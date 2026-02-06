# Copyright (C) 2026 SUSE LLC
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

package Cavil::Controller::Auth::APIKey;
use Mojo::Base 'Mojolicious::Controller', -signatures;

sub check ($self) {
  $self->_denied and return undef unless my $auth = $self->req->headers->authorization;
  $self->_denied and return undef unless $auth =~ /^Bearer\ (\S+)$/;
  my $token = $1;

  $self->_denied and return undef unless defined(my $user = $self->api_keys->find_by_key($token));
  $self->stash('cavil.api.user' => $user->{login}, 'cavil.api.write_access' => $user->{write_access});

  return 1;
}

sub _denied ($self) {
  $self->render(
    json   => {error => 'It appears you have insufficient permissions for accessing this resource'},
    status => 403
  );
}

1;
