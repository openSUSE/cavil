# Copyright (C) 2018 SUSE Linux GmbH
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, see <http://www.gnu.org/licenses/>.

package Cavil::Model::Users;
use Mojo::Base -base, -signatures;

has 'pg';

sub add_role ($self, $id, $role) {
  $self->pg->db->query('update bot_users set roles = array_cat(roles, ?) where id = ?', [$role], $id);
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

sub licensedigger ($self) {
  $self->find_or_create(login => 'licensedigger', roles => ['bot'], comment => 'Legal-auto bot');
}

sub list ($self) { $self->pg->db->select('bot_users')->hashes->to_array }

sub remove_role ($self, $id, $role) {
  $self->pg->db->query('update bot_users set roles = array_remove(roles, ?) where id = ?', $role, $id);
}

sub roles ($self, $user) {
  return $self->pg->db->query('select roles from bot_users where login = ?', $user)->arrays->flatten->to_array;
}

1;
