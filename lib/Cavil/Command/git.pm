# Copyright (C) 2024 SUSE LLC
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, see <http://www.gnu.org/licenses/>.

package Cavil::Command::git;
use Mojo::Base 'Mojolicious::Command', -signatures;

use Mojo::File qw(path);
use Mojo::Util qw(getopt);


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

  # Index
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
  my $job = $pkgs->git_import($obj->{id}, {url => $url, pkg => $pkg, hash => $hash, priority => 9}, 9);

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
