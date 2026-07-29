# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package Cavil::Task::SPDX;
use Mojo::Base 'Mojolicious::Plugin', -signatures;

use Cavil::Checkout;
use Mojo::Util qw(scope_guard);

sub register ($self, $app, $config) {
  $app->minion->add_task(spdx_report => \&_spdx_report);
}

sub _spdx_report ($job, $id) {
  my $app    = $job->app;
  my $minion = $app->minion;
  my $pkgs   = $app->packages;
  my $spdx   = $app->spdx;

  # Protect from race conditions
  my $spdx_guard = scope_guard sub { $minion->unlock("spdx_$id") };
  return $job->finish("Package $id is already being processed")
    unless my $pkg_guard = $pkgs->claim_guard($id, $job->id);
  return $job->fail("Package $id is not indexed yet") unless $pkgs->is_indexed($id);

  # Placeholder
  $pkgs->remove_spdx_report($id);
  my $path = $pkgs->spdx_report_path($id);
  $spdx->generate_to_file($id, $path);

  # Usually the last job to touch the package (with always_generate_spdx_reports every build ends here), so
  # a reindex requested while it was running has nobody else to pick it up
  $pkgs->hand_back($id, $job->id);
}

1;
