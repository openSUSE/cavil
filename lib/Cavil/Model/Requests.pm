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
use Mojo::Base -base, -signatures;

has 'pg';

sub add ($self, $link, $pkg) {
  my $req = {external_link => $link, package => $pkg};
  return $self->pg->db->insert('bot_requests', $req, {returning => 'id'})->hash->{id};
}

sub all ($self) {
  return $self->pg->db->query(
    'select external_link, array_agg(package) as packages from bot_requests
     group by external_link'
  )->hashes->to_array;
}

sub remove ($self, $link) {
  my $db = $self->pg->db;

  # External link might be a product, then we only want to remove the packages from it that are not part of the product
  # anymore
  my $results = $db->query(
    'delete from bot_requests as br
     where external_link = $1 and not exists (
       select 1 from bot_package_products as bpp join bot_products as bp on bp.id = bpp.product
       where bp.name = $1 and bpp.package = br.id
     ) returning id', $link
  )->arrays->flatten->to_array;

  return $results;

}

1;
