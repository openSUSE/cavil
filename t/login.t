# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Mojo::Base -strict, -signatures;

use FindBin;
use lib "$FindBin::Bin/lib";

use Test::More;
use Test::Mojo;
use Mojo::JSON;
use Mojo::Server::Daemon;
use Mojo::URL;
use Mojolicious;
use Cavil::Test;

plan skip_all => 'set TEST_ONLINE to enable this test' unless $ENV{TEST_ONLINE};

my $cavil_test = Cavil::Test->new(online => $ENV{TEST_ONLINE}, schema => 'login_test');
my $config     = $cavil_test->default_config;
$config->{openid} = {
  key            => 'APP_NAME',
  secret         => 'APP_SECRET',
  well_known_url => 'https://id.opensuse.org/openidc/.well-known/openid-configuration'
};
my $t = Test::Mojo->new(Cavil => $config);
$cavil_test->no_fixtures($t->app);

subtest 'Unknown resource' => sub {
  $t->get_ok('/does_not_exist')->status_is(404)->content_like(qr/The requested resource does not exist/);
};

subtest 'Public (main menu)' => sub {
  $t->get_ok('/')->status_is(200);
  $t->get_ok('/reviews/recent')->status_is(200);
  $t->get_ok('/licenses')->status_is(200);
  $t->get_ok('/products')->status_is(200);
  $t->get_ok('/products/openSUSE:Factory')->status_is(200);
};

subtest 'Login required' => sub {
  $t->get_ok('/api_keys')->status_is(401)->content_like(qr/Login Required/);
  $t->get_ok('/settings')->status_is(401)->content_like(qr/Login Required/);
  $t->get_ok('/settings/api-keys')->status_is(401)->content_like(qr/Login Required/);
  $t->get_ok('/api_keys/meta')->status_is(401)->content_like(qr/Login Required/);
  $t->post_ok('/api_keys')->status_is(401)->content_like(qr/Login Required/);
  $t->delete_ok('/api_keys/1')->status_is(401)->content_like(qr/Login Required/);
  $t->get_ok('/reviews/details/1')->status_is(401)->content_like(qr/Login Required/);
  $t->get_ok('/reviews/meta/1')->status_is(401)->content_like(qr/Login Required/);
  $t->get_ok('/reviews/report/1')->status_is(401)->content_like(qr/Login Required/);
  $t->get_ok('/reviews/report_details/1')->status_is(401)->content_like(qr/Login Required/);
  $t->get_ok('/reviews/fetch_source/1')->status_is(401)->content_like(qr/Login Required/);
  $t->get_ok('/reviews/file_view/1/LICENSE')->status_is(401)->content_like(qr/Login Required/);
  $t->get_ok('/reviews/file_view_meta/1/LICENSE')->status_is(401)->content_like(qr/Login Required/);
  $t->get_ok('/reviews/file_raw/1/LICENSE')->status_is(401)->content_like(qr/Login Required/);
  $t->get_ok('/reviews/notes/recent')->status_is(401)->content_like(qr/Login Required/);
  $t->get_ok('/reviews/notes/recent.json')->status_is(401)->content_like(qr/Login Required/);
  $t->get_ok('/reviews/notes/tags')->status_is(401)->content_like(qr/Login Required/);
  $t->get_ok('/reviews/notes/tags.json')->status_is(401)->content_like(qr/Login Required/);
  $t->get_ok('/reviews/notes/1')->status_is(401)->content_like(qr/Login Required/);
  $t->post_ok('/reviews/notes/1')->status_is(401)->content_like(qr/Login Required/);
  $t->patch_ok('/reviews/notes/1')->status_is(401)->content_like(qr/Login Required/);
  $t->patch_ok('/reviews/notes/1/pin')->status_is(401)->content_like(qr/Login Required/);
  $t->delete_ok('/reviews/notes/1')->status_is(401)->content_like(qr/Login Required/);
  $t->post_ok('/reviews/notes/preview')->status_is(401)->content_like(qr/Login Required/);
  $t->get_ok('/snippets')->status_is(401)->content_like(qr/Login Required/);
  $t->get_ok('/snippets/meta')->status_is(401)->content_like(qr/Login Required/);
  $t->get_ok('/snippet/edit/1')->status_is(401)->content_like(qr/Login Required/);
  $t->get_ok('/snippet/meta/1')->status_is(401)->content_like(qr/Login Required/);
  $t->get_ok('/licenses/autocomplete.json')->status_is(401)->content_like(qr/Login Required/);
  $t->get_ok('/licenses/pattern/1.json')->status_is(401)->content_like(qr/Login Required/);
  $t->get_ok('/licenses/pattern/1/match_count.json')->status_is(401)->content_like(qr/Login Required/);
  $t->get_ok('/licenses/missing')->status_is(401)->content_like(qr/Login Required/);
  $t->get_ok('/licenses/proposed')->status_is(401)->content_like(qr/Login Required/);
  $t->get_ok('/licenses/proposed/meta')->status_is(401)->content_like(qr/Login Required/);
  $t->get_ok('/licenses/recent')->status_is(401)->content_like(qr/Login Required/);
  $t->get_ok('/licenses/recent/meta')->status_is(401)->content_like(qr/Login Required/);
  $t->get_ok('/documents/1/spdx')->status_is(401)->content_like(qr/Login Required/);
  $t->get_ok('/stats')->status_is(401)->content_like(qr/Login Required/);
  $t->get_ok('/stats/meta')->status_is(401)->content_like(qr/Login Required/);
};

subtest 'Not authenticated' => sub {
  $t->post_ok('/reviews/review_package/1')->status_is(403)->content_like(qr/Permission/);
  $t->post_ok('/reviews/fasttrack_package/1')->status_is(403)->content_like(qr/Permission/);
  $t->post_ok('/ignored-files')->status_is(403)->content_like(qr/Permission/);
  $t->post_ok('/reviews/reindex/1')->status_is(403)->content_like(qr/Permission/);
  $t->get_ok('/licenses/new_pattern')->status_is(403)->content_like(qr/Permission/);
  $t->post_ok('/licenses/create_pattern')->status_is(403)->content_like(qr/Permission/);
  $t->get_ok('/licenses/edit_pattern/1')->status_is(403)->content_like(qr/Permission/);
  $t->post_ok('/licenses/pattern/1.json')->status_is(403)->content_like(qr/Permission/);
  $t->post_ok('/licenses/update_pattern/1')->status_is(403)->content_like(qr/Permission/);
  $t->post_ok('/licenses/meta/Apache-2.0')->status_is(403)->content_like(qr/Permission/);
  $t->post_ok('/licenses/update_patterns')->status_is(403)->content_like(qr/Permission/);
  $t->delete_ok('/licenses/remove_pattern/1')->status_is(403)->content_like(qr/Permission/);
  $t->get_ok('/snippets/from_file/1/1/2')->status_is(403)->content_like(qr/Permission/);
  $t->get_ok('/snippets/from_path/1/LICENSE?start=1&end=2')->status_is(403)->content_like(qr/Permission/);
  $t->get_ok('/upload')->status_is(403)->content_like(qr/Permission/);
  $t->put_ok('/products/openSUSE:Factory/annotation' => form => {product => 'Tumbleweed'})
    ->status_is(403)
    ->content_like(qr/Permission/);
};

subtest 'OpenID' => sub {
  $t->get_ok('/login')->status_is(302)->header_is(Location => '/oidc/callback');
};

subtest 'OpenID Connect claims' => sub {
  my $claims   = {};
  my $provider = Mojolicious->new;
  $provider->routes->post('/token' => {json => {access_token => 'secret_token'}});
  $provider->routes->get(
    '/userinfo' => sub ($c) {
      return $c->render(json => {}, status => 401) unless $c->req->headers->authorization eq 'Bearer secret_token';
      $c->render(json => $claims);
    }
  );
  my $daemon = Mojo::Server::Daemon->new(app => $provider, listen => ['http://127.0.0.1'], silent => 1)->start;
  my $url    = Mojo::URL->new('http://127.0.0.1')->port($daemon->ports->[0]);
  my $config = $t->app->oauth2->providers->{opensuse};
  $config->{token_url}    = $url->clone->path('/token')->to_string;
  $config->{userinfo_url} = $url->clone->path('/userinfo')->to_string;
  my $users = $t->app->users;

  my $login = sub ($expected) {
    $t->get_ok('/oidc/callback?code=42')->status_is(302)->header_is(Location => '/');
    $t->get_ok('/settings/api-keys')->status_is(200);
    ok $users->find(login => $expected), "user $expected created";
    $t->get_ok('/logout')->status_is(302);
  };
  my $refuse = sub {
    $t->get_ok('/oidc/callback?code=42')->status_is(403)->content_like(qr/did not supply a username or verified email/);
    $t->get_ok('/settings')->status_is(401);
  };

  $claims = {nickname => 'nick', preferred_username => 'preferred', email => 'nick@example.com'};
  $login->('nick');
  ok !$users->find(login => 'preferred'), 'nickname wins';

  $claims = {preferred_username => 'keycloak', email => 'keycloak@example.com'};
  $login->('keycloak');
  is $users->find(login => 'keycloak')->{email}, 'keycloak@example.com', 'email stored';

  $claims = {nickname => '', email => 'google@example.com', email_verified => Mojo::JSON->true};
  $login->('google@example.com');

  $claims = {email => 'entra@example.com'};
  $login->('entra@example.com');

  $claims = {email => 'unverified@example.com', email_verified => Mojo::JSON->false};
  $refuse->();
  $claims = {email => 'cognito@example.com', email_verified => 'false'};
  $refuse->();
  ok !$users->find(login => $_), 'no user created' for qw(unverified@example.com cognito@example.com);

  $claims = {sub => '1234'};
  $refuse->();
};

subtest 'Dummy' => sub {
  delete $config->{openid};
  $t = Test::Mojo->new(Cavil => $config);
  $t->get_ok('/upload')->status_is(403)->content_like(qr/Permission/);
  $t->put_ok('/products/openSUSE:Factory/annotation' => form => {product => 'Tumbleweed'})
    ->status_is(403)
    ->content_like(qr/Permission/);
  $t->get_ok('/login')->status_is(302)->header_is(Location => '/');
  $t->get_ok('/upload')->status_is(200)->content_like(qr/Upload/);
  $t->put_ok('/products/openSUSE:Factory/annotation' => form => {product => 'Tumbleweed'})
    ->status_is(200)
    ->json_is('/product', 'Tumbleweed');
  $t->put_ok('/products/openSUSE:Factory/annotation' => form => {product => 'Tumbleweed', priority => 7})
    ->status_is(200)
    ->json_is('/priority', 7);
  $t->put_ok('/products/openSUSE:Factory/annotation' => form => {product => 'Tumbleweed', priority => ''})
    ->status_is(200)
    ->json_is('/priority', undef);
  $t->put_ok('/products/openSUSE:Factory/annotation' => form => {priority => 11})->status_is(400);
  $t->put_ok('/products/openSUSE:Factory/annotation' => form => {priority => 'x'})->status_is(400);
  $t->get_ok('/logout')->status_is(302)->header_is(Location => '/');
  $t->get_ok('/upload')->status_is(403)->content_like(qr/Permission/);
  $t->put_ok('/products/openSUSE:Factory/annotation' => form => {product => 'Tumbleweed'})
    ->status_is(403)
    ->content_like(qr/Permission/);
};

done_testing;
