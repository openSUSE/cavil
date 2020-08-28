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

package Cavil::Command::user;
use Mojo::Base 'Mojolicious::Command';

use Mojo::Util qw(dumper getopt tablify);

has description => 'Manage Cavil users';
has usage       => sub { shift->extract_usage };

sub run {
  my ($self, @args) = @_;

  getopt \@args, 'A|add-role=s' => \my $add, 'R|remove-role=s' => \my $remove;
  my $id = shift @args;

  # List
  my $users = $self->app->users;
  return
    print tablify [map { [@$_{qw(id login roles)}] } map { $_->{roles} = join ',', @{$_->{roles}}; $_ } @{$users->list}]
    unless $id;

  # Add role
  $users->add_role($id, $add) if $add;

  # Remove role
  $users->remove_role($id, $remove) if $remove;

  # Show user
  return print dumper $users->find(id => $id);
}

1;

=encoding utf8

=head1 NAME

Cavil::Command::user - Cavil user command

=head1 SYNOPSIS

  Usage: APPLICATION user [OPTIONS] [ID]

    script/cavil user
    script/cavil user 23
    script/cavil user -A admin 23

  Options:
    -A, --add-role <name>      Add a role to a user
    -R, --remove-role <name>   Remove a role from a user
    -h, --help                 Show this summary of available options

=cut
