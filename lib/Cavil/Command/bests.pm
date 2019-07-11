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

package Cavil::Command::bests;
use Mojo::Base 'Mojolicious::Command';

use Mojo::File 'path';
use Mojo::JSON qw(decode_json encode_json);
use Spooky::Patterns::XS;
use Time::HiRes 'time';
use Cavil::Text 'closest_pattern';

has description => 'Show license changes from previous reviews';
has usage       => sub { shift->extract_usage };

sub run {
  my ($self, @args) = @_;

  my $app = $self->app;
  my $db  = $app->pg->db;

  my $cache = $app->home->child('cache', 'cavil.pattern.words');
  my $data  = decode_json $cache->slurp;

  Spooky::Patterns::XS::init_matcher;
  say time;
  my $hash         = $db->select('license_patterns', '*', {id => 1})->hash;
  my $best_pattern = closest_pattern($hash->{pattern}, $hash->{id}, $data);
  say STDERR "BEST for $hash->{id} is $best_pattern->{id}";

  say time;
  my $snippet = $db->select('snippets', '*', {}, {limt => 1})->hash;
  $best_pattern = closest_pattern($snippet->{text}, undef, $data);
  say STDERR "BEST is $best_pattern->{id}";
  say time;

  #say $best_pattern->{pattern};

}

1;

=encoding utf8

=head1 NAME

Cavil::Command::bests - Cavil best command

=head1 SYNOPSIS

  Usage: APPLICATION check ID

    script/cavil check 110848

  Options:
    -h, --help   Show this summary of available options

=cut
