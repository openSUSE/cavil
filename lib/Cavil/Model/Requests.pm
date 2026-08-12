# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package Cavil::Model::Requests;
use Mojo::Base -base, -signatures;

has 'pg';

sub add ($self, $link, $pkg) {
  my $db = $self->pg->db;
  $db->query('INSERT INTO bot_requests (external_link, package) VALUES (?, ?) ON CONFLICT DO NOTHING', $link, $pkg);
  return $db->query('SELECT id FROM bot_requests WHERE external_link = ? AND package = ?', $link, $pkg)->hash->{id};
}

sub all ($self) {
  return $self->pg->db->query(
    'SELECT br.external_link, array_agg(br.package) AS packages, array_agg(bp.checkout_dir) AS checkouts
     FROM bot_requests br JOIN bot_packages bp ON (br.package = bp.id)
     GROUP BY br.external_link'
  )->hashes->to_array;
}

sub find_by_link ($self, $link) {
  return $self->pg->db->query('SELECT package FROM bot_requests WHERE external_link = ?', $link)
    ->arrays->flatten->to_array;
}

sub remove ($self, $link) {
  return $self->pg->db->delete('bot_requests', {external_link => $link}, {returning => 'package'})
    ->hashes->map(sub { $_->{package} })->to_array;
}

1;
