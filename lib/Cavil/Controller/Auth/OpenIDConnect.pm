# Copyright (C) 2022 SUSE Linux GmbH
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

package Cavil::Controller::Auth::OpenIDConnect;
use Mojo::Base 'Mojolicious::Controller', -signatures;

sub login ($self) {
  my $config = $self->oauth2->providers->{opensuse};

  # Required for id.opensuse.org
  $config->{authorize_url} .= '?response_type=code' unless $config->{authorize_url} =~ /response_type=/;

  $self->oauth2->get_token_p('opensuse', {redirect_uri => 'https://legaldb.suse.de/oidc/callback'})->then(
    sub ($result) {
      return undef unless my $token = $result->{access_token};
      $self->ua->get_p($config->{userinfo_url} => {Authorization => "Bearer $token"});
    }
  )->then(
    sub ($tx) {
      return undef unless defined $tx;
      my $data = $tx->res->json;

      # Create in DB
      my $user  = $self->users->find_or_create(login => $data->{nickname}, email => $data->{email}, fullname => '');
      my $login = $user->{login};

      $self->session(user => $login);
      $self->log->info(qq{User "$login" logged in});
      $self->redirect_to('dashboard');
    }
  )->catch(
    sub ($error) {
      $self->log->error($error);
      $self->render(text => $error, status => 403);
    }
  );
}

1;
