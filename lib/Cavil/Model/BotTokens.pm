# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package Cavil::Model::BotTokens;
use Mojo::Base -base, -signatures;

use Cavil::Model::AuditLog qw(audit_event);

has 'pg';

# The token itself never goes into the audit log, which curators and lawyers can read
sub add ($self, $token, $login) {
  my $db = $self->pg->db;
  my $tx = $db->begin;
  my $id = $db->query(
    'INSERT INTO bot_tokens (token, description, owner)
       VALUES (COALESCE(?, gen_random_uuid()::text), ?, (SELECT id FROM bot_users WHERE login = ?))
       ON CONFLICT DO NOTHING RETURNING id', $token->{token}, $token->{description}, $login
  )->hash;
  return undef unless $id;
  audit_event(
    $db,
    type  => 'bot_token.added',
    actor => $db->select('bot_users', 'id', {login => $login})->hash->{id},
    data  => {description => $token->{description}}
  );
  $tx->commit;
  return $id->{id};
}

sub exists ($self, $token) { !!$self->pg->db->select('bot_tokens', 'id', {token => $token})->rows }

sub invalid ($self, $token) {
  return undef unless defined $token->{token};
  return 'The token cannot contain spaces'        if $token->{token} =~ /\s/;
  return 'The token needs at least 16 characters' if length $token->{token} < 16;
  return undef;
}

sub list ($self) {
  return $self->pg->db->query(
    'SELECT bt.id, bt.token, bt.description, EXTRACT(EPOCH FROM bt.created) AS created_epoch, bu.login
       FROM bot_tokens bt LEFT JOIN bot_users bu ON bu.id = bt.owner
      ORDER BY bt.created DESC, bt.id DESC'
  )->hashes->to_array;
}

sub remove ($self, $id, $login) {
  my $db = $self->pg->db;
  my $tx = $db->begin;
  return undef unless my $token = $db->delete('bot_tokens', {id => $id}, {returning => ['description']})->hash;
  audit_event(
    $db,
    type  => 'bot_token.removed',
    actor => $db->select('bot_users', 'id', {login => $login})->hash->{id},
    data  => $token
  );
  $tx->commit;
  return 1;
}

1;
