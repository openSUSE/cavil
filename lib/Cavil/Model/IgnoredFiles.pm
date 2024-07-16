# Copyright (C) 2024 SUSE LLC
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

package Cavil::Model::IgnoredFiles;
use Mojo::Base -base, -signatures;

use Cavil::Util qw(paginate);

has [qw(log pg)];

sub add ($self, $glob, $owner) {
  my $db = $self->pg->db;
  my $id = $db->query('SELECT id FROM bot_users WHERE login = ?', $owner)->hash->{id};
  $db->insert('ignored_files', {glob => $glob, owner => $id});
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
      SELECT if.id, if.glob, EXTRACT(EPOCH FROM if.created) AS created_epoch, bu.login, COUNT(*) OVER() AS total
      FROM ignored_files if JOIN bot_users bu ON (if.owner = bu.id)
      $search
      ORDER BY if.created DESC
      LIMIT ? OFFSET ?
    }, $options->{limit}, $options->{offset}
  )->hashes->to_array;

  return paginate($results, $options);
}

sub remove ($self, $id, $user) {
  return undef unless my $hash = $self->pg->db->delete('ignored_files', {id => $id}, {returning => ['glob']})->hash;
  $self->log->info(qq{User "$user" removed glob "$hash->{glob}"});
  return 1;
}

1;
