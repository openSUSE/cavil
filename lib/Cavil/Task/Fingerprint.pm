# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Builds the code search fingerprint index off the indexing hot path. Indexing only records a content
# hash per file (see Cavil::FileIndexer); this task prunes content whose files are all gone, winnows the
# not-yet-fingerprinted contents into the Postgres inverted index in batches, refreshing the stopword set as it
# goes, then bumps the generation. Schedule it on its own (see docs/Maintenance.md); a single-flight guard keeps
# one builder running at a time.

package Cavil::Task::Fingerprint;
use Mojo::Base 'Mojolicious::Plugin', -signatures;

use Mojo::Util qw(scope_guard steady_time);

# The single-flight lock is renewed while the build runs. Minion locks just expire, so a fixed one let a build
# that outlives it (a big build runs for days) acquire a second builder alongside the first, doubling the write
# load on the very index searches are trying to read. Renewing keeps one builder no matter how long it takes,
# while a dead worker still releases within one TTL.
use constant LOCK     => 'fingerprint_build';
use constant LOCK_TTL => 3600;

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
  return $job->finish('Code search is disabled') unless $app->codesearch;

  my $minion = $app->minion;
  return $job->finish('Fingerprint build already in progress') unless $minion->lock(LOCK, LOCK_TTL);
  my $unlock   = scope_guard sub { $minion->unlock(LOCK) };
  my $renew_at = steady_time + LOCK_TTL / 2;

  my $fp = $app->fingerprints;
  $fp->reset_index if $opts->{rebuild};    # discard the index first (a k/w change or forced rebuild), under the lock
  my $pruned = $fp->prune_contents;        # drop content bookkeeping whose files are all gone

  my ($total, $next) = (0, STOPWORD_REFRESH_AFTER);
  while (my $n = $fp->build_pending) {
    $total += $n;

    # Push the lock expiry out and record progress, so a days-long build stays single-flight and visible.
    if (steady_time > $renew_at) {
      $minion->unlock(LOCK);
      $minion->lock(LOCK, LOCK_TTL);
      $renew_at = steady_time + LOCK_TTL / 2;
      $job->note(fingerprinted => $total);
    }

    next if $total < $next;
    $fp->refresh_stopwords;
    $next = $total * 2;
  }
  $fp->refresh_stopwords;    # final pass over the complete corpus
  $fp->bump_generation;      # invalidate client search caches: the corpus changed
  $job->note(fingerprinted => $total, pruned => $pruned);
}

1;
