# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package Cavil::Command::unpack;
use Mojo::Base 'Mojolicious::Command', -signatures;

use Getopt::Long qw(GetOptionsFromArray);
use Cavil::Util  qw(PRIORITY_SWEEP PRIORITY_WAITING);

has description => 'Unpack sources';
has usage       => sub ($self) { $self->extract_usage };

sub run ($self, @args) {
  my ($rebatch, $batch, $priority);
  GetOptionsFromArray(\@args, 'rebatch:i' => \$rebatch, 'batch=i' => \$batch, 'priority=i' => \$priority);

  return $self->_rebatch($rebatch, $batch // 500, $priority // PRIORITY_SWEEP) if defined $rebatch;

  my $id = shift @args;
  die "ID is required.\n" unless $id;

  my $app  = $self->app;
  my $pkgs = $app->packages;
  print STDOUT "Releasing package $id\n" if $pkgs->force_release($id);

  # Manual recovery should not wait behind unattended work.
  if   (my $job = $pkgs->unpack($id, PRIORITY_WAITING)) { print STDOUT "Triggered unpack job $job\n" }
  else                                                  { print STDOUT "Unpacking already in progress\n" }
}

# Batch preprocessing migrations at sweep priority so live reviews retain precedence.
sub _rebatch ($self, $offset, $batch, $priority) {
  my $app = $self->app;

  my $ids = $app->pg->db->query('SELECT id FROM bot_packages WHERE obsolete IS NOT TRUE AND id > ? ORDER BY id LIMIT ?',
    $offset, $batch)->arrays->flatten->to_array;

  if (!@$ids) {
    say "Caught up - no non-obsolete packages after id $offset.";
    return;
  }

  my $packages = $app->packages;
  my $enqueued = 0;
  my $last     = $offset;
  for my $id (@$ids) {
    $last = $id;
    $enqueued++ if $packages->unpack($id, $priority);
  }

  say "Enqueued $enqueued re-unpack job(s) at priority $priority (through id $last).";
  say "Next offset: $last";
}

1;

=encoding utf8

=head1 NAME

Cavil::Command::unpack - Cavil unpack command

=head1 SYNOPSIS

  Usage: APPLICATION unpack [OPTIONS] [ID]

    # Re-unpack a single package
    script/cavil unpack 12345

    # Re-unpack the oldest non-obsolete packages in paced batches (for rolling out a
    # preprocessing change). Start at the beginning, 500 packages at a time:
    script/cavil unpack --rebatch
    # ...then continue from the "Next offset" it printed, when workload allows:
    script/cavil unpack --rebatch 67890 --batch 1000

  Options:
        --rebatch [offset]  Re-unpack one batch of the oldest non-obsolete packages
                            with id greater than [offset] (default: 0), then print the
                            newest id as the offset for the next call. Jobs are enqueued
                            at the sweep priority band and cascade through
                            index/analyze/report.
        --batch <n>         Packages per batch (default: 500)
        --priority <n>      Minion priority for the enqueued jobs (default: 20, the sweep
                            band, below everything a reviewer or an import is waiting on)
    -h, --help              Show this summary of available options

=cut
