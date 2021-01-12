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

package Cavil::Controller::Auth::OpenID;
use Mojo::Base 'Mojolicious::Controller', -signatures;

use LWP::UserAgent;
use Net::OpenID::Consumer;

sub login ($self) {
  $self->redirect_to('openid');
}

sub openid ($self) {
  my $base = $self->req->url->base->to_string;

  my $csr = Net::OpenID::Consumer->new(
    ua              => LWP::UserAgent->new,
    required_root   => $base,
    consumer_secret => $self->app->config->{openid}{secret}
  );
  my $claimed_id = $csr->claimed_identity($self->app->config->{openid}{provider});
  return $self->render(text => $csr->err, status => 403) unless $claimed_id;

  $claimed_id->set_extension_args('http://openid.net/extensions/sreg/1.1',
    {required => 'email', optional => 'fullname,nickname'});
  $claimed_id->set_extension_args(
    'http://openid.net/srv/ax/1.0',
    {
      mode             => 'fetch_request',
      required         => 'email,fullname,nickname,firstname,lastname',
      'type.email'     => "http://schema.openid.net/contact/email",
      'type.fullname'  => "http://axschema.org/namePerson",
      'type.nickname'  => "http://axschema.org/namePerson/friendly",
      'type.firstname' => 'http://axschema.org/namePerson/first',
      'type.lastname'  => 'http://axschema.org/namePerson/last'
    }
  );

  my $check_url = $claimed_id->check_url(
    delayed_return => 1,
    return_to      => $self->url_for('response')->to_abs->to_string,
    trust_root     => $base
  );

  return $self->redirect_to($check_url) if $check_url;
  $self->render(text => $csr->err, status => 403);
}

sub response ($self) {
  my $params = $self->req->params->to_hash;
  my $base   = $self->req->url->base->to_string;

  my $csr = Net::OpenID::Consumer->new(
    ua              => LWP::UserAgent->new,
    required_root   => $base,
    consumer_secret => $self->app->config->{openid}{secret},
    args            => $params
  );

  my ($error, $login, $email, $fullname);
  $csr->handle_server_response(
    not_openid   => sub { $error = 'Not an OpenID message' },
    setup_needed => sub { $error = 'Setup not supported' },
    cancelled    => sub { $error = 'Authentication cancelled' },
    verified     => sub {
      my $vident = shift;

      my $sreg = $vident->signed_extension_fields('http://openid.net/extensions/sreg/1.1');
      my $ax   = $vident->signed_extension_fields('http://openid.net/srv/ax/1.0');

      $error = 'Missing username' unless $login = $sreg->{nickname} || $ax->{'value.nickname'};

      $email    = $sreg->{email}    || $ax->{'value.email'};
      $fullname = $sreg->{fullname} || $ax->{'value.fullname'};
    },
    error => sub {
      my ($err, $txt) = @_;
      $error = "$err: $txt";
    },
  );

  return $self->render(text => $error, status => 403) if $error;

  # Create in DB
  my $user = $self->users->find_or_create(login => $login, email => $email, fullname => $fullname);

  $self->session(user => $user->{login});
  $self->redirect_to('dashboard');
}

1;
