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
  my $ids
    = $app->pg->db->query('select id from bot_packages where obsolete is true order by id')->arrays->flatten->to_array;
  my $buckets = Cavil::Util::buckets($ids, $app->config->{cleanup_bucket_average});

  my $minion = $app->minion;
  $minion->enqueue('cleanup_batch', $_, {parents => [$job->id], priority => 1}) for @$buckets;
}

sub _cleanup_batch ($job, @ids) {
  my $app    = $job->app;
  my $minion = $app->minion;
  my $log    = $app->log;
  my $db     = $app->pg->db;

  for my $id (@ids) {
    my $tx  = $db->begin;
    my $pkg = $db->select('bot_packages', ['name', 'checkout_dir', 'obsolete'], {id => $id}, {for => 'update'})->hash;
    next if !$pkg || !$pkg->{obsolete} || !(my $guard = $minion->guard("processing_pkg_$id", 172800));

    $log->info("[$id] Remove $pkg->{name}/$pkg->{checkout_dir}");
    my $dir = path($app->config->{checkout_dir}, $pkg->{name}, $pkg->{checkout_dir});
    $dir->remove_tree if -d $dir;

    $db->query('delete from bot_reports where package = ?',     $id);
    $db->query('delete from emails where package = ?',          $id);
    $db->query('delete from urls where package = ?',            $id);
    $db->query('delete from pattern_matches where package = ?', $id);
    $db->query('delete from matched_files where package = ?',   $id);
    $tx->commit;
  }
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
