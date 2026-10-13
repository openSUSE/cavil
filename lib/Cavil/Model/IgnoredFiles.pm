# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package Cavil::Model::IgnoredFiles;
use Mojo::Base -base, -signatures;

use Cavil::Model::AuditLog qw(audit_event);
use Cavil::Util            qw(paginate);

has [qw(log pg)];

sub add ($self, $glob, $owner, $contributor = undef) {
  my $db = $self->pg->db;
  my $id = $db->query('SELECT id FROM bot_users WHERE login = ?', $owner)->hash->{id};

  my $contributor_id;
  if (defined $contributor) {
    $contributor_id = $db->query('SELECT id FROM bot_users WHERE login = ?', $contributor)->hash->{id};
  }

  my $tx = $db->begin;
  $db->insert('ignored_files',
    {glob => $glob, owner => $id, (defined $contributor_id ? (contributor => $contributor_id) : ())});
  audit_event(
    $db,
    type  => 'ignored_file.added',
    actor => $id,
    data  => {glob => $glob, defined $contributor_id ? (contributor => $contributor) : ()}
  );
  $tx->commit;
}

sub find_glob ($self, $glob) {
  my $hash = $self->pg->db->select('ignored_files', 'id', {glob => $glob})->hash;
  return $hash ? $hash->{id} : undef;
}

sub paginate_ignored_files ($self, $options) {
  my $db = $self->pg->db;

  my $search = '';
  if (length($options->{search}) > 0) {
    my $quoted = $db->dbh->quote("\%$options->{search}\%");
    $search = "WHERE glob ILIKE $quoted";
  }

  my $results = $db->query(
    qq{
      SELECT if.id, if.glob, EXTRACT(EPOCH FROM if.created) AS created_epoch, bu.login,
        bu2.login AS contributor_login, COUNT(*) OVER() AS total
      FROM ignored_files if JOIN bot_users bu ON (if.owner = bu.id)
        LEFT JOIN bot_users bu2 ON (if.contributor = bu2.id)
      $search
      ORDER BY if.created DESC
      LIMIT ? OFFSET ?
    }, $options->{limit}, $options->{offset}
  )->hashes->to_array;

  return paginate($results, $options);
}

sub remove ($self, $id, $user) {
  my $db = $self->pg->db;
  my $tx = $db->begin;
  return undef unless my $hash = $db->delete('ignored_files', {id => $id}, {returning => ['glob']})->hash;
  audit_event(
    $db,
    type  => 'ignored_file.removed',
    actor => $db->select('bot_users', 'id', {login => $user})->hash->{id},
    data  => {glob => $hash->{glob}}
  );
  $tx->commit;
  $self->log->info(qq{User "$user" removed glob "$hash->{glob}"});
  return 1;
}

1;
