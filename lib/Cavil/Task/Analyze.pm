# Copyright (C) 2018,2019 SUSE Linux GmbH
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, see <http://www.gnu.org/licenses/>.

package Cavil::Task::Analyze;
use Mojo::Base 'Mojolicious::Plugin';

use Cavil::Licenses 'lic';
use Mojo::JSON 'to_json';

sub register {
  my ($self, $app) = @_;
  $app->minion->add_task(analyze  => \&_analyze);
  $app->minion->add_task(analyzed => \&_analyzed);
}

sub _analyze {
  my ($job, $id) = @_;

  my $app = $job->app;
  my $log = $app->log;
  $app->plugins->emit_hook('before_task_analyze');

  my $reports  = $app->reports;
  my $pkg      = $app->packages->find($id);
  my $specfile = $reports->specfile_report($id);
  my $dig      = $reports->dig_report($id);

  my $chksum    = $app->checksum($specfile, $dig);
  my $shortname = _shortname($app->pg->db, $chksum, $specfile, $dig);

  # Free up memory
  undef $specfile;

  my $new_candidates = [];

  # Do not leak Postgres connections
  {
    my $db = $app->pg->db;
    $db->update('bot_packages', {checksum => $shortname}, {id => $id});
    $db->update('bot_reports', {ldig_report => to_json($dig)},
      {package => $id});
    if ($pkg->{state} ne 'new') {

      # in case we reindexed an old pkg, check if 'new' packages now match.
      # new patterns might change the story
      $new_candidates = $db->select(
        'bot_packages',
        'id',
        {
          name    => $pkg->{name},
          indexed => { '!=' => undef },
          id      => {'!=' => $pkg->{id}},
          state   => 'new'
        }
      )->hashes;
    }
  }

  my $prio = $job->info->{priority};
  $app->minion->enqueue(
    analyzed => [$id] => {parents => [$job->id], priority => $prio});

  for my $candidate (@$new_candidates) {
    $app->minion->enqueue(
      analyzed => [$candidate->{id}] => {parents => [$job->id], priority => 9});
  }
  $log->info("[$id] Analyzed $shortname");
}

sub _analyzed {
  my ($job, $id) = @_;

  my $app     = $job->app;
  my $reports = $app->reports;
  my $pkgs    = $app->packages;

  # Only "new" and "acceptable" can be reviewed automatically
  my $pkg = $pkgs->find($id);
  return unless my $pkg_shortname = $pkg->{checksum};
  return unless $pkg->{indexed};
  return if $pkg->{state} ne 'new' && $pkg->{state} ne 'acceptable';

  # Exclude "unacceptable" reviews
  my $packages = $pkgs->history($pkg->{name}, $pkg_shortname, $id);
  return if grep { $_->{state} eq 'unacceptable' } @$packages;

  my ($found_correct, $found_acceptable);
  for my $p (@$packages) {

    # ignore obsolete reviews - possibly harmful as we don't reindex those
    next if $p->{obsolete};
    $found_correct = $p->{id} if $p->{state} eq 'correct';
    last if $found_correct;
    $found_acceptable = $p->{id} if $p->{state} eq 'acceptable';
  }

  # Try to upgrade from "acceptable" to "correct"
  if ($pkg->{state} eq 'acceptable') {
    if (my $c_id = $found_correct) {
      $pkg->{state}            = 'correct';
      $pkg->{review_timestamp} = 1;
      $pkg->{reviewing_user}   = undef;
      $pkg->{result}
        = "Correct because reviewed under the same license ($c_id)";
      return $pkgs->update($pkg);
    }
  }

  # Previously reviewed and accepted
  if (my $f_id = $found_correct || $found_acceptable) {
    $pkg->{state}            = $found_correct ? 'correct' : 'acceptable';
    $pkg->{review_timestamp} = 1;
    $pkg->{result}
      = "Accepted because previously reviewed under the same license ($f_id)";
    return $pkgs->update($pkg);
  }

  # Acceptable risk
  if (defined(my $risk = $reports->risk_is_acceptable($pkg_shortname))) {

    # risk 0 is spooky
    return unless $risk;
    $pkg->{state}            = 'acceptable';
    $pkg->{review_timestamp} = 1;
    $pkg->{result}           = "Accepted because of low risk ($risk)";
    $pkgs->update($pkg);
  }

  _look_for_smallest_delta($app, $pkg) if $pkg->{state} eq 'new';
}

sub _look_for_smallest_delta {
  my ($app, $pkg) = @_;

  my $db      = $app->pg->db;
  my $reports = $app->reports;

  my $older_reviews = $db->select(
    'bot_packages',
    'id,checksum',
    {
      name     => $pkg->{name},
      state    => [qw(acceptable correct)],
      id       => {'!=' => $pkg->{id}},
      obsolete => 0,
      indexed  => {'!=' => undef}
    },
    {-desc => 'id'}
  );

  my $new_summary = _review_summary($db, $reports, $pkg->{id});

  my $best_score;
  my $best;
  my %checked;
  for my $old (@{$older_reviews->hashes}) {
    next if $checked{$old->{checksum}};
    say "compare $old->{id}->$pkg->{id}";
    my $old_summary = _review_summary($db, $reports, $old->{id});
    my $score       = _summary_delta_score($old_summary, $new_summary);
    if (!$score) {

      # don't look further
      $pkg->{state}            = 'acceptable';
      $pkg->{review_timestamp} = 1;
      $pkg->{result} = "Not found any signficant difference against $old->{id}";
      $app->packages->update($pkg);
      return;
    }
    $checked{$old->{checksum}} = 1;
    if (!$best || $score < $best_score) {
      $best       = $old_summary;
      $best_score = $score;
    }
  }
  return unless $best;
  $app->pg->db->update(
    'bot_packages',
    {result => _summary_delta($best, $new_summary, $best_score)},
    {id     => $pkg->{id}}
  );
}

sub _find_report_summary {
  my ($db, $chksum) = @_;

  my $lentry
    = $db->select('report_checksums', 'shortname', {checksum => $chksum})->hash;
  if ($lentry) {
    return $lentry->{shortname};
  }

  # try to find a unique name for the checksum
  my $chars = ['a' .. 'z', 'A' .. 'Z', '0' .. '9'];
  while (1) {
    my $shortname = join('', map { $chars->[rand @$chars] } 1 .. 4);
    $db->query(
      'insert into report_checksums (checksum, shortname)
       values (?,?) on conflict do nothing', $chksum, $shortname
    );
    return $shortname
      if $db->select('report_checksums', 'id',
      {shortname => $shortname, checksum => $chksum})->hash;
  }
}

sub _shortname {
  my ($db, $chksum, $specfile, $report) = @_;

  my $chksum_summary = _find_report_summary($db, $chksum);

  my $max_risk = 0;
  for my $risk (keys %{$report->{risks}}) {
    $max_risk = $risk if $risk > $max_risk;
  }
  $max_risk = 9 if %{$report->{missed_snippets}};

  my $l = lic($specfile->{main}{license})->example;
  $l ||= 'Error';

  return "$l-$max_risk:$chksum_summary";
}

sub _review_summary {
  my ($db, $reports, $id) = @_;

  my %summary  = (id => $id);
  my $specfile = $reports->specfile_report($id);
  $summary{specfile}
    = lic($specfile->{main}{license})->canonicalize->to_string || 'Error';
  my $report = $reports->dig_report($id);

  my $min_risklevel = 1;

  # it's a bit random but the risk levels are defined a little random too
  $min_risklevel = 2 if $report->{risks}{3};
  $summary{licenses} = {};
  for my $license (sort { $a cmp $b } keys %{$report->{licenses}}) {
    next if $report->{licenses}{$license}{risk} < $min_risklevel;
    my $text = "$license";
    for my $flag (@{$report->{licenses}{$license}{flags}}) {
      $text .= ":$flag";
    }
    $summary{licenses}{$text} = $report->{licenses}{$license}{risk};
  }
  my @files = map {
    $db->select('matched_files', 'filename', {id => $_})->hash->{filename}
  } keys %{$report->{snippets}};
  $summary{missed_snippets} = \@files;
  return \%summary;
}

sub _summary_delta_score {
  my ($old, $new) = @_;

  # not an option
  if ($new->{specfile} ne $old->{specfile}) {
    return 1000;
  }

  my $score = 0;

  # if the old had missed, the new ones don't matter
  unless (@{$old->{missed_snippets}}) {
    $score = scalar(@{$new->{missed_snippets}});
  }

  # copy
  my %lics = %{$new->{licenses}};
  for my $lic (keys %{$old->{licenses}}) {
    delete $lics{$lic};
  }
  map { $score += $_ * 10 } values %lics;
  return $score;
}

sub _summary_delta {
  my ($old, $new, $score) = @_;

  my $text = "Diff to closest match $old->{id}:\n\n";

  if ($new->{specfile} ne $old->{specfile}) {
    $text .= "  Different spec file license: $old->{specfile}\n\n";
  }

  # if the old had missed, the new ones don't matter
  if (!@{$old->{missed_snippets}} && @{$new->{missed_snippets}}) {
    my @snips = @{$new->{missed_snippets}};
    $text .= "  New missed snippet in " . (shift @snips);
    if (@snips) {
      $text .= " and " . (scalar @snips) . " files more";
    }
    $text .= "\n\n";
  }

  # copy
  my %lics = %{$new->{licenses}};
  for my $lic (keys %{$old->{licenses}}) {
    delete $lics{$lic};
  }
  for my $lic (keys %lics) {
    $text
      .= "  Found new license $lic (risk $lics{$lic}) not present in old report\n";
  }
  say $text;
  return $text;
}

1;
