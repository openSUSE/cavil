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

has [qw(pg)];

sub add ($self, $glob, $owner) {
  my $db = $self->pg->db;
  my $id = $db->query('SELECT id FROM bot_users WHERE login = ?', $owner)->hash->{id};
  $db->insert('ignored_files', {glob => $glob, owner => $id});
}

1;
