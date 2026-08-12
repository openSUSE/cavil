# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package Cavil::Task::Unpack;
use Mojo::Base 'Mojolicious::Plugin', -signatures;

use Cavil::Checkout;
use Cavil::Util qw(parse_exclude_file);

sub register ($self, $app, $config) {
  $app->minion->add_task(unpack => \&_unpack);
}

sub _unpack ($job, $id) {
  my $app  = $job->app;
  my $log  = $app->log;
  my $pkgs = $app->packages;

  return $job->finish("Package $id is already being processed") unless my $guard = $pkgs->claim_guard($id, $job->id);
  return $job->fail("Package $id is not imported yet")          unless $pkgs->is_imported($id);

  # Clear unpacked to block indexing, but retain the live report during rebuilding.
  $app->pg->db->update('bot_packages', {unpacked => undef, index_stage => 'unpacking'}, {id => $id});

  my $exclude = [];
  if (my $exclude_file = $app->config->{exclude_file}) {
    my $name = $app->packages->find($id)->{name};
    $exclude = parse_exclude_file($exclude_file, $name);
  }

  my $dir = $pkgs->pkg_checkout_dir($id);
  Cavil::Checkout->new($dir)->unpack({exclude => $exclude});
  $pkgs->unpacked($id);
  $log->info("[$id] Unpacked $dir");

  undef $guard;
  $pkgs->index($id, $job->info->{priority} + 1, [$job->id]);
}

1;
