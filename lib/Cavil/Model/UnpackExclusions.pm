# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package Cavil::Model::UnpackExclusions;
use Mojo::Base -base, -signatures;

use Cavil::Model::AuditLog qw(audit_event);
use Cavil::Util            qw(paginate);
use Text::Glob             qw(glob_to_regex);

has 'pg';

sub add ($self, $rule, $login) {
  my $db = $self->pg->db;
  my $tx = $db->begin;
  my $id = $db->query(
    'INSERT INTO unpack_exclusions (package_glob, file, reason, owner)
       VALUES (?, ?, ?, (SELECT id FROM bot_users WHERE login = ?))
       ON CONFLICT DO NOTHING RETURNING id', @$rule{qw(package_glob file reason)}, $login
  )->hash;
  return undef unless $id;
  audit_event(
    $db,
    type  => 'unpack_exclusion.added',
    actor => $db->select('bot_users', 'id', {login => $login})->hash->{id},
    data  => {%$rule{qw(package_glob file reason)}}
  );
  $tx->commit;
  return $id->{id};
}

sub for_package ($self, $name) {
  local $Text::Glob::strict_wildcard_slash = 0;
  return [map { $_->{file} }
    grep { $name =~ glob_to_regex($_->{package_glob}) }
      $self->pg->db->query('SELECT package_glob, file FROM unpack_exclusions ORDER BY id')->hashes->each];
}

# Every unpack compiles every rule, so one that does not compile would stop unpacking everywhere. File::Unpack2 only
# escapes some regex characters in file names, the rest would change what gets excluded.
sub invalid ($self, $rule) {
  local $Text::Glob::strict_wildcard_slash = 0;
  return 'The package pattern is not valid' unless eval { glob_to_regex($rule->{package_glob}); 1 };
  return 'The file name cannot contain any of | \\ + ^ $' if $rule->{file} =~ /[|\\+^\$]/;
  return undef;
}

sub paginate_exclusions ($self, $options) {
  my $db = $self->pg->db;

  my $search = '';
  if (length($options->{search}) > 0) {
    my $quoted = $db->dbh->quote("\%$options->{search}\%");
    $search = "WHERE ue.package_glob ILIKE $quoted OR ue.file ILIKE $quoted OR ue.reason ILIKE $quoted";
  }

  my $results = $db->query(
    qq{
      SELECT ue.id, ue.package_glob, ue.file, ue.reason, EXTRACT(EPOCH FROM ue.created) AS created_epoch, bu.login,
        COUNT(*) OVER() AS total
      FROM unpack_exclusions ue JOIN bot_users bu ON (ue.owner = bu.id)
      $search
      ORDER BY ue.created DESC, ue.id DESC
      LIMIT ? OFFSET ?
    }, $options->{limit}, $options->{offset}
  )->hashes->to_array;

  return paginate($results, $options);
}

sub remove ($self, $id, $login) {
  my $db = $self->pg->db;
  my $tx = $db->begin;
  return undef
    unless my $rule
    = $db->delete('unpack_exclusions', {id => $id}, {returning => [qw(package_glob file reason)]})->hash;
  audit_event(
    $db,
    type  => 'unpack_exclusion.removed',
    actor => $db->select('bot_users', 'id', {login => $login})->hash->{id},
    data  => $rule
  );
  $tx->commit;
  return 1;
}

1;
