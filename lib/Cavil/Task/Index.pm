# Copyright (C) 2018,2019 SUSE Linux GmbH
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

package Cavil::Task::Index;
use Mojo::Base 'Mojolicious::Plugin', -signatures;

use Cavil::Checkout;
use Cavil::FileIndexer;
use Spooky::Patterns::XS;
use Time::HiRes 'time';

sub register ($self, $app, $config) {
  $app->minion->add_task(index                 => \&_index);
  $app->minion->add_task(index_batch           => \&_index_batch);
  $app->minion->add_task(index_later           => \&_index_later);
  $app->minion->add_task(indexed               => \&_indexed);
  $app->minion->add_task(reindex_all           => \&_reindex_all);
  $app->minion->add_task(reindex_matched_later => \&_reindex_matched_later);
}

sub _index ($job, $id) {
  my $app    = $job->app;
  my $minion = $app->minion;
  my $pkgs   = $app->packages;
  my $log    = $app->log;

  # Protect from race conditions
  return $job->fail("Package $id is not unpacked yet")          unless $pkgs->is_unpacked($id);
  return $job->finish("Package $id is already being processed") unless $minion->lock("processing_pkg_$id", 172800);

  # Clean up (make sure not to leak a Postgres connection)
  {
    my $db = $app->pg->db;
    $db->update('bot_packages', {indexed => undef, checksum => undef}, {id => $id});
    $db->delete('matched_files', {package => $id});
    $db->delete('urls',          {package => $id});
    $db->delete('emails',        {package => $id});
    $db->delete('bot_reports',   {package => $id});

    $pkgs->remove_spdx_report($id);
  }

  my $dir      = $pkgs->pkg_checkout_dir($id);
  my $checkout = Cavil::Checkout->new($dir);

  # Update file stats
  unless ($pkgs->has_file_stats($id)) {
    my $stats = $checkout->unpacked_file_stats;
    $pkgs->update_file_stats($id, $stats);
  }

  # Split up files into batches
  my $batches   = $checkout->unpacked_files($app->config->{index_bucket_average});
  my $parent_id = $job->id;
  my $prio      = $job->info->{priority};
  my @children  = map {
    $minion->enqueue(
      index_batch => [$id, $_] => {parents => [$parent_id], priority => $prio + 1, notes => {"pkg_$id" => 1}})
  } @$batches;
  $minion->enqueue(indexed => [$id] => {parents => \@children, priority => $prio + 2, notes => {"pkg_$id" => 1}});

  $log->info("[$id] Made @{[scalar @$batches]} batches for $dir");
}

sub _index_batch ($job, $id, $batch) {
  my $app = $job->app;
  my $log = $app->log;
  $app->plugins->emit_hook('before_task_index_batch');

  my $start = time;

  my $fi       = Cavil::FileIndexer->new($app, $id);
  my $preptime = time - $start;

  my %meta = (emails => {}, urls => {});
  for my $file (@$batch) {
    my ($path, $mime) = @$file;
    $fi->file(\%meta, $path, $mime);
  }

  # URLs
  my $db  = $app->pg->db;
  my $max = $app->config->{max_email_url_size};
  for my $url (sort keys %{$meta{urls}}) {
    next if length($url) > $max;
    $db->query(
      'insert into urls (package, url, hits) values ($1, $2, $3)
         on conflict (package, md5(url))
         do update set hits = urls.hits + $3', $id, $url, $meta{urls}{$url}
    );
  }

  # Email addresses
  for my $email (sort keys %{$meta{emails}}) {
    next if length($email) > $max;
    my $e = $meta{emails}{$email};
    $db->query(
      'insert into emails (package, email, name, hits)
           values ($1, $2, $3, $4)
         on conflict (package, md5(email))
         do update set hits = emails.hits + $4', $id, $email, $e->{name}, $e->{count}
    );
  }
  my $total = time - $start;
  my $dir   = $fi->dir;
  $log->info(
    sprintf("[$id] Indexed batch of @{[scalar @$batch]} files from $dir (%.02f prep, %.02f total)", $preptime, $total));
}

sub _index_later ($job, $id) {
  $job->app->packages->reindex($id, $job->info->{priority} + 1);
}

sub _indexed ($job, $id) {
  my $app    = $job->app;
  my $minion = $job->minion;
  my $pkgs   = $job->app->packages;

  # Protect from race conditions
  $minion->unlock("processing_pkg_$id");

  $pkgs->indexed($id);

  # Next step - always high prio because the renderer
  # relies on it
  return $pkgs->analyze($id, 9, [$job->id]);
}

sub _reindex_all ($job) {
  $job->app->packages->reindex_all;
}

sub _reindex_matched_later ($job, $pid) {
  $job->app->packages->reindex_matched_packages($pid, $job->info->{priority});
}

1;
