# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Builds the code search fingerprint index off the indexing hot path. Indexing only records a content
# hash per file (see Cavil::FileIndexer); this task prunes content whose files are all gone, winnows the
# not-yet-fingerprinted contents into the Postgres inverted index in batches, refreshing the stopword set as it
# goes, then bumps the generation. Schedule it on its own (see docs/Maintenance.md).
#
# With codesearch.workers above 1 the scheduled job becomes an entry point that splits the work into that many
# shard jobs and lets Minion run them side by side (measured 1.9x with 4). It needs none of the machinery the
# package indexing fan-out has - no claim, no finisher, no state column - because a shard's unit of work is one
# fp_contents row whose "indexed" flag flips in the same transaction as its arrays. A shard that dies simply
# leaves those contents pending for the next build, so there is never anything stranded to recover.

package Cavil::Task::Fingerprint;
use Mojo::Base 'Mojolicious::Plugin', -signatures;

use Cavil::Util qw(PRIORITY_SWEEP);
use Mojo::Util  qw(scope_guard steady_time);

# Each shard holds its own lock, renewed while it runs. Minion locks just expire, so a fixed one let a build that
# outlives it (a big build runs for days) acquire a second builder alongside the first, doubling the write load
# on the very index searches are trying to read. Renewing keeps one builder per shard no matter how long it
# takes, while a dead worker still releases within one TTL. Deliberately one lock per shard rather than one
# across the whole build: a lock shared by several jobs is what made the indexing fan-out painful to restart.
use constant LOCK_TTL => 3600;

sub _lock ($shard) { return "fingerprint_build_$shard" }

# Refresh the stopword set once a build has added this many contents, then on a geometric schedule. Document
# frequencies climb as contents are added, so a long build leaves newly-ubiquitous fingerprints unpruned and
# every search drags a huge candidate set out of the index - searches are unusable until the build ends. The
# threshold is what matters, not whether this is a rebuild: a big incremental build has the same problem. Small
# daily builds never reach it and just refresh once at the end, since the scan covers the whole corpus.
use constant STOPWORD_REFRESH_AFTER => 100_000;

sub register ($self, $app, $config) {
  $app->minion->add_task(fingerprint_build => \&_fingerprint_build);
}

sub _fingerprint_build ($job, $opts = {}) {
  my $app = $job->app;
  return $job->finish('Code search is disabled') unless my $cfg = $app->codesearch;

  my $minion = $app->minion;
  my $fp     = $app->fingerprints;

  # The entry point (no shard of its own) does the once-per-build work, then either splits or builds.
  my $pruned;
  unless (defined $opts->{shard}) {
    my $workers = $cfg->{workers} || 1;

    # A rebuild discards the whole index, which would pull the ground out from under any shard still writing.
    if ($opts->{rebuild}) {
      return $job->finish('Cannot rebuild while a build is running')
        if grep { $minion->is_locked(_lock($_)) } 0 .. $workers - 1;
      $fp->reset_index;
    }

    # Once per build rather than once per shard, so concurrent identical deletes cannot collide.
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

  my ($total, $next) = (0, STOPWORD_REFRESH_AFTER);
  while (my $n = $fp->build_pending($shard, $shards)) {
    $total += $n;

    # Push the lock expiry out and record progress, so a days-long build keeps its shard and stays visible.
    if (steady_time > $renew_at) {
      $minion->unlock($lock);
      $minion->lock($lock, LOCK_TTL);
      $renew_at = steady_time + LOCK_TTL / 2;
      $job->note(fingerprinted => $total);
    }

    next if $total < $next;
    $fp->refresh_stopwords;
    $next = $total * 2;
  }

  # Every shard refreshes and bumps, rather than electing one to finish: refresh_stopwords is an idempotent
  # insert, and a shard that finished early would otherwise leave the others' fingerprints unpruned until the
  # next build. Bumping the generation more than once only makes clients drop their caches again.
  $fp->refresh_stopwords;
  $fp->bump_generation;
  $job->note(fingerprinted => $total, defined $pruned ? (pruned => $pruned) : ());
}

1;
