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
use Mojo::Base 'Mojolicious::Command';

has description => 'Migrate the database to latest version';
has usage       => sub { shift->extract_usage };

sub run {
  my $app        = shift->app;
  my $migrations = $app->pg->migrations;
  my $before     = $migrations->active;
  if ($before == $migrations->latest) {
    say "Nothing to do";
    return;
  }

  my $db = $app->pg->db;

  # special case for migration 7, which copies license properties
  # to patterns
  if ($migrations->active < 7) {
    $migrations->migrate(7);
    my $patterns = $db->query(
      "select p.id,l.name,l.risk,l.eula,l.nonfree
         from license_patterns p join licenses l on p.license = l.id"
    )->hashes;

    for my $p (@$patterns) {
      $p->{name} = '' if $p->{name} eq 'Low Risk Keyword';
      $p->{name} = '' if $p->{name} eq 'Higher Risk Keyword';

      $db->update(
        'license_patterns',
        {
          # Careful: in migration 7 it's called license_string
          # renamed to license in 10
          license_string => $p->{name},
          risk           => $p->{risk}
        },
        {id => $p->{id}}
      );
    }
  }

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
