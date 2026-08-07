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

sub find ($self, $name) { $self->pg->db->select('bot_products', '*', {name => $name})->hash }

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

# Like for_package, but also returns the curated product annotation for each codestream, so callers can
# collapse the raw codestream names into their human product name (falling back to the name when unset)
sub for_package_products ($self, $id) {
  return $self->pg->db->query(
    'SELECT p.name, p.product FROM bot_package_products pp JOIN bot_products p ON (p.id = pp.product)
     WHERE pp.package = ? ORDER BY p.name', $id
  )->hashes->to_array;
}

# The codestream names that roll up to a curated product, so the aggregate group page can offer a curator a
# way back down to each individual codestream (where its annotation can be changed or cleared)
sub codestreams_for_product ($self, $product) {
  return $self->pg->db->select('bot_products', 'name', {product => $product}, {order_by => 'name'})
    ->arrays->flatten->to_array;
}

# Attach a codestream to a curated product (the human deliverable name it rolls up to), or clear it when
# the product is empty. Keyed by name so it works whether or not the sync bot has created the row yet, and
# it only touches the annotation column, so a later sync (which rewrites membership) never clobbers it
sub set_annotation ($self, $name, $product) {
  my $db  = $self->pg->db;
  my $obj = $self->find_or_create($name);
  $product = undef if defined $product && $product eq '';
  $db->update('bot_products', {product => $product}, {id => $obj->{id}});
  return $product;
}

sub paginate_known_products ($self, $options) {
  my $db = $self->pg->db;

  my $search = '';
  if (length($options->{search}) > 0) {
    my $quoted = $db->dbh->quote("\%$options->{search}\%");
    $search = "WHERE name ILIKE $quoted OR product ILIKE $quoted";
  }

  # Default view collapses codestreams by their curated product name (falling back to the raw codestream
  # name when unannotated), so one deliverable spread across many codestreams becomes a single row. The
  # flat view ("All codestreams") instead lists every codestream on its own, with its annotation exposed,
  # so a curator can audit the product mapping across the whole fleet at a glance
  my $grouped = ($options->{grouped} // 'true') eq 'true';

  my $results;
  if ($grouped) {
    $results = $db->query(
      qq{
        SELECT COALESCE(product, name) AS name, COUNT(*) AS streams,
          EXTRACT(EPOCH FROM MAX(updated)) AS updated_epoch, COUNT(*) OVER() AS total
        FROM bot_products
        $search
        GROUP BY COALESCE(product, name)
        ORDER BY MAX(updated) DESC, name DESC
        LIMIT ? OFFSET ?
      }, $options->{limit}, $options->{offset}
    )->hashes->to_array;
  }
  else {
    $results = $db->query(
      qq{
        SELECT name, product AS annotation, 1 AS streams,
          EXTRACT(EPOCH FROM updated) AS updated_epoch, COUNT(*) OVER() AS total
        FROM bot_products
        $search
        ORDER BY updated DESC, name DESC
        LIMIT ? OFFSET ?
      }, $options->{limit}, $options->{offset}
    )->hashes->to_array;
  }

  # Package counts for a row: a group sums across every codestream that rolls up to it, a flat codestream
  # counts only its own membership
  for my $result (@$results) {
    my $where = $grouped ? 'COALESCE(bot_products.product, bot_products.name) = ?' : 'bot_products.name = ?';

    # COUNT(DISTINCT id): a package shared by several codestreams of one product must count once, not once
    # per codestream, or grouped products with overlapping codestreams inflate their review totals
    my $packages = $db->query(
      qq{
      SELECT COUNT(DISTINCT bot_packages.id) FILTER (WHERE state = 'new') AS new_packages,
        COUNT(DISTINCT bot_packages.id) FILTER (WHERE state = 'unacceptable') AS unacceptable_packages,
        COUNT(DISTINCT bot_packages.id) FILTER (WHERE state = 'acceptable' OR state = 'acceptable_by_lawyer')
          AS reviewed_packages
      FROM bot_package_products
        JOIN bot_packages ON (bot_packages.id = bot_package_products.package)
        JOIN bot_products ON (bot_products.id = bot_package_products.product)
      WHERE $where}, $result->{name}
    )->hash;
    $result->{reviewed_packages}     = $packages->{reviewed_packages};
    $result->{new_packages}          = $packages->{new_packages};
    $result->{unacceptable_packages} = $packages->{unacceptable_packages};
  }

  return paginate($results, $options);
}

sub remove ($self, $name) {
  my $sth = $self->pg->db->dbh->prepare('DELETE FROM bot_products WHERE name = ?');
  my $rc  = $sth->execute($name);
  return $rc > 0;
}

sub update ($self, $product, $packages) {
  my $db = $self->pg->db;

  my $updated
    = $db->query('SELECT created FROM bot_packages WHERE id = ANY(?) ORDER BY created DESC LIMIT 1', $packages)
    ->hash->{created};
  $db->query('UPDATE bot_products SET updated = ? WHERE id = ?', $updated, $product);

  $db->delete('bot_package_products', {product => $product});
  $db->query(
    'insert into bot_package_products (product, package) values (?, ?)
     on conflict do nothing', $product, $_
  ) for @$packages;
}

1;
