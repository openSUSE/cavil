package Cavil::Model::APIKeys;
use Mojo::Base -base, -signatures;

has 'pg';

sub create ($self, %args) {
  my %data = (
    owner        => $args{owner},
    description  => $args{description} // '',
    write_access => $args{type} eq 'read-write' ? 1 : 0,
    expires      => $args{expires}
  );
  return $self->pg->db->insert('api_keys', \%data, {returning => '*'})->hash;
}

sub find_by_key ($self, $key) {
  return undef unless my $user = $self->pg->db->query(
    'SELECT * FROM api_keys ak JOIN bot_users bu ON ak.owner = bu.id
     WHERE ak.api_key = ? AND expires > NOW()', $key
  )->hash;
  return {login => $user->{login}, write_access => $user->{write_access}};
}

sub list ($self, $owner) {
  return $self->pg->db->query('SELECT *, EXTRACT(EPOCH FROM expires) AS expires_epoch FROM api_keys WHERE owner = ?',
    $owner)->hashes->to_array;
}

sub remove ($self, $id, $owner) {
  return $self->pg->db->delete('api_keys', {id => $id, owner => $owner})->rows;
}

1;
