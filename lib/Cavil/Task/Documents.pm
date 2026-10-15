# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package Cavil::Task::Documents;
use Mojo::Base 'Mojolicious::Plugin', -signatures;

sub register ($self, $app, $config) {
  $app->minion->add_task(documents => \&_documents);
}

# One document, without holding the package: the stamp is taken before the build starts, so if the report or anything
# else the document is built from changes in the meantime, the document counts as missing rather than being handed out
sub _documents ($job, $id, $key) {
  my $app  = $job->app;
  my $pkgs = $app->packages;

  return $job->fail("Package $id is not indexed yet") unless $pkgs->is_indexed($id);
  return $job->fail("Unknown document $key") unless my $doc = $pkgs->document($key);
  return $job->finish("Document $key of package $id is up to date") if $pkgs->has_document($id, $key);

  # A registry key names the application helper that generates it, so a new format needs no wiring here
  my $stamp = $pkgs->${\$doc->{stamp}}($pkgs->find($id));
  $app->$key->generate_to_file($id, $pkgs->document_path($id, $key), $stamp);
}

1;
