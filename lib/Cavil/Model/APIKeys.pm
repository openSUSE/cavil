# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package Cavil::Model::APIKeys;
use Mojo::Base -base, -signatures;

has 'pg';

my $UUID = qr/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

sub create ($self, %args) {
  my $write_access = $args{type} eq 'read-write' ? 1 : 0;

  # can_finalize_reviews only meaningful with read-write; coerce off otherwise.
  my $can_finalize = ($write_access && $args{can_finalize_reviews}) ? 1 : 0;

  my %data = (
    owner                => $args{owner},
    description          => $args{description} // '',
    write_access         => $write_access,
    can_finalize_reviews => $can_finalize,
    expires              => $args{expires},
    oauth_client         => $args{oauth_client}
  );
  return $self->pg->db->insert('api_keys', \%data, {returning => '*'})->hash;
}

sub create_code ($self, %args) {
  my $db = $self->pg->db;
  $db->query('DELETE FROM oauth_codes WHERE expires < NOW()');
  return $db->insert('oauth_codes', \%args, {returning => 'code'})->hash->{code};
}

sub find_by_key ($self, $key) {
  return undef unless $key =~ $UUID;
  return undef unless my $user = $self->pg->db->query(
    'SELECT * FROM api_keys ak JOIN bot_users bu ON ak.owner = bu.id
     WHERE ak.api_key = ? AND expires > NOW()', $key
  )->hash;
  return {
    login                => $user->{login},
    write_access         => $user->{write_access},
    can_finalize_reviews => $user->{can_finalize_reviews}
  };
}

sub find_client ($self, $id) {
  return undef unless $id =~ $UUID;
  return $self->pg->db->select('oauth_clients', '*', {id => $id})->hash;
}

sub list ($self, $owner) {
  return $self->pg->db->query('SELECT *, EXTRACT(EPOCH FROM expires) AS expires_epoch FROM api_keys WHERE owner = ?',
    $owner)->hashes->to_array;
}

sub redeem_code ($self, $code) {
  return undef unless $code =~ $UUID;
  return $self->pg->db->query('DELETE FROM oauth_codes WHERE code = ? AND expires > NOW() RETURNING *', $code)->hash;
}

sub register_client ($self, %args) {
  return $self->pg->db->insert('oauth_clients', \%args, {returning => 'id'})->hash->{id};
}

sub remove ($self, $id, $owner) {
  my $sth = $self->pg->db->dbh->prepare('DELETE FROM api_keys WHERE id = ? AND owner = ?');
  my $rc  = $sth->execute($id, $owner);
  return $rc > 0;
}

1;
