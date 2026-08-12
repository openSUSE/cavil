# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package Cavil::Task::SPDX;
use Mojo::Base 'Mojolicious::Plugin', -signatures;

use Cavil::Checkout;

sub register ($self, $app, $config) {
  $app->minion->add_task(spdx_report => \&_spdx_report);
}

sub _spdx_report ($job, $id) {
  my $app  = $job->app;
  my $pkgs = $app->packages;
  my $spdx = $app->spdx;

  # Busy packages are retried because an interactive download is waiting for output.
  my $pkg_guard = $pkgs->claim_guard($id, $job->id);
  unless ($pkg_guard) {
    my $retries = $job->info->{retries} // 0;
    return $job->fail("Package $id has been busy for an hour, giving up") if $retries >= 70;
    return $job->retry({delay => $retries < 10 ? 3 : 60});
  }
  return $job->fail("Package $id is not indexed yet") unless $pkgs->is_indexed($id);

  $pkgs->remove_spdx_report($id);
  my $path = $pkgs->spdx_report_path($id);
  $spdx->generate_to_file($id, $path);

  # Usually the last job to touch the package (with always_generate_spdx_reports every build ends here), so
  # a reindex requested while it was running has nobody else to pick it up
  $pkgs->hand_back($id, $job->id);
}

1;
