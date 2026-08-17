# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package Cavil::Task::Documents;
use Mojo::Base 'Mojolicious::Plugin', -signatures;

sub register ($self, $app, $config) {
  $app->minion->add_task(documents => \&_documents);
}

sub _documents ($job, $id) {
  my $app  = $job->app;
  my $pkgs = $app->packages;

  # Busy packages are retried because an interactive download is waiting for output.
  my $pkg_guard = $pkgs->claim_guard($id, $job->id);
  unless ($pkg_guard) {
    my $retries = $job->info->{retries} // 0;
    return $job->fail("Package $id has been busy for an hour, giving up") if $retries >= 70;
    return $job->retry({delay => $retries < 10 ? 3 : 60});
  }
  return $job->fail("Package $id is not indexed yet") unless $pkgs->is_indexed($id);

  # A registry key names the application helper that generates it, so a new format needs no wiring here
  $pkgs->remove_documents($id);
  for my $doc (@{$pkgs->DOCUMENTS}) {
    my $key = $doc->{key};
    $app->$key->generate_to_file($id, $pkgs->document_path($id, $key));
  }

  # The only job touching the package, so a reindex requested while it was running has nobody else to pick it up
  $pkgs->hand_back($id, $job->id);
}

1;
