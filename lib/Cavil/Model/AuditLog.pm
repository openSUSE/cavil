# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package Cavil::Model::AuditLog;
use Mojo::Base -base, -signatures;

use Cavil::Util qw(paginate);

has 'pg';

# Exact matches only, a substring would mix in every package sharing a prefix (gcc, gcc13, cross-gcc...)
sub paginate_events ($self, $options) {
  my $search = $options->{search} // '';
  my ($where, @bind) = ('');
  if ($search =~ /^\d+$/ && $search < 2**31) {
    ($where, @bind) = ('WHERE e.package = ? OR e.package_name = ?', $search, $search);
  }
  elsif (length $search) { ($where, @bind) = ('WHERE e.package_name = ?', $search) }

  my $db      = $self->pg->db;
  my $results = $db->query(
    qq{
      SELECT e.id, e.type, e.package, e.package_name, e.data, EXTRACT(EPOCH FROM e.created) AS created_epoch,
        u.login, p.checksum AS package_checksum, COUNT(*) OVER() AS total
      FROM audit_events e LEFT JOIN bot_packages p ON p.id = e.package LEFT JOIN bot_users u ON u.id = e.actor
      $where
      ORDER BY e.id DESC
      LIMIT ? OFFSET ?
    }, @bind, $options->{limit}, $options->{offset}
  )->expand->hashes->to_array;

  # A page past the end has no row to carry the window count
  my $page = paginate($results, $options);
  $page->{total} = $db->query("SELECT count(*) FROM audit_events e $where", @bind)->array->[0]
    if !@$results && $options->{offset};
  return $page;
}

1;
