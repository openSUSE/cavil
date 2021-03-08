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
