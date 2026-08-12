# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package Cavil::Command::cleanup;
use Mojo::Base 'Mojolicious::Command', -signatures;

has description => 'Start background jobs to remove obsolete checkouts';
has usage       => sub ($self) { $self->extract_usage };

sub run ($self, @args) { say $self->app->minion->enqueue('obsolete') }

1;

=encoding utf8

=head1 NAME

Cavil::Command::cleanup - Cavil cleanup command

=head1 SYNOPSIS

  Usage: APPLICATION cleanup

    script/cavil cleanup

  Options:
    -h, --help   Show this summary of available options

=cut
