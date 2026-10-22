# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package Cavil::Command::setup;
use Mojo::Base 'Mojolicious::Command', -signatures;

use Cavil::Status;
use Mojo::Util qw(getopt);

has description => 'Prepare the database of a new or upgraded instance';
has usage       => sub ($self) { $self->extract_usage };

sub run ($self, @args) {
  my $app  = $self->app;
  my $sync = $app->sync;
  getopt \@args, 'p|patterns=s' => \(my $file = $sync->shipped);

  my $migrations = $app->pg->migrations;
  my ($before, $latest) = ($migrations->active, $migrations->latest);
  if ($before == $latest) { say 'Database is up to date' }
  else {
    my $busy = $app->status->busy;
    die <<"EOF" if $busy->{jobs} || $busy->{workers};
Refusing to update the database from version $before to $latest while $busy->{workers} workers are running and
$busy->{jobs} jobs are queued or active, because they could run old code against the new schema. Stop the web
application, wait until the queue is empty, stop all workers, then run setup again. A worker that died without
shutting down counts as running until its last heartbeat is @{[$app->minion->missing_after / 60]} minutes old.
EOF
    $migrations->migrate;
    say "Updated database from version $before to $latest";
  }

  if ($app->pg->db->query('SELECT 1 FROM license_patterns LIMIT 1')->rows) {
    my $unknown = $sync->pending($file);
    say $unknown
      ? qq{$unknown shipped license patterns are not part of this instance, see "script/cavil sync --help"}
      : 'License patterns are up to date';
  }
  else { say 'Imported ' . $sync->load($file) . ' license patterns' }

  my $minion = $app->minion;
  my $added  = 0;
  for my $schedule (@Cavil::Status::SCHEDULES) {
    my ($name, $cron, $task) = @$schedule;
    next if $minion->list_schedules(0, 1, {names => [$name]})->{total};
    $minion->schedule($name, $cron, $task);
    say qq{Scheduled "$task" as "$name" ($cron)};
    $added++;
  }
  say 'Maintenance schedules are up to date' unless $added;
}

1;

=encoding utf8

=head1 NAME

Cavil::Command::setup - Cavil setup command

=head1 SYNOPSIS

  Usage: APPLICATION setup [OPTIONS]

    script/cavil setup

  Brings the database of a new or upgraded instance up to date, safe to run as often as you like: updates the
  schema, loads the shipped license patterns into an empty instance and schedules the maintenance tasks that are
  not scheduled yet (pause a schedule to disable it, a removed one comes back). Refuses to update the schema while
  workers are running or jobs are queued.

  Options:
    -p, --patterns <file>   License patterns to load into an empty instance, defaults to the shipped ones
    -h, --help              Show this summary of available options

=cut
