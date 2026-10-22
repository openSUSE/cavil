# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package Cavil::Model::AuditLog;
use Mojo::Base -base, -signatures;

use Cavil::Util qw(paginate);
use Exporter 'import';

our @EXPORT_OK = qw(audit_event CATEGORIES);

use constant CATEGORIES => {
  reviews     => ['review.%'],
  limitations => ['limitation.%'],
  patterns    => ['pattern.%',       'license.%'],
  ignored     => ['ignored_match.%', 'ignored_file.%',     'snippet.%'],
  settings    => ['settings.%',      'unpack_exclusion.%', 'bot_token.%']
};

has 'pg';

# Callers pass the handle of the transaction making the change, so the event commits or rolls back with it
sub audit_event ($db, %event) {
  $event{data} = {-json => $event{data} // {}};
  $db->insert('audit_events', \%event);
}

# Settings events can be narrowed down to the keys of one section
sub last_event ($self, $types, $keys = undef) {
  my $only = $keys ? q{AND (jsonb_exists_any(e.data->'changes', ?) OR jsonb_exists_any(e.data->'reset', ?))} : '';
  return $self->pg->db->query(
    "SELECT EXTRACT(EPOCH FROM e.created) AS created_epoch, u.login
       FROM audit_events e LEFT JOIN bot_users u ON u.id = e.actor
      WHERE e.type = ANY(?) $only ORDER BY e.id DESC LIMIT 1", $types, $keys ? ($keys, $keys) : ()
  )->hash;
}

# Exact matches only, a substring would mix in every package sharing a prefix (gcc, gcc13, cross-gcc...)
sub paginate_events ($self, $options) {
  my $search = $options->{search} // '';
  my (@where, @bind);
  if ($search =~ /^\d+$/ && $search < 2**31) {
    push @where, '(e.package = ? OR e.package_name = ?)';
    push @bind, $search, $search;
  }
  elsif (length $search) { push @where, 'e.package_name = ?'; push @bind, $search }
  push @where, 'e.actor IS NOT NULL' if $options->{by_user};
  if (my $types = CATEGORIES->{$options->{category} // ''}) { push @where, 'e.type LIKE ANY(?)'; push @bind, $types }
  my $where = @where ? 'WHERE ' . join(' AND ', @where) : '';

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
