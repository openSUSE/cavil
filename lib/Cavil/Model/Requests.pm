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

package Cavil::Model::Requests;
use Mojo::Base -base;

has 'pg';

sub add {
  my ($self, $link, $pkg) = @_;
  my $req = {external_link => $link, package => $pkg};
  return $self->pg->db->insert('bot_requests', $req, {returning => 'id'})->hash->{id};
}

sub all {
  my $self = shift;
  return $self->pg->db->query(
    'select external_link, array_agg(package) as packages from bot_requests
     group by external_link'
  )->hashes->to_array;
}

sub remove {
  my ($self, $link) = @_;
  return $self->pg->db->delete('bot_requests', {external_link => $link}, {returning => 'package'})
    ->hashes->map(sub { $_->{package} })->to_array;
}

1;
