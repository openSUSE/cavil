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

package Cavil::Bootstrap;
use Mojo::Base -base;

use Mojo::File 'path';
use Mojo::JSON qw(decode_json encode_json);
use Mojo::Util 'slugify';

has 'app';

sub load {
  my $self = shift;

  # Avoid adding the same data more than once
  my $licenses = $self->app->licenses;
  return undef
    if $licenses->pg->db->select('licenses', 'id', {name => 'Low Risk Keyword'})
    ->hash;

  my $patterns = $self->app->patterns;
  my $dir      = path(__FILE__)->dirname->child('resources', 'bootstrap');
  for my $file ($dir->list->sort->each) {
    my $data = decode_json $file->slurp;

    my $id = $licenses->create(
      name    => $data->{name},
      risk    => $data->{risk},
      nonfree => $data->{nonfree},
      eula    => $data->{eula}
    );

    $patterns->create(
      pattern   => $_->{pattern},
      patent    => $_->{patent},
      trademark => $_->{trademark},
      opinion   => $_->{opinion},
      license   => $data->{name},
      risk      => $data->{risk},
      nonfree   => $data->{nonfree},
      eula      => $data->{eula}
    ) for @{$data->{patterns}};
  }
  $patterns->expire_cache;

  return 1;
}

sub store {
  my ($self, $dir) = @_;

  my $db = $self->app->pg->db;
  my $high
    = $db->select('licenses', '*', {name => 'Higher Risk Keyword'})->hash;
  my $low = $db->select('licenses', '*', {name => 'Low Risk Keyword'})->hash;
  die "Keyword licenses missing" unless $high && $low;

  # All keywords
  say '* Keywords';
  my $prefix = 1;
  for my $l ($low, $high) {
    say "$prefix. $l->{name}";
    _store($db, $dir, $prefix, $l);
    $prefix++;
  }

  # Find popular licenses (excluding keywords)
  say '* Popular licenses (this might take a few minutes)';
  my $popular = $db->select(
    ['pattern_matches', ['license_patterns', id => 'pattern']],
    ['license_patterns.license', \'count(*) as matches'],
    {'license_patterns.license' => {-not_in => [$low->{id}, $high->{id}]}},
    {
      group_by => ['license_patterns.license'],
      limit    => 98,
      order_by => {-desc => 'matches'}
    }
  )->hashes->to_array;

  for my $l (@$popular) {
    $l = $db->select('licenses', '*', {id => $l->{license}})->hash;
    say "$prefix. $l->{name}";

    # Find popular patterns for license
    my $top = $db->select(
      ['pattern_matches', ['license_patterns', id => 'pattern']],
      ['pattern_matches.pattern', \'count(*) as matches'],
      {'license_patterns.license' => $l->{id}, packname => ''},
      {
        group_by => ['pattern_matches.pattern'],
        limit    => 20,
        order_by => {-desc => 'matches'}
      }
    )->hashes->map(sub { $_->{pattern} })->to_array;

    _store($db, $dir, $prefix, $l, @$top);
    $prefix++;
  }
}

sub _name {
  my ($prefix, $name) = @_;
  return sprintf("%04d-", $prefix) . slugify($name) . '.json';
}

sub _store {
  my ($db, $dir, $prefix, $l, @patterns) = @_;

  my @in  = @patterns ? (id => {-in => \@patterns}) : ();
  my $all = $db->select(
    'license_patterns',
    ['pattern', 'patent', 'trademark', 'opinion'],
    {license  => $l->{id}, @in},
    {order_by => {-asc => 'id'}}
  )->hashes->to_array;

  my $data = {
    name        => $l->{name},
    url         => $l->{url},
    description => $l->{description},
    risk        => $l->{risk},
    nonfree     => $l->{nonfree},
    eula        => $l->{eula},
    patterns    => $all
  };
  my $name = _name($prefix, $l->{name});
  path($dir, $name)->spurt(encode_json $data);
}

1;
