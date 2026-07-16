# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package Cavil::Command::unpack;
use Mojo::Base 'Mojolicious::Command', -signatures;

use Getopt::Long qw(GetOptionsFromArray);

has description => 'Unpack sources';
has usage       => sub ($self) { $self->extract_usage };

sub run ($self, @args) {
  my ($rebatch, $batch, $priority);
  GetOptionsFromArray(\@args, 'rebatch:i' => \$rebatch, 'batch=i' => \$batch, 'priority=i' => \$priority);

  return $self->_rebatch($rebatch, $batch // 500, $priority // 0) if defined $rebatch;

  my $id = shift @args;
  die "ID is required.\n" unless $id;

  my $app    = $self->app;
  my $minion = $app->minion;
  if ($minion->is_locked("processing_pkg_$id")) {
    print STDOUT "Releasing locks for package $id\n";
    $minion->unlock("processing_pkg_$id");
  }

  if   (my $job = $app->packages->unpack($id)) { print STDOUT "Triggered unpack job $job\n" }
  else                                         { print STDOUT "Unpacking already in progress\n" }
}

# Re-unpack one batch of the oldest non-obsolete packages after $offset, at a low
# priority so the catch-up yields to live review traffic. Re-unpacking cascades through
# index/analyze/report, so this is how a preprocessing change (e.g. markup stripping)
# is rolled out gradually: call it, let the workers drain, then call again with the
# printed "Next offset" when workload allows.
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
                            at a low priority and cascade through index/analyze/report.
        --batch <n>         Packages per batch (default: 500)
        --priority <n>      Minion priority for the enqueued jobs (default: 0, below the
                            normal unpack priority of 5)
    -h, --help              Show this summary of available options

=cut
