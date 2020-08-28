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

package Cavil::Model::Products;
use Mojo::Base -base;

has 'pg';

sub all { shift->pg->db->select('bot_products')->hashes->to_array }

sub find_or_create {
  my ($self, $name) = @_;

  my $db = $self->pg->db;
  if (my $product = $db->select('bot_products', '*', {name => $name})->hash) {
    return $product;
  }

  return $db->insert('bot_products', {name => $name}, {returning => '*'})->hash;
}

sub for_package {
  my ($self, $id) = @_;
  return $self->pg->db->select(['bot_package_products', ['bot_products', id => 'product']],
    'name', {'bot_package_products.package' => $id})->arrays->flatten->to_array;
}

sub list {
  my ($self, $name) = @_;

  my $db = $self->pg->db;
  return [] unless my $product = $db->select('bot_products', 'id', {name => $name})->hash;

  return $db->query(
    'select bot_packages.name, bot_packages.id,
       extract(epoch from bot_packages.created) as created_epoch, state,
       checksum
     from bot_package_products
       join bot_packages on (bot_packages.id = bot_package_products.package)
     where bot_package_products.product = ?', $product->{id}
  )->hashes->to_array;
}

sub update {
  my ($self, $product, $packages) = @_;
  my $db = $self->pg->db;
  $db->delete('bot_package_products', {product => $product});
  $db->query(
    'insert into bot_package_products (product, package) values (?, ?)
     on conflict do nothing', $product, $_
  ) for @$packages;
}

1;
