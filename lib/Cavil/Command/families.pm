# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package Cavil::Command::families;
use Mojo::Base 'Mojolicious::Command', -signatures;

has description => 'Regroup packages into families after an upgrade or a change to the naming rules';
has usage       => sub ($self) { $self->extract_usage };

sub run ($self, @args) {
  my $families = $self->app->packages->sync_families;
  say 'Regrouped ' . @$families . ' package families';
}

1;

=encoding utf8

=head1 NAME

Cavil::Command::families - Cavil families command

=head1 SYNOPSIS

  Usage: APPLICATION families

    script/cavil families

  Options:
    -h, --help   Show this summary of available options

=cut
