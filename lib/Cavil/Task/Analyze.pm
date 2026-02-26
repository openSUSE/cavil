# Copyright (C) 2018-2024 SUSE LLC
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
use Mojo::Base 'Mojolicious::Plugin', -signatures;

use Cavil::Licenses   qw(lic);
use Cavil::ReportUtil qw(report_checksum report_shortname summary_delta summary_delta_score);
use Mojo::JSON        qw(to_json);
use List::Util        qw(uniq);

sub register ($self, $app, $config) {
  $app->minion->add_task(analyze  => \&_analyze);
  $app->minion->add_task(analyzed => \&_analyzed);
}

sub _analyze ($job, $id) {
  my $app    = $job->app;
  my $minion = $app->minion;
  my $pkgs   = $app->packages;
  my $log    = $app->log;
  my $config = $app->config;

  # Protect from race conditions
  return $job->finish("Package $id is not indexed yet") unless $pkgs->is_indexed($id);
  return $job->finish("Package $id is already being processed")
    unless my $guard = $minion->guard("processing_pkg_$id", 172800);

  $app->plugins->emit_hook('before_task_analyze');
  $app->pg->db->update('bot_reports', {ldig_report => undef}, {package => $id});

  my $reports  = $app->reports;
  my $pkg      = $pkgs->find($id);
  my $specfile = $reports->specfile_report($id);
  my $dig      = $reports->dig_report($id);

  my $chksum    = report_checksum($specfile, $dig);
  my $shortname = report_shortname($reports->shortname($chksum), $specfile, $dig);
  my $flags     = $pkgs->flags($id);

  # Free up memory
  undef $specfile;

  my $new_candidates = [];

  # Unresolved keyword matches
  my $unresolved = 0;
  if (my $snippets = $dig->{snippets}) {
    my @all;
    for my $file (keys %$snippets) {
      push @all, values %{$snippets->{$file}};
    }
    $unresolved = scalar uniq @all;
  }

  # Do not leak Postgres connections
  {
    my $db = $app->pg->db;
    $db->update('bot_packages', {checksum => $shortname, unresolved_matches => $unresolved, %$flags}, {id => $id});
    $db->update('bot_reports', {ldig_report => to_json($dig)}, {package => $id});
    if ($pkg->{state} ne 'new') {

      # in case we reindexed an old pkg, check if 'new' packages now match.
      # new patterns might change the story
      $new_candidates = $db->select('bot_packages', 'id',
        {name => $pkg->{name}, indexed => {'!=' => undef}, id => {'!=' => $pkg->{id}}, state => 'new'})->hashes;
    }
  }

  undef $guard;
  my $prio = $job->info->{priority};
  my $analyzed_id
    = $minion->enqueue(analyzed => [$id] => {parents => [$job->id], priority => $prio, notes => {"pkg_$id" => 1}});
  $pkgs->generate_spdx_report($id, {parents => [$analyzed_id]}) if $config->{always_generate_spdx_reports};

  for my $candidate (@$new_candidates) {
    $minion->enqueue(
      analyzed => [$candidate->{id}] => {parents => [$job->id], priority => 9, notes => {"pkg_$id" => 1}});
  }
  $log->info("[$id] Analyzed $shortname");
}

sub _analyzed ($job, $id) {
  my $app     = $job->app;
  my $config  = $app->config;
  my $minion  = $app->minion;
  my $reports = $app->reports;
  my $pkgs    = $app->packages;

  # Protect from race conditions
  return $job->finish("Package $id is not indexed yet") unless $pkgs->is_indexed($id);
  return $job->finish("Package $id is already being processed")
    unless my $guard = $minion->guard("processing_pkg_$id", 172800);

  # Only "new" and "acceptable" can be reviewed automatically
  my $pkg = $pkgs->find($id);
  return unless my $pkg_shortname = $pkg->{checksum};
  return unless $pkg->{indexed};
  return if $pkg->{state} ne 'new' && $pkg->{state} ne 'acceptable';

  # Incomplete checkout
  my $specfile = $reports->specfile_report($id);
  if ($specfile->{incomplete_checkout}) {
    _look_for_smallest_delta($app, $pkg, 0, 0, 1) if $pkg->{state} eq 'new';
    return;
  }

  # Every package above threshold needs a human review before future versions can be auto-accepted
  if (!$pkgs->has_manual_review($pkg->{name})) {

    my $auto_accept_risk = $config->{auto_accept_risk};
    my $risk             = $reports->risk_is_acceptable($pkg_shortname);
    if (defined($risk) && $risk > 0 && $auto_accept_risk && $risk <= $auto_accept_risk) {
      $pkg->{state}            = 'acceptable';
      $pkg->{review_timestamp} = 1;
      $pkg->{reviewing_user}   = undef;
      $pkg->{result} = "Accepted because of low risk ($risk) and auto-accept risk threshold ($auto_accept_risk)";
      $pkgs->update($pkg);
      return;
    }

    _look_for_smallest_delta($app, $pkg, 0, 0, 0) if $pkg->{state} eq 'new';
    return;
  }

  # Fast-track packages that are configured to always be acceptable
  my $name                = $pkg->{name};
  my $acceptable_packages = $config->{acceptable_packages} || [];
  if (grep { $name eq $_ } @$acceptable_packages) {
    $pkg->{state}            = 'acceptable';
    $pkg->{review_timestamp} = 1;
    $pkg->{reviewing_user}   = undef;
    $pkg->{result}           = "Accepted because of package name ($name)";
    $pkgs->update($pkg);
    return;
  }

  # Exclude "unacceptable" reviews
  my $packages = $pkgs->history($name, $pkg_shortname, $id);
  return if grep { $_->{state} eq 'unacceptable' } @$packages;

  my ($found_acceptable_by_lawyer, $found_acceptable);
  for my $p (@$packages) {

    # ignore obsolete reviews - possibly harmful as we don't reindex those
    next                                   if $p->{obsolete};
    $found_acceptable_by_lawyer = $p->{id} if $p->{state} eq 'acceptable_by_lawyer';
    last                                   if $found_acceptable_by_lawyer;
    $found_acceptable = $p->{id}           if $p->{state} eq 'acceptable';
  }

  # Try to upgrade from "acceptable" to "acceptable_by_lawyer"
  if ($pkg->{state} eq 'acceptable') {
    if (my $c_id = $found_acceptable_by_lawyer) {
      $pkg->{state}            = 'acceptable_by_lawyer';
      $pkg->{review_timestamp} = 1;
      $pkg->{reviewing_user}   = undef;
      $pkg->{ai_assisted}      = 0;
      $pkg->{result}           = "Accepted because reviewed by lawyer under the same license ($c_id)";
      $pkgs->update($pkg);
    }
    return;    # the rest is for 'new'
  }

  # Previously reviewed and accepted
  if (my $f_id = $found_acceptable_by_lawyer || $found_acceptable) {
    $pkg->{state}            = $found_acceptable_by_lawyer ? 'acceptable_by_lawyer' : 'acceptable';
    $pkg->{review_timestamp} = 1;
    $pkg->{reviewing_user}   = undef;
    $pkg->{result}           = "Accepted because previously reviewed under the same license ($f_id)";
    $pkgs->update($pkg);
    return;
  }

  # Acceptable risk
  if (defined(my $risk = $reports->risk_is_acceptable($pkg_shortname))) {

    # risk 0 is spooky
    unless ($risk) {
      $pkg->{result} = undef;
      $pkg->{notice} = 'Manual review is required because of unusually low risk (0)';
      $pkgs->update($pkg);
      return;
    }

    $pkg->{state}            = 'acceptable';
    $pkg->{review_timestamp} = 1;
    $pkg->{reviewing_user}   = undef;
    $pkg->{result}           = "Accepted because of low risk ($risk)";
    $pkgs->update($pkg);
  }

  _look_for_smallest_delta($app, $pkg, 1, 1, 0) if $pkg->{state} eq 'new';
}

sub _look_for_smallest_delta ($app, $pkg, $allow_accept, $has_manual_review, $incomplete_checkout) {
  my $reports = $app->reports;
  my $pkgs    = $app->packages;

  my $older_reviews = $pkgs->old_reviews($pkg);
  my $new_summary   = $reports->summary($pkg->{id});

  my $best_score;
  my $best;
  my %checked;
  for my $old (@$older_reviews) {
    next if $checked{$old->{checksum}};
    my $old_summary = $reports->summary($old->{id});
    my $score       = summary_delta_score($old_summary, $new_summary);

    # don't look further
    if (!$score) {
      $pkg->{result} = undef;
      if ($allow_accept) {
        $pkg->{result}           = "Accepted because of no significant difference ($old->{id})";
        $pkg->{state}            = 'acceptable';
        $pkg->{review_timestamp} = 1;
        $pkg->{reviewing_user}   = undef;
      }

      $pkg->{notice} = "Not found any significant difference against $old->{id}";
      if ($incomplete_checkout) {
        $pkg->{notice} .= ', manual review is required because the checkout might be incomplete';
      }
      elsif (!$has_manual_review) {
        $pkg->{notice} .= ', manual review is required because previous reports are missing a reviewing user';
      }

      $pkgs->update($pkg);
      return;
    }

    $checked{$old->{checksum}} = 1;
    if (!$best || $score < $best_score) {
      $best       = $old_summary;
      $best_score = $score;
    }
  }

  unless ($best) {
    $pkg->{result} = undef;
    $pkg->{notice} = 'Manual review is required because no previous reports are available';
    $pkgs->update($pkg);
    return;
  }

  $pkgs->update({id => $pkg->{id}, result => undef, notice => summary_delta($best, $new_summary)});
}

1;
