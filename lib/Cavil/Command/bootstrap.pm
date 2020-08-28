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

package Cavil::Command::bootstrap;
use Mojo::Base 'Mojolicious::Command';

use Mojo::Util 'getopt';

has description => 'Manage boostrap licenses and patterns';
has usage       => sub { shift->extract_usage };

sub run {
  my ($self, @args) = @_;

  getopt \@args,
    'export=s' => \my $export,
    'import'   => \my $import;

  my $bootstrap = $self->app->bootstrap;
  return $bootstrap->store($export) if $export;

  return say $bootstrap->load ? 'Database initialized' : 'Database already initialized' if $import;
}

1;

=encoding utf8

=head1 NAME

Cavil::Command::bootstrap - Cavil bootstrap command

=head1 SYNOPSIS

  Usage: APPLICATION bootstrap

    script/cavil bootstrap

  Options:
    -h, --help   Show this summary of available options

=cut
