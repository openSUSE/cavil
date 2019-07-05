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

package Cavil::Model::Licenses;
use Mojo::Base -base;

use Mojo::File 'path';

has [qw(pg)];

sub all { shift->pg->db->select('licenses')->hashes->to_array }

sub create {
  my ($self, %args) = @_;
  return $self->pg->db->insert('licenses', \%args, {returning => 'id'})
    ->hash->{id};
}


sub find {
  my ($self, $id) = @_;
  return $self->pg->db->select('licenses', '*', {id => $id})->hash;
}

sub try_to_match_license {
  my ($self, $name) = @_;

  return -1 unless $name;

  my $licenses = $self->all;
  for my $lic (@$licenses) {
    return $lic->{id} if $lic->{name} eq $name;
  }

  # try with sublicenses - very cruely
  for my $lpart (split(/\s/, $name)) {
    for my $lic (@$licenses) {
      return $lic->{id} if $lic->{name} eq $lpart;
    }
  }
  return -1;
}

sub update {
  my ($self, $id, %args) = @_;

  $self->pg->db->update(
    'licenses',
    {
      name        => $args{name},
      url         => $args{url},
      risk        => $args{risk},
      description => $args{description},
      eula        => $args{eula} // 0,
      nonfree     => $args{nonfree} // 0
    },
    {id => $id}
  );
}


1;
