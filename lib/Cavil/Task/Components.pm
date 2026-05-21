# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package Cavil::Task::Components;
use Mojo::Base 'Mojolicious::Plugin', -signatures;

sub register ($self, $app, $config) {
  $app->minion->add_task(detect_components => \&_detect_components);
}

sub _detect_components ($job, $id) {
  my $app    = $job->app;
  my $minion = $app->minion;
  my $pkgs   = $app->packages;

  return $job->fail("Package $id is not indexed yet") unless $pkgs->is_indexed($id);
  return $job->finish("Package $id is already being processed")
    unless my $guard = $minion->guard("processing_pkg_$id", 172800);

  $app->plugins->emit_hook('before_task_detect_components');
  $app->components->detect_for_package($id);

  undef $guard;
  my $prio = $job->info->{priority};
  $pkgs->analyze($id, $prio, [$job->id]);
}

1;
