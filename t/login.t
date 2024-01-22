# Copyright (C) 2018-2020 SUSE LLC
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

subtest 'Not authenticated' => sub {
  $t->post_ok('/reviews/review_package/1')->status_is(403)->content_like(qr/Permission/);
  $t->post_ok('/reviews/fasttrack_package/1')->status_is(403)->content_like(qr/Permission/);
  $t->post_ok('/reviews/add_ignore')->status_is(403)->content_like(qr/Permission/);
  $t->post_ok('/reviews/reindex/1')->status_is(403)->content_like(qr/Permission/);
  $t->get_ok('/reviews/file_view/1/LICENSE')->status_is(403)->content_like(qr/Permission/);
  $t->get_ok('/licenses/new_pattern')->status_is(403)->content_like(qr/Permission/);
  $t->post_ok('/licenses/create_pattern')->status_is(403)->content_like(qr/Permission/);
  $t->get_ok('/licenses/edit_pattern/1')->status_is(403)->content_like(qr/Permission/);
  $t->post_ok('/licenses/update_pattern/1')->status_is(403)->content_like(qr/Permission/);
  $t->post_ok('/licenses/update_patterns')->status_is(403)->content_like(qr/Permission/);
  $t->delete_ok('/licenses/remove_pattern/1')->status_is(403)->content_like(qr/Permission/);
};

subtest 'OpenID' => sub {
  $t->get_ok('/login')->status_is(302)->header_is(Location => '/oidc/callback');
};

subtest 'Dummy' => sub {
  delete $config->{openid};
  $t = Test::Mojo->new(Cavil => $config);
  $t->get_ok('/upload')->status_is(403)->content_like(qr/Permission/);
  $t->get_ok('/login')->status_is(302)->header_is(Location => '/');
  $t->get_ok('/upload')->status_is(200)->content_like(qr/Upload/);
  $t->get_ok('/logout')->status_is(302)->header_is(Location => '/');
  $t->get_ok('/upload')->status_is(403)->content_like(qr/Permission/);
};

done_testing;
