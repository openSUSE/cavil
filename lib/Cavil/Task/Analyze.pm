# Copyright (C) 2018 SUSE Linux GmbH
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
  my $specfile = $reports->specfile_report($id);
  my $dig      = $reports->dig_report($id);

  my $chksum = $app->checksum($specfile, $dig);
  my $shortname = _shortname($app->pg->db, $chksum, $specfile, $dig);

  # Free up memory
  undef $specfile;

  my $db = $app->pg->db;
  $db->update('bot_packages', {checksum    => $shortname},    {id      => $id});
  $db->update('bot_reports',  {ldig_report => to_json($dig)}, {package => $id});

  my $prio = $job->info->{priority};
  $app->minion->enqueue(
    analyzed => [$id] => {parents => [$job->id], priority => $prio});

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
  return if $pkg->{state} ne 'new' && $pkg->{state} ne 'acceptable';

  # Exclude "unacceptable" reviews
  my $packages = $pkgs->history($pkg->{name}, $pkg_shortname, $id);
  return if grep { $_->{state} eq 'unacceptable' } @$packages;

  my ($found_correct, $found_acceptable);
  for my $p (@$packages) {
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
    }
  }

  # Previously reviewed and accepted
  elsif (my $f_id = $found_correct || $found_acceptable) {
    $pkg->{state} = $found_correct ? 'correct' : 'acceptable';
    $pkg->{review_timestamp} = 1;
    $pkg->{result}
      = "Accepted because previously reviewed under the same license ($f_id)";
  }

  # Acceptable risk
  elsif (defined(my $risk = $reports->risk_is_acceptable($pkg_shortname))) {
    $pkg->{state}            = 'acceptable';
    $pkg->{review_timestamp} = 1;
    $pkg->{result}           = "Accepted because of low risk ($risk)";
  }

  $pkgs->update($pkg) if $pkg->{state} ne 'new';
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
  my $l = lic($specfile->{main}{license})->example;
  $l ||= 'Error';

  return "$l-$max_risk:$chksum_summary";
}

1;
