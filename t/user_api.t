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

use Mojo::Base -strict;

use FindBin;
use lib "$FindBin::Bin/lib";

use Test::More;
use Test::Mojo;
use Cavil::Test;
use Mojo::Date;

plan skip_all => 'set TEST_ONLINE to enable this test' unless $ENV{TEST_ONLINE};

my $cavil_test = Cavil::Test->new(online => $ENV{TEST_ONLINE}, schema => 'user_api_test');
my $t          = Test::Mojo->new(Cavil => $cavil_test->default_config);
$cavil_test->mojo_fixtures($t->app);

subtest 'API keys' => sub {
  my $key           = '';
  my $expires_epoch = time + 36000;
  my $expires       = Mojo::Date->new($expires_epoch)->to_datetime =~ s/:\d{2}Z$//r;

  subtest 'Create API key' => sub {
    $t->get_ok('/login')->status_is(302)->header_is(Location => '/');

    $t->post_ok('/api_keys' => form => {expires => $expires, description => 'Test key'})
      ->status_is(200)
      ->json_is('/created' => 1);
    $t->get_ok('/api_keys/meta')
      ->status_is(200)
      ->json_is('/keys/0/id'    => 1)
      ->json_is('/keys/0/owner' => 2)
      ->json_like('/keys/0/api_key' => qr/^[a-f0-9\-]{20,}$/i)
      ->json_is('/keys/0/description' => 'Test key')
      ->json_has('/keys/0/expires_epoch');
    $key = $t->tx->res->json('/keys/0/api_key');

    $t->get_ok('/logout')->status_is(302)->header_is(Location => '/');
  };

  subtest 'Access API with key' => sub {
    $t->get_ok('/api/v1/whoami')
      ->status_is(403)
      ->json_is('/error' => 'It appears you have insufficient permissions for accessing this resource');

    $t->get_ok('/api/v1/whoami' => {Authorization => "Bearer $key"})
      ->status_is(200)
      ->json_is('/id', 2)
      ->json_is('/user' => 'tester');
  };

  subtest 'API keys from multiple users' => sub {
    my $key = $t->app->api_keys->create(owner => 1, description => 'Other user key', expires => $expires);

    $t->get_ok('/login')->status_is(302)->header_is(Location => '/');
    $t->get_ok('/api_keys/meta')
      ->status_is(200)
      ->json_is('/keys/0/id'    => 1)
      ->json_is('/keys/0/owner' => 2)
      ->json_hasnt('/keys/1');
    $t->get_ok('/logout')->status_is(302)->header_is(Location => '/');

    $t->get_ok('/api/v1/whoami' => {Authorization => "Bearer $key->{api_key}"})
      ->status_is(200)
      ->json_is('/id', 1)
      ->json_is('/user' => 'test_bot');
  };

  subtest 'Expired API key' => sub {
    $t->app->pg->db->query("UPDATE api_keys SET expires = NOW() - INTERVAL '1 hour' WHERE api_key = ?", $key);
    $t->get_ok('/api/v1/whoami' => {Authorization => "Bearer $key"})
      ->status_is(403)
      ->json_is('/error' => 'It appears you have insufficient permissions for accessing this resource');

    $t->app->pg->db->query("UPDATE api_keys SET expires = NOW() + INTERVAL '10 hours' WHERE api_key = ?", $key);
    $t->get_ok('/api/v1/whoami' => {Authorization => "Bearer $key"})
      ->status_is(200)
      ->json_is('/id', 2)
      ->json_is('/user' => 'tester');
  };

  subtest 'Remove API key' => sub {
    $t->get_ok('/login')->status_is(302)->header_is(Location => '/');

    $t->delete_ok('/api_keys/1')->status_is(200)->json_is('/removed' => 1);
    $t->get_ok('/api/v1/whoami' => {Authorization => "Bearer $key"})
      ->status_is(403)
      ->json_is('/error' => 'It appears you have insufficient permissions for accessing this resource');

    $t->get_ok('/logout')->status_is(302)->header_is(Location => '/');
  };

  subtest 'Removing another users keys is not allowed' => sub {
    $t->get_ok('/login')->status_is(302)->header_is(Location => '/');
    $t->delete_ok('/api_keys/2')->status_is(200)->json_is('/removed' => 0);
    $t->get_ok('/logout')->status_is(302)->header_is(Location => '/');
  }
};

done_testing;
