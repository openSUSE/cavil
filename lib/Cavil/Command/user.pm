# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package Cavil::Command::user;
use Mojo::Base 'Mojolicious::Command', -signatures;

use Mojo::Util qw(dumper getopt tablify);

has description => 'Manage Cavil users';
has usage       => sub ($self) { $self->extract_usage };

sub run ($self, @args) {
  getopt \@args, 'A|add-role=s' => \my $add, 'R|remove-role=s' => \my $remove;
  my $id = shift @args;

  my $users = $self->app->users;
  return
    print tablify [map { [@$_{qw(id login roles)}] } map { $_->{roles} = join ',', @{$_->{roles}}; $_ } @{$users->list}]
    unless $id;

  $users->add_role($id, $add) if $add;

  $users->remove_role($id, $remove) if $remove;

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
    -A, --add-role <name>      Add a role to a user, such as "admin",
                               "manager", "contributor", "lawyer" or
                               "classifier"
    -R, --remove-role <name>   Remove a role from a user
    -h, --help                 Show this summary of available options

=cut
