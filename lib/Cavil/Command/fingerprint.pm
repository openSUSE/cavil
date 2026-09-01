# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package Cavil::Command::fingerprint;
use Mojo::Base 'Mojolicious::Command', -signatures;

use Cavil::Util qw(PRIORITY_SWEEP);
use Mojo::Util  qw(getopt);

has description => 'Build the code search fingerprint index';
has usage       => sub ($self) { $self->extract_usage };

sub run ($self, @args) {
  getopt \@args, 'rebuild' => \my $rebuild;

  my $app = $self->app;
  die "Code search is disabled (enable it in the config).\n" unless $app->codesearch;

  # The build can run for hours, so it is a Minion job (memory limits, retries, single-flight guard); a
  # worker does the work. --rebuild discards the index first, inside the job. Sweep priority, or it waits
  # behind every reindex the weekly sweep queues up.
  my $id = $app->minion->enqueue('fingerprint_build', [{rebuild => $rebuild ? 1 : 0}], {priority => PRIORITY_SWEEP});
  print "Queued code search fingerprint build as job $id", ($rebuild ? ' (rebuild)' : ''), ".\n";
}

1;

=encoding utf8

=head1 NAME

Cavil::Command::fingerprint - Build the code search fingerprint index

=head1 SYNOPSIS

  Usage: APPLICATION fingerprint [OPTIONS]

    script/cavil fingerprint
    script/cavil fingerprint --rebuild

  Options:
    --rebuild   Discard the index and rebuild it from scratch. Use after changing the winnowing
                parameters (k/w) in the config, or to force a clean rebuild.

  Queues a Minion job (a worker does the work, which can take a while); without options it fingerprints
  every indexed content not yet in the index. Neither mode touches the database directly.

=cut
