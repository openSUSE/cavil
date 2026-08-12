# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package Cavil::Controller::Auth::Token;
use Mojo::Base 'Mojolicious::Controller', -signatures;

sub check ($self) {
  my $tokens = $self->app->config('tokens');
  return 1 unless @$tokens;

  $self->_denied and return undef unless my $auth = $self->req->headers->authorization;
  $self->_denied and return undef unless $auth =~ /^Token\ (\S+)$/;
  my $token = $1;

  $self->_denied and return undef unless grep { $token eq $_ } @$tokens;

  return 1;
}

sub _denied ($self) {
  $self->respond_to(
    json =>
      {json => {error => 'It appears you have insufficient permissions for accessing this resource'}, status => 403},
    any => {template => 'permissions', status => 403}
  );
}

1;
