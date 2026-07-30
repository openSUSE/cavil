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

  # Protect from race conditions. Somebody else holding the package is a "not yet", not a "no": a reindex
  # is the usual holder and weekly for everything, so waiting it out is the normal course of events - and
  # somebody is sitting in front of the download watching for the report to appear. Finishing here instead
  # would report success while writing nothing at all, leaving them with no report and no explanation.
  #
  # Because somebody is watching, the first attempts come back in seconds: the holder is often a job with
  # little work left, and a flat minute of waiting can outlast building the report. Once it is clear this
  # is a real rebuild rather than a near miss, it settles down to looking once a minute. A package that
  # never lets go is a real fault, and says so in the queue after an hour of trying - the usual cause is a
  # claim left behind by a job that was killed, which the nightly build sweep collects.
  my $pkg_guard = $pkgs->claim_guard($id, $job->id);
  unless ($pkg_guard) {
    my $retries = $job->info->{retries} // 0;
    return $job->fail("Package $id has been busy for an hour, giving up") if $retries >= 70;
    return $job->retry({delay => $retries < 10 ? 3 : 60});
  }
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
