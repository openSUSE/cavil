# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package Cavil::Command::rindex;
use Mojo::Base 'Mojolicious::Command', -signatures;

has description => 'Start background jobs to reindex all packages';
has usage       => sub ($self) { $self->extract_usage };

sub run ($self, @args) { say $self->app->minion->enqueue('reindex_all') }

1;

=encoding utf8

=head1 NAME

Cavil::Command::rindex - Cavil rindex command

=head1 SYNOPSIS

  Usage: APPLICATION rindex

    script/cavil rindex

  Options:
    -h, --help   Show this summary of available options

=cut
