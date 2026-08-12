# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package Cavil::Controller::Auth::APIKey;
use Mojo::Base 'Mojolicious::Controller', -signatures;

sub check ($self) {
  $self->_denied and return undef unless my $auth = $self->req->headers->authorization;
  $self->_denied and return undef unless $auth =~ /^Bearer\ (\S+)$/;
  my $token = $1;

  $self->_denied and return undef unless defined(my $user = $self->api_keys->find_by_key($token));

  # Capability scopes, derived from the key for now (later straight from the key's own scopes)
  my @scopes = ('cavil:read');
  push @scopes, 'cavil:write'            if $user->{write_access};
  push @scopes, 'cavil:reviews.finalize' if $user->{can_finalize_reviews};

  $self->stash(
    'cavil.api.user'         => $user->{login},
    'cavil.api.write_access' => $user->{write_access},
    'cavil.api.scopes'       => \@scopes
  );

  return 1;
}

sub _denied ($self) {
  $self->render(
    json   => {error => 'It appears you have insufficient permissions for accessing this resource'},
    status => 403
  );
}

1;
