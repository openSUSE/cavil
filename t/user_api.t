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
use Mojo::File qw(path);
use Mojo::Date;
use Mojo::JSON qw(true false);

plan skip_all => 'set TEST_ONLINE to enable this test' unless $ENV{TEST_ONLINE};

my $cavil_test = Cavil::Test->new(online => $ENV{TEST_ONLINE}, schema => 'user_api_test');
my $t          = Test::Mojo->new(Cavil => $cavil_test->default_config);
$cavil_test->mojo_fixtures($t->app);

# Add patterns for known incompatible licenses
$t->app->patterns->create(pattern => 'SPDX-License-Identifier: Apache-2.0',   license => 'Apache-2.0');
$t->app->patterns->create(pattern => 'SPDX-License-Identifier: GPL-2.0-only', license => 'GPL-2.0-only');
$t->app->pg->db->query('UPDATE license_patterns SET spdx = $1 WHERE license = $1', $_) for qw(Apache-2.0 GPL-2.0-only);

# Add files with incompatible licenses
my $pkg = $t->app->packages->find(1);
my $dir = path($cavil_test->checkout_dir, $pkg->{name}, $pkg->{checkout_dir});
$dir->child('apache_file.txt')->spurt("# SPDX-License-Identifier: Apache-2.0\n\nThis is a test file.\n");
$dir->child('gpl2_file.txt')->spurt("# SPDX-License-Identifier: GPL-2.0-only\n\nThis is another test file.\n");

# Unpack and index
$t->app->minion->enqueue(unpack => [1]);
$t->app->minion->perform_jobs;

subtest 'API keys' => sub {
  my $key           = '';
  my $expires_epoch = time + 36000;
  my $expires       = Mojo::Date->new($expires_epoch)->to_datetime =~ s/:\d{2}Z$//r;

  subtest 'Create API key' => sub {
    $t->get_ok('/login')->status_is(302)->header_is(Location => '/');

    $t->post_ok('/api_keys' => form => {expires => $expires, type => 'read-only', description => 'Test key'})
      ->status_is(200)
      ->json_is('/created' => 1);
    $t->get_ok('/api_keys/meta')
      ->status_is(200)
      ->json_is('/keys/0/id'    => 1)
      ->json_is('/keys/0/owner' => 2)
      ->json_like('/keys/0/api_key' => qr/^[a-f0-9\-]{20,}$/i)
      ->json_is('/keys/0/description'  => 'Test key')
      ->json_is('/keys/0/write_access' => 0)
      ->json_has('/keys/0/expires_epoch');
    $key = $t->tx->res->json('/keys/0/api_key');

    $t->get_ok('/logout')->status_is(302)->header_is(Location => '/');
  };

  subtest 'Access API without key' => sub {
    $t->get_ok('/api/v1/whoami')
      ->status_is(403)
      ->json_is('/error' => 'It appears you have insufficient permissions for accessing this resource');
    $t->get_ok('/api/v1/report/1.json')
      ->status_is(403)
      ->json_is('/error' => 'It appears you have insufficient permissions for accessing this resource');
    $t->get_ok('/api/v1/report/1.txt')
      ->status_is(403)
      ->json_is('/error' => 'It appears you have insufficient permissions for accessing this resource');
    $t->get_ok('/api/v1/report/1.mcp')
      ->status_is(403)
      ->json_is('/error' => 'It appears you have insufficient permissions for accessing this resource');
  };

  subtest 'Access API with key' => sub {
    $t->get_ok('/api/v1/whoami' => {Authorization => "Bearer $key"})
      ->status_is(200)
      ->json_is('/id', 2)
      ->json_is('/user'         => 'tester')
      ->json_is('/roles'        => ['admin', 'classifier', 'manager'])
      ->json_is('/write_access' => false);
  };

  subtest 'Access reports with API key' => sub {
    $t->get_ok('/api/v1/report/1.json' => {Authorization => "Bearer $key"})
      ->status_is(200)
      ->json_is('/package/id'                      => 1)
      ->json_is('/package/checkout_dir'            => 'c7cfdab0e71b0bebfdf8b2dc3badfecd')
      ->json_is('/report/licenses/Apache-2.0/spdx' => 'Apache-2.0');

    $t->get_ok('/api/v1/report/1.txt' => {Authorization => "Bearer $key"})
      ->status_is(200)
      ->content_like(qr/Package:.+perl-Mojolicious/)
      ->content_like(qr/Checkout:.+c7cfdab0e71b0bebfdf8b2dc3badfecd/)
      ->content_like(qr/Unpacked:.+files/)
      ->content_like(qr/Apache-2.0:.+3 files/);

    $t->get_ok('/api/v1/report/1.mcp' => {Authorization => "Bearer $key"})
      ->status_is(200)
      ->content_like(qr/Package:.+perl-Mojolicious/)
      ->content_like(qr/Checkout:.+c7cfdab0e71b0bebfdf8b2dc3badfecd/)
      ->content_like(qr/Apache-2.0:.+3 files/)
      ->content_like(qr/LICENSE.+Snippet: 2.+Hash: 3c/);
  };

  subtest 'API keys from multiple users' => sub {
    my $key = $t->app->api_keys->create(owner => 1, description => 'Other user key', type => 'read-write',
      expires => $expires);

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
      ->json_is('/user'         => 'test_bot')
      ->json_is('/roles'        => ['user'])
      ->json_is('/write_access' => true);
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
