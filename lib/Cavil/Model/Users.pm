# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package Cavil::Model::Users;
use Mojo::Base -base, -signatures;

use Cavil::Role qw(role_conflict);

has 'pg';

sub add_role ($self, $id, $role) {
  my $db = $self->pg->db;
  if (my $user = $db->select('bot_users', ['roles'], {id => $id})->hash) {
    my $conflict = role_conflict($role, @{$user->{roles}});
    die qq{Role "$role" cannot be combined with "$conflict", bot accounts only hold the "agent" role\n}
      if defined $conflict;
  }
  $db->query('update bot_users set roles = array_cat(roles, ?) where id = ?', [$role], $id);
}

sub find ($self, %args) {
  my %where = map { $_ => $args{$_} } grep { exists $args{$_} } qw(id login);
  return $self->pg->db->select('bot_users', '*', \%where)->hash;
}

sub find_or_create ($self, %args) {
  if (my $user = $self->find(%args)) { return $user }
  return $self->pg->db->insert('bot_users', \%args, {returning => '*'})->hash;
}

sub has_role ($self, $user, @roles) {
  return 1 if !@roles;
  return undef unless my $result = $self->pg->db->query('select roles from bot_users where login = ?', $user)->hash;
  for my $role (@roles) {
    return 1 if grep { $_ eq $role } @{$result->{roles}};
  }
  return 0;
}

sub id_for_login ($self, $login) {
  return undef unless my $hash = $self->pg->db->query('select id from bot_users where login = ?', $login)->hash;
  return $hash->{id};
}

sub grant_first_admin ($self, $id) {
  return $self->pg->db->query(
    q{UPDATE bot_users SET roles = array_append(roles, 'admin')
       WHERE id = ? AND NOT 'admin' = ANY(roles) AND NOT 'agent' = ANY(roles)
         AND NOT EXISTS (SELECT 1 FROM bot_users WHERE 'admin' = ANY(roles))}, $id
  )->rows;
}

sub licensedigger ($self) {
  $self->find_or_create(login => 'licensedigger', roles => ['bot'], comment => 'Legal-auto bot');
}

sub list ($self) { $self->pg->db->select('bot_users')->hashes->to_array }

sub remove_role ($self, $id, $role) {
  $self->pg->db->query('update bot_users set roles = array_remove(roles, ?) where id = ?', $role, $id);
}

sub roles ($self, $user) {
  return $self->pg->db->query('select roles from bot_users where login = ?', $user)->arrays->flatten->sort->to_array;
}

1;
