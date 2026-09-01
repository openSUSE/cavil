# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Builds the code search fingerprint index off the indexing hot path. Indexing only records a content
# hash per file (see Cavil::FileIndexer); this task prunes content whose files are all gone, winnows the
# not-yet-fingerprinted contents into the Postgres inverted index in batches, then refreshes the stopword set
# and bumps the generation. Schedule it on its own (see docs/Maintenance.md).
#
# codesearch.workers > 1 splits the work into that many shard jobs. Unlike the indexing fan-out this needs no
# claim and no finisher: a shard's unit of work is one row whose "indexed" flag flips with its arrays, so a dead
# shard only leaves them pending for the next build.

package Cavil::Task::Fingerprint;
use Mojo::Base 'Mojolicious::Plugin', -signatures;

use Cavil::Util qw(PRIORITY_SWEEP);
use Mojo::Util  qw(scope_guard steady_time);

# One lock per shard, renewed as it runs: Minion locks only expire, and a build outlives any fixed TTL. Not one
# lock across the whole build - a lock shared between jobs is what made the indexing fan-out painful to restart.
use constant LOCK_TTL => 3600;

sub _lock ($shard) { return "fingerprint_build_$shard" }

sub register ($self, $app, $config) {
  $app->minion->add_task(fingerprint_build => \&_fingerprint_build);
}

sub _fingerprint_build ($job, $opts = {}) {
  my $app = $job->app;
  return $job->finish('Code search is disabled') unless my $cfg = $app->codesearch;

  my $minion = $app->minion;
  my $fp     = $app->fingerprints;

  # The entry point (no shard of its own) does what has to happen once, then splits or builds.
  my $pruned;
  unless (defined $opts->{shard}) {
    my $workers = $cfg->{workers} || 1;

    # Resetting would pull the index out from under any shard still writing to it.
    if ($opts->{rebuild}) {
      return $job->finish('Cannot rebuild while a build is running')
        if grep { $minion->is_locked(_lock($_)) } 0 .. $workers - 1;
      $fp->reset_index;
    }

    # Here rather than per shard, so concurrent identical deletes cannot collide.
    $pruned = $fp->prune_contents;

    if ($workers > 1) {
      $minion->enqueue(fingerprint_build => [{shard => $_, shards => $workers}] => {priority => PRIORITY_SWEEP})
        for 0 .. $workers - 1;
      return $job->finish("Split into $workers shards, pruned $pruned orphaned contents");
    }
  }

  my ($shard, $shards) = ($opts->{shard} // 0, $opts->{shards} // 1);
  my $lock = _lock($shard);
  return $job->finish("Shard $shard is already being built") unless $minion->lock($lock, LOCK_TTL);
  my $unlock   = scope_guard sub { $minion->unlock($lock) };
  my $renew_at = steady_time + LOCK_TTL / 2;

  my $total = 0;
  while (my $n = $fp->build_pending($shard, $shards)) {
    $total += $n;

    if (steady_time > $renew_at) {
      $minion->unlock($lock);
      $minion->lock($lock, LOCK_TTL);
      $renew_at = steady_time + LOCK_TTL / 2;
      $job->note(fingerprinted => $total);
    }
  }

  # Once, at the end, and only in whichever shard wins the race for it (see refresh_stopwords). Not during the
  # build: that was worth its cost only before the probe limit made an unpruned fingerprint merely slower to
  # read rather than able to drag the whole corpus into a search.
  $fp->refresh_stopwords;
  $fp->bump_generation;
  $job->note(fingerprinted => $total, defined $pruned ? (pruned => $pruned) : ());
}

1;
