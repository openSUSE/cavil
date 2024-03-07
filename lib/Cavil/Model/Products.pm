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
use Mojo::Base -base, -signatures;

use Cavil::Util qw(paginate);

has 'pg';

sub all ($self) { $self->pg->db->select('bot_products')->hashes->to_array }

sub find_or_create ($self, $name) {
  my $db = $self->pg->db;
  if (my $product = $db->select('bot_products', '*', {name => $name})->hash) {
    return $product;
  }

  return $db->insert('bot_products', {name => $name}, {returning => '*'})->hash;
}

sub for_package ($self, $id) {
  return $self->pg->db->select(['bot_package_products', ['bot_products', id => 'product']],
    'name', {'bot_package_products.package' => $id})->arrays->flatten->to_array;
}

sub paginate_known_products ($self, $options) {
  my $db = $self->pg->db;

  my $search = '';
  if (length($options->{search}) > 0) {
    my $quoted = $db->dbh->quote("\%$options->{search}\%");
    $search = "WHERE name ILIKE $quoted";
  }

  my $results = $db->query(
    qq{
      SELECT *, COUNT(*) OVER() AS total
      FROM bot_products
      $search
      ORDER BY id DESC
      LIMIT ? OFFSET ?
    }, $options->{limit}, $options->{offset}
  )->hashes->to_array;

  for my $result (@$results) {
    my $packages = $db->query(
      q{
      SELECT COUNT(*) FILTER (WHERE state = 'new') AS new_packages,
        COUNT(*) FILTER (WHERE state = 'unacceptable') AS unacceptable_packages,
        COUNT(*) FILTER (WHERE state = 'acceptable' OR state = 'correct') AS reviewed_packages
      FROM bot_package_products JOIN bot_packages ON (bot_packages.id = bot_package_products.package)
      WHERE bot_package_products.product = ?}, $result->{id}
    )->hash;
    $result->{reviewed_packages}     = $packages->{reviewed_packages};
    $result->{new_packages}          = $packages->{new_packages};
    $result->{unacceptable_packages} = $packages->{unacceptable_packages};
  }

  return paginate($results, $options);
}

sub update ($self, $product, $packages) {
  my $db = $self->pg->db;
  $db->delete('bot_package_products', {product => $product});
  $db->query(
    'insert into bot_package_products (product, package) values (?, ?)
     on conflict do nothing', $product, $_
  ) for @$packages;
}

1;
