# Copyright (C) 2019 SUSE Linux GmbH
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

package Cavil::Command::migrate;
use Mojo::Base 'Mojolicious::Command', -signatures;

has description => 'Migrate the database to latest version';
has usage       => sub ($self) { $self->extract_usage };

sub run ($self, @args) {
  my $app        = $self->app;
  my $migrations = $app->pg->migrations;
  my $before     = $migrations->active;
  if ($before == $migrations->latest) {
    say "Nothing to do";
    return;
  }

  my $db = $app->pg->db;

  # now the rest
  $migrations->migrate;

  say "Migrated from $before to " . $migrations->active;
}

1;

=encoding utf8

=head1 NAME

Cavil::Command::migrate - Cavil command to migrate the DB schema

=head1 SYNOPSIS

  Usage: APPLICATION migrate

    script/cavil migrate

  Options:
    -h, --help   Show this summary of available options

=cut
