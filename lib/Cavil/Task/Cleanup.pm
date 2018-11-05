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
use Mojo::Base 'Mojolicious::Plugin';

use Cavil::Util;
use Mojo::File 'path';

sub register {
  my ($self, $app) = @_;
  $app->minion->add_task(obsolete      => \&_obsolete);
  $app->minion->add_task(cleanup       => \&_cleanup);
  $app->minion->add_task(cleanup_batch => \&_cleanup_batch);
}

sub _cleanup {
  my $job = shift;

  my $app = $job->app;
  my $ids
    = $app->pg->db->query(
    'select id from bot_packages where obsolete is true order by id')
    ->arrays->flatten->to_array;
  my $buckets
    = Cavil::Util::buckets($ids, $app->config->{cleanup_bucket_average});

  my $minion = $app->minion;
  $minion->enqueue('cleanup_batch', $_, {parents => [$job->id], priority => 1})
    for @$buckets;
}

sub _cleanup_batch {
  my ($job, @ids) = @_;

  my $app = $job->app;
  my $log = $app->log;
  my $db  = $app->pg->db;

  for my $id (@ids) {
    next
      unless my $pkg
      = $db->select('bot_packages', ['name', 'checkout_dir'], {id => $id})
      ->hash;

    my $dir
      = path($app->config->{checkout_dir}, $pkg->{name}, $pkg->{checkout_dir});
    next unless -d $dir;

    $log->info("[$id] Remove $pkg->{name}/$pkg->{checkout_dir}");
    my $tx = $db->begin;
    $db->query('delete from bot_reports where package = ?',     $id);
    $db->query('delete from emails where package = ?',          $id);
    $db->query('delete from urls where package = ?',            $id);
    $db->query('delete from matched_files where package = ?',   $id);
    $db->query('delete from pattern_matches where package = ?', $id);
    $tx->commit;
    $dir->remove_tree;
  }
}

sub _obsolete {
  my $job = shift;

  my $app = $job->app;
  my $log = $app->log;
  my $db  = $job->app->pg->db;

  my $list = $db->query(
    "select id, name, state, checksum
     from bot_packages
     where state != 'new' and obsolete is not true and checksum is not null
     order by id"
  );

  my %seen;
  while (my $pkg = $list->hash) {
    my $key = "$pkg->{name}-+$pkg->{state}+-$pkg->{checksum}";
    if (defined $seen{$key}) {
      $db->query('update bot_packages set obsolete = true where id = ?',
        $seen{$key});
    }
    $seen{$key} = $pkg->{id};
  }

  $app->minion->enqueue('cleanup' => [] => {parents => [$job->id]});
}

1;
