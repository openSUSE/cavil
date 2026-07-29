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

package Cavil::Task::Cleanup;
use Mojo::Base 'Mojolicious::Plugin', -signatures;

use Cavil::Util;
use Mojo::File 'path';

sub register ($self, $app, $config) {
  $app->minion->add_task(obsolete      => \&_obsolete);
  $app->minion->add_task(cleanup       => \&_cleanup);
  $app->minion->add_task(cleanup_batch => \&_cleanup_batch);
}

sub _cleanup ($job) {
  my $app  = $job->app;
  my $pkgs = $app->packages;

  _sweep_builds($app);

  $pkgs->obsolete_duplicate_new;
  my $ids     = $pkgs->need_cleanup;
  my $buckets = Cavil::Util::buckets($ids, $app->config->{cleanup_bucket_average});

  my $minion = $app->minion;
  $minion->enqueue('cleanup_batch', $_, {parents => [$job->id], priority => 1}) for @$buckets;
}

sub _cleanup_batch ($job, @ids) {
  my $pkgs = $job->app->packages;
  for my $id (@ids) { $pkgs->cleanup($id, $job->id) }
}

# Recover from reindexes that died halfway: a worker that was killed, a job that failed and was removed
# from the queue, a build that "script/cavil unpack" force-released and superseded. Their rows are
# invisible to readers (only generation 0 is the report), so nothing is broken while they sit there - but
# they cost disk, and they leave the package claimed by a job that no longer exists, looking like it is
# forever rebuilding.
#
# A package is only touched once Minion says nothing is queued or running for it, which is what makes
# this safe: with no job for the package there is nobody left who could be writing those rows.
sub _sweep_builds ($app) {
  my $minion = $app->minion;
  my $pkgs   = $app->packages;
  my $log    = $app->log;

  for my $id (@{$pkgs->unsettled_builds}) {
    next if $minion->jobs({notes => ["pkg_$id"], states => ['inactive', 'active']})->total;

    # Whoever owns the package has no job left in the queue to show for it, so take it over - but only if
    # it is still exactly this owner, so a build that starts in the gap keeps its claim and its rows
    my $owner = $pkgs->find($id)->{processing_job};
    next unless defined(my $deleted = $pkgs->discard_builds($id, $owner));
    $log->info("[$id] Discarded $deleted rows from an abandoned reindex") if $deleted;

    # The reindex the abandoned build was meant to deliver still has to happen, and so does any request
    # that came in while it was running. reindex() enqueues one job for both.
    next unless $deleted || $pkgs->reindex_requested($id);
    $pkgs->clear_reindex_request($id);

    # A package that has no report yet is not a reindex candidate at all (reindex only takes indexed
    # packages), so an import whose very first build died is indexed from scratch instead
    my $requeued;
    if    ($pkgs->is_indexed($id))                              { $requeued = ($pkgs->reindex($id, 3) // '') eq 'now' }
    elsif (!$pkgs->is_obsolete($id) && $pkgs->is_unpacked($id)) { $requeued = $pkgs->index($id, 3) }
    $log->info("[$id] Requeueing the build it never finished") if $requeued;
  }
}

sub _obsolete ($job) {
  my $app    = $job->app;
  my $config = $app->config;
  $app->packages->obsolete_old_packages($config->{days_to_keep_orphaned_packages},
    $config->{days_to_keep_orphaned_duplicate_packages});
  $app->minion->enqueue('cleanup' => [] => {parents => [$job->id]});
}

1;
