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
  my $app = $job->app;
  my $db  = $app->pg->db;

  # Mark all duplicate new packages as obsolete (same external_link and name)
  $db->query(
    q{
      UPDATE bot_packages
      SET obsolete = true, state = 'obsolete', result = 'Obsoleted by newer package with same name and external_link'
      WHERE id IN (
        SELECT a.id FROM (
          SELECT id, ROW_NUMBER() OVER (PARTITION BY external_link, name ORDER BY id DESC) row_no
          FROM bot_packages
          WHERE state = 'new' AND external_link IS NOT NULL
        ) AS a
        WHERE row_no > 1
      );
    }
  );

  my $ids     = $db->query('select id from bot_packages where obsolete is true order by id')->arrays->flatten->to_array;
  my $buckets = Cavil::Util::buckets($ids, $app->config->{cleanup_bucket_average});

  my $minion = $app->minion;
  $minion->enqueue('cleanup_batch', $_, {parents => [$job->id], priority => 1}) for @$buckets;
}

sub _cleanup_batch ($job, @ids) {
  my $pkgs = $job->app->packages;
  for my $id (@ids) { $pkgs->cleanup($id) }
}

sub _obsolete ($job) {
  my $app = $job->app;
  my $log = $app->log;
  my $db  = $job->app->pg->db;

  my $leave_untagged_imports = 7;

  my $list = $db->query(
    "update bot_packages set obsolete = true where id in
       (select id from bot_packages
        left join bot_package_products on bot_package_products.package=bot_packages.id
        where state != 'new' and checksum is not null and
        imported < now() - Interval '$leave_untagged_imports days' and
        bot_package_products.product is null
       )"
  );

  $app->minion->enqueue('cleanup' => [] => {parents => [$job->id]});
}

1;
