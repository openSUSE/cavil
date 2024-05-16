# Copyright (C) 2018 SUSE Linux GmbH
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

package Cavil::Command::obs;
use Mojo::Base 'Mojolicious::Command', -signatures;

use Mojo::File 'path';
use Mojo::Util qw(dumper getopt);

has description => 'Import OBS sources';
has usage       => sub ($self) { $self->extract_usage };

sub run ($self, @args) {
  getopt \@args,
    'd|download=s' => \my $download,
    'import'       => \my $import,
    'r|rev=s'      => \my $rev,
    'reimport=s'   => \my $reimport;

  my $api     = shift @args;
  my $project = shift @args;
  my $pkg     = shift @args;

  if ($reimport) {
    my $result = $self->app->pg->db->query(
      'SELECT api_url, project, package, srcmd5
       FROM bot_packages bp JOIN bot_sources bs ON bp.source = bs.id
       WHERE bp.id = ?', $reimport
    )->hash;
    die "Package with the id $reimport not found.\n" unless $result;
    ($api, $project, $pkg, $rev) = @{$result}{qw(api_url project package srcmd5)};
    $import = 1;
  }

  die "API is required.\n"     unless $api;
  die "PROJECT is required.\n" unless $project;
  die "PACKAGE is required.\n" unless $pkg;

  # Get info
  my $app  = $self->app;
  my $obs  = $app->obs;
  my $info = $obs->package_info($api, $project, $pkg, {rev => $rev});
  return print STDOUT dumper $info unless $download || $import;

  # Download
  my ($srcpkg, $srcmd5, $verifymd5) = @{$info}{qw(package srcmd5 verifymd5)};
  my $checkout_dir = $import ? $app->config->{checkout_dir} : $download;
  my $dir          = path($checkout_dir, $srcpkg, $verifymd5)->make_path;
  $obs->download_source($api, $project, $pkg, $dir, {rev => $srcmd5});
  return print STDOUT qq{Downloaded $pkg to "$dir".\n} if $download;

  # Index
  my $user = $app->users->licensedigger;
  my $pkgs = $app->packages;
  my $obj  = $pkgs->find_by_name_and_md5($srcpkg, $verifymd5);
  if (!$obj) {
    my $id = $pkgs->add(
      name            => $srcpkg,
      checkout_dir    => $verifymd5,
      api_url         => $api,
      requesting_user => $user->{id},
      project         => $project,
      priority        => 1,
      package         => $pkg,
      srcmd5          => $srcmd5,
    );
    $obj = $pkgs->find($id);
  }
  $obj->{external_link} //= 'obs-command';
  $obj->{obsolete} = 0;
  $pkgs->update($obj);
  my $job = $pkgs->obs_import(
    $obj->{id},
    {
      api       => $api,
      project   => $project,
      pkg       => $pkg,
      srcpkg    => $srcpkg,
      rev       => $rev,
      srcmd5    => $srcmd5,
      verifymd5 => $verifymd5,
      priority  => 9
    },
    9
  );

  print STDOUT "Triggered obs_import job $job\n";
}

1;

=encoding utf8

=head1 NAME

Cavil::Command::obs - Cavil obs command

=head1 SYNOPSIS

  Usage: APPLICATION obs [API] [PROJECT] [PACKAGE]

    script/cavil obs https://api.opensuse.org Base:System grub2
    script/cavil obs https://api.opensuse.org Base:System grub2 -r 307
    script/cavil obs https://api.opensuse.org Base:System grub2 -r 307 -d .
    script/cavil obs https://api.opensuse.org Base:System grub2 -r 307 -i
    script/cavil obs --reimport 123

  Options:
    -d, --download <dir>   Resolve and download package from OBS
        --import           Import and index package from OBS
    -h, --help             Show this summary of available options
        --reimport <id>    Reimport an existing package
    -r, --rev <revision>   Package revision

=cut
