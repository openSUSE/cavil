# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package Cavil::Controller::OAuth;
use Mojo::Base 'Mojolicious::Controller', -signatures;

use Digest::SHA  qw(sha256);
use MIME::Base64 qw(encode_base64url);
use Mojo::Date;
use Mojo::URL;
use Text::Glob qw(match_glob);

my @PARAMS = qw(client_id redirect_uri response_type code_challenge code_challenge_method state resource);
my @SCOPES = ('cavil:read', 'cavil:write', 'cavil:reviews.finalize');

sub authorize ($self) {
  my $req = $self->_request;
  return $self->render(text => $req->{fatal}, status => 400) if $req->{fatal};
  return $self->_back($req->{uri}, error => $req->{error})   if $req->{error};

  return $self->_login unless $self->current_user;

  my $host = Mojo::URL->new($req->{uri})->host;
  $self->render('oauth/consent', client => $req->{client}, host => $host, params => \@PARAMS);
}

sub consent ($self) {
  my $req = $self->_request;
  return $self->render(text => $req->{fatal}, status => 400) if $req->{fatal};
  return $self->_login unless $self->current_user;
  return $self->render(text => 'Bad CSRF token', status => 403) if $self->validation->csrf_protect->has_error;
  return $self->_back($req->{uri}, error => $req->{error}) if $req->{error};
  return $self->_back($req->{uri}, error => 'access_denied') unless $self->param('allow');

  my $write = $self->param('write_access') ? 1 : 0;
  my $code  = $self->api_keys->create_code(
    client               => $req->{client}{id},
    owner                => $self->users->id_for_login($self->current_user),
    redirect_uri         => $req->{uri},
    code_challenge       => $self->param('code_challenge'),
    write_access         => $write,
    can_finalize_reviews => $write && $self->param('can_finalize_reviews') ? 1 : 0
  );
  $self->_back($req->{uri}, code => $code, iss => $self->_issuer);
}

sub metadata ($self) {
  my $issuer = $self->_issuer;
  $self->render(
    json => {
      issuer                                => $issuer,
      authorization_endpoint                => "$issuer/oauth/authorize",
      token_endpoint                        => "$issuer/oauth/token",
      registration_endpoint                 => "$issuer/oauth/register",
      scopes_supported                      => \@SCOPES,
      response_types_supported              => ['code'],
      grant_types_supported                 => ['authorization_code'],
      code_challenge_methods_supported      => ['S256'],
      token_endpoint_auth_methods_supported => ['none']
    }
  );
}

sub protected_resource ($self) {
  $self->render(
    json => {
      resource                 => $self->_resource,
      authorization_servers    => [$self->_issuer],
      scopes_supported         => \@SCOPES,
      bearer_methods_supported => ['header']
    }
  );
}

sub register ($self) {
  my $meta = $self->req->json;
  return $self->_error('invalid_client_metadata') unless ref $meta eq 'HASH';
  my $uris = $meta->{redirect_uris};
  return $self->_error('invalid_redirect_uri')
    unless ref $uris eq 'ARRAY' && @$uris && !grep { !$self->_allowed_uri($_) } @$uris;

  my $name = substr($meta->{client_name} // 'MCP client', 0, 100);
  my $id   = $self->api_keys->register_client(name => $name, redirect_uris => $uris);
  $self->render(
    status => 201,
    json   => {
      client_id                  => $id,
      client_name                => $name,
      redirect_uris              => $uris,
      token_endpoint_auth_method => 'none',
      grant_types                => ['authorization_code'],
      response_types             => ['code']
    }
  );
}

sub token ($self) {
  $self->res->headers->cache_control('no-store');
  return $self->_error('unsupported_grant_type') unless ($self->param('grant_type') // '') eq 'authorization_code';

  my $code     = $self->param('code')          // '';
  my $verifier = $self->param('code_verifier') // '';
  return $self->_error('invalid_grant') unless (my $grant = $self->api_keys->redeem_code($code));
  return $self->_error('invalid_grant')
    unless $grant->{client} eq ($self->param('client_id') // '')
    && $grant->{redirect_uri} eq ($self->param('redirect_uri') // '')
    && encode_base64url(sha256($verifier)) eq $grant->{code_challenge};

  my $client  = $self->api_keys->find_client($grant->{client});
  my $seconds = $self->config->{oauth_token_expiration} // 90 * 86400;
  my $key     = $self->api_keys->create(
    owner                => $grant->{owner},
    description          => "$client->{name} (OAuth)",
    type                 => $grant->{write_access} ? 'read-write' : 'read-only',
    can_finalize_reviews => $grant->{can_finalize_reviews},
    expires              => Mojo::Date->new(time + $seconds)->to_datetime,
    oauth_client         => $client->{id}
  );

  my @scopes = ('cavil:read');
  push @scopes, 'cavil:write'            if $key->{write_access};
  push @scopes, 'cavil:reviews.finalize' if $key->{can_finalize_reviews};
  $self->render(
    json => {access_token => $key->{api_key}, token_type => 'Bearer', expires_in => $seconds, scope => "@scopes"});
}

sub _allowed_uri ($self, $uri) {
  my $url  = Mojo::URL->new($uri);
  my $host = ($url->host // '') =~ tr/[]//dr;
  return undef unless ($url->scheme // '') eq 'https' || (($url->scheme // '') eq 'http' && _loopback($host));
  return 1 unless my $hosts = $self->config->{oauth_redirect_hosts};
  return !!grep { match_glob($_, $host) } @$hosts;
}

sub _back ($self, $uri, %params) {
  my $url   = Mojo::URL->new($uri);
  my $state = $self->param('state');
  $url->query->merge(%params, defined $state ? (state => $state) : ());
  $self->redirect_to($url);
}

sub _error ($self, $error) { $self->render(json => {error => $error}, status => 400) }

sub _issuer ($self) { $self->url_for('/')->to_abs->to_string =~ s!/$!!r }

sub _login ($self) {
  my %query = map { defined $self->param($_) ? ($_ => $self->param($_)) : () } @PARAMS;
  $self->session(return_to => $self->url_for('oauth_authorize')->query(%query)->to_string);
  $self->redirect_to('/login');
}

sub _loopback ($host) {
  !!grep { ($host =~ tr/[]//dr) eq $_ } qw(localhost 127.0.0.1 ::1);
}

# Loopback redirects may use any port (RFC 8252), since native clients like Claude Code pick a free one per login
sub _matches ($registered, $uri) {
  my $url = Mojo::URL->new($uri);
  return !!grep { $_ eq $uri } @$registered unless ($url->scheme // '') eq 'http' && _loopback($url->host // '');
  my $portless = $url->clone->port(undef)->to_string;
  return !!grep { Mojo::URL->new($_)->port(undef)->to_string eq $portless } @$registered;
}

sub _request ($self) {
  my $id  = $self->param('client_id')    // '';
  my $uri = $self->param('redirect_uri') // '';
  return {fatal => 'Unknown OAuth client'} unless (my $client = $self->api_keys->find_client($id));
  return {fatal => 'Invalid redirect URI'} unless _matches($client->{redirect_uris}, $uri);

  my $error;
  $error = 'unsupported_response_type' unless ($self->param('response_type') // '') eq 'code';
  $error //= 'invalid_request'
    unless ($self->param('code_challenge') // '') =~ /^[\w-]{43}$/
    && ($self->param('code_challenge_method') // '') eq 'S256';
  my $resource = $self->param('resource');
  $error //= 'invalid_target' if defined $resource && $resource =~ s!/$!!r ne $self->_resource;

  return {client => $client, uri => $uri, error => $error};
}

sub _resource ($self) { $self->url_for('mcp')->to_abs->to_string }

1;
