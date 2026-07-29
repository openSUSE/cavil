# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package Cavil::Task::Import;
use Mojo::Base 'Mojolicious::Plugin', -signatures;

use Cavil::Checkout;
use Mojo::File  qw(path);
use Cavil::Util qw(request_id_from_external_link);

sub register ($self, $app, $config) {
  $app->minion->add_task(git_import => \&_git);
  $app->minion->add_task(obs_import => \&_obs);
}

sub _embargo ($job, $id, $data) {
  return unless my $link       = $data->{external_link};
  return unless my $request_id = request_id_from_external_link($link);

  my $app       = $job->app;
  my $embargoed = $app->obs->check_for_embargo($data->{api}, $request_id);
  $app->packages->update({id => $id, embargoed => $embargoed});
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

  # Next step, one above this one. The whole chain down to the report is built on the priority this import
  # was submitted with, so an urgent request stays urgent all the way there and an ordinary one does not
  # overtake the reviewers waiting on theirs.
  undef $guard;
  $pkgs->unpack($id, $job->info->{priority} + 1, [$job->id]);
}

sub _obs ($job, $id, $data) {
  my $app  = $job->app;
  my $log  = $app->log;
  my $pkgs = $app->packages;

  # Protect from race conditions
  return $job->finish("Package $id is already being processed") unless my $guard = $pkgs->claim_guard($id, $job->id);

  # Check embargo status before checkout
  _embargo($job, $id, $data);

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

  # Next step, one above this one. The whole chain down to the report is built on the priority this import
  # was submitted with, so an urgent request stays urgent all the way there and an ordinary one does not
  # overtake the reviewers waiting on theirs.
  undef $guard;
  $pkgs->unpack($id, $job->info->{priority} + 1, [$job->id]);
}

1;
