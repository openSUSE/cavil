# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package Cavil::Controller::Auth::OpenIDConnect;
use Mojo::Base 'Mojolicious::Controller', -signatures;

use List::Util qw(first);

sub login ($self) {
  my $config = $self->oauth2->providers->{opensuse};

  # OpenID Connect requires "response_type" (id.opensuse.org and Authentik reject requests without), the plugin omits it
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
      my $data = $tx->res->json // {};

      # "nickname" first keeps existing logins stable, an unverified email must not claim an email-based login
      my @claims   = qw(nickname preferred_username);
      my $verified = $data->{email_verified};
      push @claims, 'email' unless defined $verified && (!$verified || $verified eq 'false');
      my $claim = first { length($data->{$_} // '') } @claims;
      unless (defined $claim) {
        $self->log->error('OpenID Connect userinfo has no usable login, claims: ' . join(', ', sort keys %$data));
        return $self->render(text => 'OpenID Connect provider did not supply a username or verified email',
          status => 403);
      }

      my $user  = $self->users->find_or_create(login => $data->{$claim}, email => $data->{email});
      my $login = $user->{login};

      $self->session(user => $login);
      $self->log->info(qq{User "$login" logged in});
      $self->redirect_to(delete $self->session->{return_to} // 'dashboard');
    }
  )->catch(
    sub ($error) {
      $self->log->error($error);
      $self->render(text => $error, status => 403);
    }
  );
}

1;
