# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package Cavil::Task::Import;
use Mojo::Base 'Mojolicious::Plugin', -signatures;

use Cavil::Checkout;
use Mojo::File  qw(path);
use Cavil::Util qw(request_id_from_external_link);

sub register ($self, $app, $config) {
  $app->minion->add_task(git_import      => \&_git);
  $app->minion->add_task(obs_import      => \&_obs);
  $app->minion->add_task(resolve_targets => \&_resolve_targets);
}

# Destination targets can need an OBS request lookup, so they are resolved here off the bot API request path.
# Gitea links carry their target in the link itself; OBS links need the request. Only unresolved targets are
# looked up, so re-runs are cheap and a changed link is picked up once the controller clears the old value.
sub _resolve_targets ($job, $id, $api) {
  my $app  = $job->app;
  my $pkgs = $app->packages;
  return unless my $pkg = $pkgs->find($id);

  $pkgs->update({id => $id, target => _target($app, $pkg->{external_link}, $api)}) unless defined $pkg->{target};

  my $requests = $app->requests;
  for my $request (@{$requests->unresolved_targets($id)}) {
    $requests->set_target($request->{id}, _target($app, $request->{external_link}, $api));
  }
}

sub _target ($app, $link, $api_url) {
  return undef unless defined $link;
  return $1                                               if $link                     =~ /^(?:soo|ssd)#([^!]+)!\d+$/;
  return eval { $app->obs->request_target($api_url, $1) } if defined $api_url && $link =~ /^(?:obs|ibs)#(\d+)$/;
  return undef;
}

sub _bugref_flags ($job, $id, $data) {
  return unless my $link       = $data->{external_link};
  return unless my $request_id = request_id_from_external_link($link);

  my $app     = $job->app;
  my $obs     = $app->obs;
  my $bugrefs = $obs->get_bugrefs_for_request($data->{api}, $request_id);

  my $embargoed = $obs->check_for_embargo($data->{api}, $request_id, $bugrefs);
  $app->packages->update({id => $id, embargoed => $embargoed});
  $app->packages->add_tags($id, $obs->cves_for_request($data->{api}, $request_id, $bugrefs));
}

sub _git ($job, $id, $data) {
  my $app  = $job->app;
  my $log  = $app->log;
  my $pkgs = $app->packages;

  # Protect from race conditions
  return $job->finish("Package $id is already being processed") unless my $guard = $pkgs->claim_guard($id, $job->id);

  my $checkout_dir = $app->config->{checkout_dir};
  my ($pkg, $url, $hash) = @{$data}{qw(pkg url hash)};
  my $dir = path($checkout_dir, $pkg, $hash);

  my $git = $app->git;
  eval { $git->download_source($url, $dir, {hash => $hash}) };
  if ($@) {
    $dir->remove_tree;
    die $@;
  }
  $pkgs->imported($id);
  $log->info("[$id] Imported $dir");

  # Preserve request priority through the build chain.
  undef $guard;
  $pkgs->unpack($id, $job->info->{priority} + 1, [$job->id]);
}

sub _obs ($job, $id, $data) {
  my $app  = $job->app;
  my $log  = $app->log;
  my $pkgs = $app->packages;

  return $job->finish("Package $id is already being processed") unless my $guard = $pkgs->claim_guard($id, $job->id);

  _bugref_flags($job, $id, $data);

  my $checkout_dir = $app->config->{checkout_dir};
  my ($srcpkg, $verifymd5, $api, $project, $pkg, $srcmd5) = @{$data}{qw(srcpkg verifymd5 api project pkg srcmd5)};
  my $dir = path($checkout_dir, $srcpkg, $verifymd5);

  my $obs = $app->obs;
  eval { $obs->download_source($api, $project, $pkg, $dir, {rev => $srcmd5}) };
  if ($@) {
    $dir->remove_tree;
    die $@;
  }
  chmod 0755, $dir;
  chmod 0644, $_ for $dir->list->each;
  $pkgs->imported($id);
  $log->info("[$id] Imported $dir");

  # Preserve request priority through the build chain.
  undef $guard;
  $pkgs->unpack($id, $job->info->{priority} + 1, [$job->id]);
}

1;
