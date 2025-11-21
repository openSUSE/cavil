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

  $pkgs->obsolete_duplicate_new;
  my $ids     = $pkgs->need_cleanup;
  my $buckets = Cavil::Util::buckets($ids, $app->config->{cleanup_bucket_average});

  my $minion = $app->minion;
  $minion->enqueue('cleanup_batch', $_, {parents => [$job->id], priority => 1}) for @$buckets;
}

sub _cleanup_batch ($job, @ids) {
  my $pkgs = $job->app->packages;
  for my $id (@ids) { $pkgs->cleanup($id) }
}

sub _obsolete ($job) {
  my $app    = $job->app;
  my $config = $app->config;
  $app->packages->obsolete_old_packages($config->{days_to_keep_orphaned_packages},
    $config->{days_to_keep_orphaned_duplicate_packages});
  $app->minion->enqueue('cleanup' => [] => {parents => [$job->id]});
}

1;
