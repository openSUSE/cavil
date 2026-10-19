# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package Cavil::Model::Requests;
use Mojo::Base -base, -signatures;

has 'pg';

sub add ($self, $link, $pkg, $target = undef) {
  my $db    = $self->pg->db;
  my $added = $db->query(
    'INSERT INTO bot_requests (external_link, package, target) VALUES (?, ?, ?)
     ON CONFLICT (external_link, package) DO UPDATE SET removed = NULL, target = EXCLUDED.target
     WHERE bot_requests.removed IS NOT NULL', $link, $pkg, $target
  )->rows;

  # After the insert, so a concurrent removal of another request can never retire a package this one needs
  $db->query('UPDATE bot_packages SET obsolete = false WHERE id = ?', $pkg);
  return $added;
}

sub unresolved_targets ($self, $package) {
  return $self->pg->db->query(
    'SELECT id, external_link FROM bot_requests WHERE package = ? AND target IS NULL AND removed IS NULL', $package)
    ->hashes->to_array;
}

sub set_target ($self, $id, $target) {
  $self->pg->db->query('UPDATE bot_requests SET target = ? WHERE id = ?', $target, $id);
}

sub all ($self) {
  return $self->pg->db->query(
    'SELECT br.external_link, array_agg(br.package ORDER BY br.id) AS packages,
       array_agg(bp.checkout_dir ORDER BY br.id) AS checkouts
     FROM bot_requests br JOIN bot_packages bp ON (br.package = bp.id)
     WHERE br.removed IS NULL
     GROUP BY br.external_link'
  )->hashes->to_array;
}

# Closed requests are kept, so a lawyer can still look a review up by an id that is no longer active
sub remove ($self, $link) {
  return $self->pg->db->query(
    'UPDATE bot_requests SET removed = NOW() WHERE external_link = ? AND removed IS NULL RETURNING package', $link)
    ->arrays->flatten->to_array;
}

1;
