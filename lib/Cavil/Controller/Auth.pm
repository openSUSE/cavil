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

package Cavil::Controller::Auth;
use Mojo::Base 'Mojolicious::Controller', -signatures;

sub check ($self) {
  my $role = $self->stash('role');
  my $user = $self->current_user;

  # User needs to log in or a different role
  $self->render('permissions', status => 403) and return undef unless $user && $self->users->has_role($user, $role);

  return 1;
}

sub logout ($self) {
  delete $self->session->{user};
  $self->redirect_to('dashboard');
}

1;
