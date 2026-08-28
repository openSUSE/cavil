# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Builds the code search fingerprint index off the indexing hot path. Indexing only records a content
# hash per file (see Cavil::FileIndexer); this task winnows the not-yet-fingerprinted contents into the
# Postgres inverted index in batches, then prunes stopwords and bumps the generation. A single-flight guard
# keeps one builder running at a time.

package Cavil::Task::Fingerprint;
use Mojo::Base 'Mojolicious::Plugin', -signatures;

sub register ($self, $app, $config) {
  $app->minion->add_task(fingerprint_build => \&_fingerprint_build);
}

sub _fingerprint_build ($job, $opts = {}) {
  my $app = $job->app;
  return $job->finish('Code search is disabled') unless $app->codesearch;
  return $job->finish('Fingerprint build already in progress')
    unless my $guard = $app->minion->guard('fingerprint_build', 7200);

  my $fp = $app->fingerprints;
  $fp->reset_index if $opts->{rebuild};    # discard the index first (a k/w change or forced rebuild), under the guard
  my $total = 0;
  while (my $n = $fp->build_pending) { $total += $n }
  $fp->refresh_stopwords;                  # prune ubiquitous fingerprints out of the index
  $fp->bump_generation;                    # invalidate client search caches: the corpus changed
  $job->note(fingerprinted => $total);
}

1;
