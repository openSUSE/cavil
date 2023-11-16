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

package Cavil::Model::Patterns;
use Mojo::Base -base, -signatures;

use Cavil::Util qw(paginate);
use Mojo::File 'path';
use Spooky::Patterns::XS;
use Storable;

has [qw(cache log pg minion)];

sub create ($self, %args) {

  my $db       = $self->pg->db;
  my $checksum = $self->checksum($args{pattern});
  my $id       = $db->select('license_patterns', 'id', {token_hexsum => $checksum})->hash;
  if ($id) {
    return {conflict => $id->{id}};
  }

  # Get SPDX expression for already known licenses
  my $spdx = '';
  if (my $license = $args{license}) {
    my $pattern = $self->pg->db->query('SELECT spdx FROM license_patterns WHERE license = ? LIMIT 1', $license)->hash;
    $spdx = $pattern->{spdx} if $pattern;
  }

  my $mid = $db->insert(
    'license_patterns',
    {
      pattern           => $args{pattern},
      token_hexsum      => $checksum,
      packname          => $args{packname}          // '',
      patent            => $args{patent}            // 0,
      trademark         => $args{trademark}         // 0,
      opinion           => $args{opinion}           // 0,
      export_restricted => $args{export_restricted} // 0,
      license           => $args{license}           // '',
      spdx              => $spdx,
      risk              => $args{risk} // 5
    },
    {returning => 'id'}
  )->hash->{id};

  $self->expire_cache;

  # reclculate the tf-idfs
  $self->minion->enqueue(pattern_stats => [] => {priority => 9});

  return $self->find($mid);
}

sub expire_cache ($self) {
  my $cache = path($self->cache);
  unlink $cache->child('cavil.tokens')->to_string;
  unlink $cache->child('cavil.pattern.bag')->to_string;
}

sub has_new_patterns ($self, $packname, $when) {
  return $self->pg->db->query(
    "select count(*) from license_patterns
     where created > ? and (packname = '' or packname = ?)", $when, $packname
  )->array->[0];
}

sub load_specific ($self, $matcher, $pname) {
  my $rows = $self->pg->db->select('license_patterns', ['id', 'pattern'], {packname => $pname});

  while (my $l = $rows->array) {
    my ($id, $pattern) = @$l;
    $pattern = Spooky::Patterns::XS::parse_tokens($pattern);
    $matcher->add_pattern($id, $pattern);
  }
}

# possibly cached
sub load_unspecific ($self, $matcher) {
  my $cachefile = path($self->cache, 'cavil.tokens')->to_string;
  if (-f $cachefile) {
    $matcher->load($cachefile);
    return;
  }

  $self->load_specific($matcher, '');

  my $dir = path($self->cache);
  my $tmp = $dir->child("cavil.tokens.tmp.$$")->to_string;
  $matcher->dump($tmp);
  rename $tmp, $cachefile;
}

sub all ($self) {
  return $self->pg->db->select('license_patterns', '*')->hashes;
}

sub find ($self, $id) {
  return $self->pg->db->select('license_patterns', '*', {id => $id})->hash;
}

sub checksum ($self, $pattern) {
  Spooky::Patterns::XS::init_matcher();
  my $a   = Spooky::Patterns::XS::parse_tokens($pattern);
  my $ctx = Spooky::Patterns::XS::init_hash(0, 0);
  for my $n (@$a) {

    # map the skips to each other
    $n = 99 if $n < 99;
    my $s = pack('q', $n);
    $ctx->add($s);
  }

  return $ctx->hex;
}

sub for_license ($self, $license) {
  return $self->pg->db->select('license_patterns', '*', {license => $license}, 'created')->hashes->to_array;
}

sub paginate_known_licenses ($self, $options) {
  my $db = $self->pg->db;

  my $search = '';
  if (length($options->{search}) > 0) {
    my $quoted = $db->dbh->quote("\%$options->{search}\%");
    $search = "WHERE license ILIKE $quoted";
  }

  my $results = $db->query(
    qq{
      SELECT license, spdx, COUNT(*) OVER() AS total
      FROM (
        SELECT DISTINCT(license), spdx FROM license_patterns
        $search
      ) AS licenses
      ORDER BY license
      LIMIT ? OFFSET ?
    }, $options->{limit}, $options->{offset}
  )->hashes->to_array;

  return paginate($results, $options);
}

sub remove ($self, $id) {
  $self->pg->db->delete('license_patterns', {id => $id});
}

sub update ($self, $id, %args) {
  my $db = $self->pg->db;

  my $checksum = $self->checksum($args{pattern});
  my $conflict = $db->select('license_patterns', 'id', {token_hexsum => $checksum})->hash;
  if ($conflict && $conflict->{id} != $id) {
    return {conflict => $conflict->{id}};
  }

  $db->update(
    'license_patterns',
    {
      pattern           => $args{pattern},
      token_hexsum      => $checksum,
      packname          => $args{packname} // '',
      license           => $args{license},
      patent            => $args{patent}            // 0,
      trademark         => $args{trademark}         // 0,
      opinion           => $args{opinion}           // 0,
      export_restricted => $args{export_restricted} // 0,
      risk              => $args{risk}              // 5
    },
    {id => $id}
  );
}

1;
