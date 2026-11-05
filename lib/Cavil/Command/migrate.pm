# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

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
