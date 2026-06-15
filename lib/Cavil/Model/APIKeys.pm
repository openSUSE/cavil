package Cavil::Model::APIKeys;
use Mojo::Base -base, -signatures;

has 'pg';

sub create ($self, %args) {
  my $write_access = $args{type} eq 'read-write' ? 1 : 0;

  # can_finalize_reviews only meaningful with read-write; coerce off otherwise.
  my $can_finalize = ($write_access && $args{can_finalize_reviews}) ? 1 : 0;

  my %data = (
    owner                => $args{owner},
    description          => $args{description} // '',
    write_access         => $write_access,
    can_finalize_reviews => $can_finalize,
    expires              => $args{expires}
  );
  return $self->pg->db->insert('api_keys', \%data, {returning => '*'})->hash;
}

sub find_by_key ($self, $key) {
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

sub list ($self, $owner) {
  return $self->pg->db->query('SELECT *, EXTRACT(EPOCH FROM expires) AS expires_epoch FROM api_keys WHERE owner = ?',
    $owner)->hashes->to_array;
}

sub remove ($self, $id, $owner) {
  my $sth = $self->pg->db->dbh->prepare('DELETE FROM api_keys WHERE id = ? AND owner = ?');
  my $rc  = $sth->execute($id, $owner);
  return $rc > 0;
}

1;
