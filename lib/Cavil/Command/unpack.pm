# Copyright (C) 2025 SUSE LLC
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

package Cavil::Command::unpack;
use Mojo::Base 'Mojolicious::Command', -signatures;

has description => 'Unpack sources';
has usage       => sub ($self) { $self->extract_usage };

sub run ($self, @args) {
  my $pkg = shift @args;

  die "PACKAGE is required.\n" unless $pkg;

  my $app    = $self->app;
  my $minion = $app->minion;
  if ($minion->is_locked("processing_pkg_$pkg")) {
    print STDOUT "Releasing locks for package $pkg\n";
    $minion->unlock("processing_pkg_$pkg");
  }

  my $job = $app->packages->unpack($pkg);

  print STDOUT "Triggered unpack job $job\n";
}

1;

=encoding utf8

=head1 NAME

Cavil::Command::unpack - Cavil unpack command

=head1 SYNOPSIS

  Usage: APPLICATION unpack [PACKAGE]

    script/cavil unpack 12345

  Options:
    -h, --help   Show this summary of available options

=cut
