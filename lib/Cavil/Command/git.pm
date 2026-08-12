# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package Cavil::Command::git;
use Mojo::Base 'Mojolicious::Command', -signatures;

use Cavil::Util qw(PRIORITY_WAITING);
use Mojo::File  qw(path);
use Mojo::Util  qw(getopt);

has description => 'Import git sources';
has usage       => sub ($self) { $self->extract_usage };

sub run ($self, @args) {
  getopt \@args, 'e|external-link=s' => \my $link, 'i|import' => \my $import;

  my $url  = shift @args;
  my $pkg  = shift @args;
  my $hash = shift @args;

  die "URL is required.\n"     unless $url;
  die "PACKAGE is required.\n" unless $pkg;
  die "HASH is required.\n"    unless $hash;

  return print STDOUT "Nothing to do\n" unless $import;

  my $app  = $self->app;
  my $user = $app->users->licensedigger;
  my $pkgs = $app->packages;
  my $obj  = $pkgs->find_by_name_and_md5($pkg, $hash);
  if (!$obj) {
    my $id = $pkgs->add(
      name            => $pkg,
      checkout_dir    => $hash,
      api_url         => $url,
      requesting_user => $user->{id},
      project         => '',
      priority        => 1,
      package         => $pkg,
      srcmd5          => $hash,
      type            => 'git'
    );
    $obj = $pkgs->find($id);
  }
  $obj->{external_link} = $link // $obj->{external_link} // 'git-command';
  $obj->{obsolete}      = 0;
  $pkgs->update($obj);

  # An admin at the command line asking for one specific package is waiting on it, same as the Reindex
  # button on a report page
  my $job = $pkgs->git_import($obj->{id}, {url => $url, pkg => $pkg, hash => $hash}, PRIORITY_WAITING);

  print STDOUT "Triggered git_import job $job\n";
}

1;

=encoding utf8

=head1 NAME

Cavil::Command::git - Cavil git command

=head1 SYNOPSIS

  Usage: APPLICATION git [URL] [PACKAGE] [HASH]

    script/cavil git https://src.opensuse.org/pool/perl-Mojolicious.git perl-Mojolicious \
                     242511548e0cdcf17b6321738e2d8b6a3b79d41775c4a867f03b384a284d9168 -i

  Options:
    -e, --external-link <link>   External link to the request
    -i, --import                 Import and index package from git
    -h, --help                   Show this summary of available options

=cut
