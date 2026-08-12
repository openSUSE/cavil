# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package Cavil::Controller::Auth::OpenIDConnect;
use Mojo::Base 'Mojolicious::Controller', -signatures;

sub login ($self) {
  my $config = $self->oauth2->providers->{opensuse};

  # Required for id.opensuse.org
  $config->{authorize_url} .= '?response_type=code' unless $config->{authorize_url} =~ /response_type=/;

  my $callback_url = $self->url_for('openid')->to_abs->to_string;
  $self->oauth2->get_token_p('opensuse', {redirect_uri => $callback_url})->then(
    sub ($result) {
      return undef unless my $token = $result->{access_token};
      $self->ua->get_p($config->{userinfo_url} => {Authorization => "Bearer $token"});
    }
  )->then(
    sub ($tx) {
      return undef unless defined $tx;
      my $data = $tx->res->json;

      # Create in DB
      my $user  = $self->users->find_or_create(login => $data->{nickname}, email => $data->{email});
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
