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
use Mojo::JSON qw(true false);

plan skip_all => 'set TEST_ONLINE to enable this test' unless $ENV{TEST_ONLINE};

my $cavil_test = Cavil::Test->new(online => $ENV{TEST_ONLINE}, schema => 'snippet_test');
my $t          = Test::Mojo->new(Cavil => $cavil_test->default_config);
$cavil_test->mojo_fixtures($t->app);

my $db = $t->app->pg->db;

subtest 'Snippet metadata' => sub {
  $t->get_ok('/snippets/meta?isClassified=false')->status_is(200)->json_hasnt('/0');
  my $id = $t->app->snippets->find_or_create('0000', 'Licenses are cool');
  $t->get_ok('/snippets/meta?isClassified=false')->status_is(200)->json_has('/0')->json_is('/0/classified', false)
    ->json_is('/0/approved', false);
};

subtest 'Snippet approval' => sub {
  $t->post_ok('/snippets/1' => form => {license => 'false'})->status_is(403);

  $t->get_ok('/login')->status_is(302)->header_is(Location => '/');
  $t->post_ok('/snippets/1' => form => {license => 'false'})->status_is(200);

  $t->get_ok('/snippets/meta?isClassified=false')->status_is(200)->json_hasnt('/0');

  my $res = $db->select('snippets', [qw(classified approved license)])->hash;
  is_deeply($res, {classified => 1, approved => 1, license => 0}, 'all fields updated');
};

done_testing();
