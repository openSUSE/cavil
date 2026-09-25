# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Mojo::Base -strict, -signatures;

use FindBin;
use lib "$FindBin::Bin/lib";

use Test::More;
use Test::Mojo;
use Cavil::Test;
use Digest::SHA  qw(sha256);
use MIME::Base64 qw(encode_base64url);
use Mojo::URL;
use MCP::Client;

plan skip_all => 'set TEST_ONLINE to enable this test' unless $ENV{TEST_ONLINE};

my $cavil_test = Cavil::Test->new(online => $ENV{TEST_ONLINE}, schema => 'oauth_test');
my $config     = $cavil_test->default_config;
$config->{oauth_redirect_hosts} = ['*.harvey.ai', 'localhost', '::1'];
my $t = Test::Mojo->new(Cavil => $config);
$cavil_test->no_fixtures($t->app);

my $base      = $t->ua->server->url->path('')->to_string =~ s!/$!!r;
my $verifier  = 'a' x 43;
my $challenge = encode_base64url(sha256($verifier));

sub authorize_query ($client_id, %params) {
  return {
    client_id             => $client_id,
    redirect_uri          => 'http://localhost:4567/callback',
    response_type         => 'code',
    code_challenge        => $challenge,
    code_challenge_method => 'S256',
    state                 => 'xyz',
    resource              => "$base/mcp",
    %params
  };
}

sub consent ($client_id, %params) {
  $t->get_ok('/oauth/authorize' => form => authorize_query($client_id))->status_is(200);
  my $csrf = $t->tx->res->dom->at('input[name=csrf_token]')->val;
  $t->post_ok('/oauth/authorize' => form => {%{authorize_query($client_id)}, csrf_token => $csrf, %params})
    ->status_is(302);
  return Mojo::URL->new($t->tx->res->headers->location);
}

my $client_id;

subtest 'Discovery' => sub {
  $t->get_ok('/mcp')
    ->status_is(401)
    ->header_is('WWW-Authenticate' => qq{Bearer resource_metadata="$base/.well-known/oauth-protected-resource"});
  $t->get_ok('/api/v1/whoami')->status_is(401);
  $t->get_ok('/api/v1/whoami' => {Authorization => 'Bearer invalid-token'})->status_is(401);

  $t->get_ok('/.well-known/oauth-protected-resource')
    ->status_is(200)
    ->json_is('/resource'                => "$base/mcp")
    ->json_is('/authorization_servers/0' => $base);
  $t->get_ok('/.well-known/oauth-protected-resource/mcp')->status_is(200)->json_is('/resource' => "$base/mcp");

  $t->get_ok('/.well-known/oauth-authorization-server')
    ->status_is(200)
    ->json_is('/issuer'                             => $base)
    ->json_is('/authorization_endpoint'             => "$base/oauth/authorize")
    ->json_is('/token_endpoint'                     => "$base/oauth/token")
    ->json_is('/registration_endpoint'              => "$base/oauth/register")
    ->json_is('/code_challenge_methods_supported/0' => 'S256');
};

subtest 'Dynamic client registration' => sub {
  $t->post_ok('/oauth/register' => json => {client_name => 'Evil', redirect_uris => ['https://evil.example/cb']})
    ->status_is(400)
    ->json_is('/error' => 'invalid_redirect_uri');
  $t->post_ok('/oauth/register' => json => {redirect_uris => ['http://app.harvey.ai/cb']})
    ->status_is(400)
    ->json_is('/error' => 'invalid_redirect_uri');
  $t->post_ok('/oauth/register' => json => {redirect_uris => ['http://127.0.0.1:1234/cb']})
    ->status_is(400)
    ->json_is('/error' => 'invalid_redirect_uri');
  $t->post_ok('/oauth/register' => json => {redirect_uris => ['http://[::1]:1234/cb']})->status_is(201);
  $t->post_ok('/oauth/register' => json => {redirect_uris => []})->status_is(400);
  $t->post_ok('/oauth/register' => json => [])->status_is(400)->json_is('/error' => 'invalid_client_metadata');

  $t->post_ok('/oauth/register' => json =>
      {client_name => 'Claude Code', redirect_uris => ['http://localhost:1234/callback', 'https://app.harvey.ai/cb']})
    ->status_is(201)
    ->json_is('/client_name'                => 'Claude Code')
    ->json_is('/token_endpoint_auth_method' => 'none');
  $client_id = $t->tx->res->json('/client_id');
  like $client_id, qr/^[0-9a-f-]{36}$/, 'client id';
};

subtest 'Invalid authorization requests' => sub {
  $t->get_ok('/oauth/authorize' => form => authorize_query('nope'))->status_is(400)->content_is('Unknown OAuth client');
  $t->get_ok('/oauth/authorize' => form => authorize_query($client_id, redirect_uri => 'https://evil.example/cb'))
    ->status_is(400)
    ->content_is('Invalid redirect URI');

  $t->get_ok('/oauth/authorize' => form => authorize_query($client_id, code_challenge_method => 'plain'))
    ->status_is(302);
  my $url = Mojo::URL->new($t->tx->res->headers->location);
  is $url->query->param('error'), 'invalid_request', 'PKCE required';
  is $url->query->param('state'), 'xyz',             'state preserved';

  $t->get_ok('/oauth/authorize' => form => authorize_query($client_id, resource => 'https://other.example/mcp'))
    ->status_is(302);
  is(Mojo::URL->new($t->tx->res->headers->location)->query->param('error'), 'invalid_target', 'wrong resource');
};

subtest 'Consent without login' => sub {
  $t->get_ok('/')->status_is(200);
  my $csrf = $t->tx->res->dom->at('meta[name=csrf-token]')->attr('content');
  $t->post_ok('/oauth/authorize' => form => {%{authorize_query($client_id)}, csrf_token => $csrf, allow => 1})
    ->status_is(302)
    ->header_is(Location => '/login');
  $t->get_ok('/login')->status_is(302)->header_like(Location => qr!^/oauth/authorize\?.*client_id=$client_id!);
  $t->get_ok($t->tx->res->headers->location)->status_is(200)->text_like('h4' => qr/Authorize Claude Code/);
  $t->get_ok('/logout')->status_is(302);
};

my $token;

subtest 'Login, consent and token exchange' => sub {
  $t->get_ok('/oauth/authorize' => form => authorize_query($client_id))
    ->status_is(302)
    ->header_is(Location => '/login');
  $t->get_ok('/login')->status_is(302)->header_like(Location => qr!^/oauth/authorize\?!);
  $t->get_ok($t->tx->res->headers->location)
    ->status_is(200)
    ->text_like('h4' => qr/Authorize Claude Code/)
    ->content_like(qr/localhost/);

  $t->post_ok('/oauth/authorize' => form => {%{authorize_query($client_id)}, allow => 1})
    ->status_is(403)
    ->content_is('Bad CSRF token');

  my $denied = consent($client_id, deny => 1);
  is $denied->query->param('error'), 'access_denied', 'denied';

  my $url  = consent($client_id, allow => 1);
  my $code = $url->query->param('code');
  is $url->host,                  'localhost', 'loopback redirect with any port';
  is $url->query->param('state'), 'xyz',       'state';
  is $url->query->param('iss'),   $base,       'issuer';
  like $code, qr/^[0-9a-f-]{36}$/, 'code';

  my %exchange = (
    grant_type    => 'authorization_code',
    code          => $code,
    client_id     => $client_id,
    redirect_uri  => 'http://localhost:4567/callback',
    code_verifier => $verifier
  );
  $t->post_ok('/oauth/token' => form => {%exchange, code_verifier => 'b' x 43})
    ->status_is(400)
    ->json_is('/error' => 'invalid_grant');
  $t->post_ok('/oauth/token' => form => \%exchange)->status_is(400)->json_is('/error' => 'invalid_grant');

  $code = consent($client_id, allow => 1)->query->param('code');
  $t->post_ok('/oauth/token' => form => {%exchange, code => $code, redirect_uri => 'http://localhost:9999/callback'})
    ->status_is(400);

  $code = consent($client_id, allow => 1)->query->param('code');
  $t->post_ok('/oauth/token' => form => {%exchange, code => $code})
    ->status_is(200)
    ->header_is('Cache-Control' => 'no-store')
    ->json_is('/token_type' => 'Bearer')
    ->json_is('/scope'      => 'cavil:read');
  $token = $t->tx->res->json('/access_token');
  $t->post_ok('/oauth/token' => form => {%exchange, code => $code})
    ->status_is(400)
    ->json_is('/error' => 'invalid_grant');

  $t->post_ok('/oauth/token' => form => {grant_type => 'password'})
    ->status_is(400)
    ->json_is('/error' => 'unsupported_grant_type');

  $code = consent($client_id, allow => 1, write_access => 1)->query->param('code');
  $t->post_ok('/oauth/token' => form => {%exchange, code => $code})
    ->status_is(200)
    ->json_is('/scope' => 'cavil:read cavil:write');
};

subtest 'Expired code' => sub {
  my $code = consent($client_id, allow => 1)->query->param('code');
  $t->app->pg->db->query(q{UPDATE oauth_codes SET expires = NOW() - INTERVAL '1 second'});
  $t->post_ok(
    '/oauth/token' => form => {
      grant_type    => 'authorization_code',
      code          => $code,
      client_id     => $client_id,
      redirect_uri  => 'http://localhost:4567/callback',
      code_verifier => $verifier
    }
  )->status_is(400)->json_is('/error' => 'invalid_grant');
};

subtest 'Use token and revoke it' => sub {
  $t->get_ok('/api/v1/whoami' => {Authorization => "Bearer $token"})
    ->status_is(200)
    ->json_is('/user'         => 'tester')
    ->json_is('/write_access' => Mojo::JSON::false);

  my $mcp = Test::Mojo->new($t->app);
  $mcp->ua->on(start => sub ($ua, $tx) { $tx->req->headers->authorization("Bearer $token") });
  my $client = MCP::Client->new(ua => $mcp->ua, url => $mcp->ua->server->url->path('/mcp'));
  ok scalar @{$client->list_tools->{tools}}, 'MCP tools available';

  $t->get_ok('/api_keys/meta')->status_is(200)->json_is('/keys/0/description' => 'Claude Code (OAuth)');
  $t->delete_ok('/api_keys/' . $_->{id})->status_is(200) for @{$t->tx->res->json('/keys')};
  $t->get_ok('/api/v1/whoami' => {Authorization => "Bearer $token"})->status_is(401);
};

done_testing;
