# Copyright (C) 2024 SUSE LLC
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

my $cavil_test = Cavil::Test->new(online => $ENV{TEST_ONLINE}, schema => 'proposal_test');
my $t          = Test::Mojo->new(Cavil => $cavil_test->default_config);
$cavil_test->package_with_snippets_fixtures($t->app);

my $db = $t->app->pg->db;

subtest 'Snippet metadata' => sub {
  my $unpack_id = $t->app->minion->enqueue(unpack => [1]);
  $t->app->minion->perform_jobs;
  $t->get_ok('/snippet/meta/1')->status_is(200)->json_is('/snippet/sline', 1)
    ->json_like('/snippet/text', qr/The license might be/)->json_is('/snippet/package/id', 1)
    ->json_is('/snippet/package/name', 'package-with-snippets')->json_is('/snippet/keywords', {0 => 1});
  $t->get_ok('/snippet/meta/2')->status_is(200)->json_is('/snippet/sline', 29)
    ->json_like('/snippet/text', qr/The GPL might be/)->json_is('/snippet/package/id', 1)
    ->json_is('/snippet/package/name', 'package-with-snippets');
};

subtest 'Pattern creation' => sub {
  subtest 'Permission errors' => sub {
    $t->get_ok('/login')->status_is(302)->header_is(Location => '/');
    $t->app->users->remove_role(2, 'admin');
    $t->get_ok('/logout')->status_is(302)->header_is(Location => '/');
    $t->post_ok('/snippet/decision/1' => form => {'create-pattern'   => 1})->status_is(403);
    $t->post_ok('/snippet/decision/1' => form => {'propose-pattern'  => 1})->status_is(403);
    $t->post_ok('/snippet/decision/1' => form => {'mark-non-license' => 1})->status_is(403);

    $t->get_ok('/login')->status_is(302)->header_is(Location => '/');
    $t->post_ok('/snippet/decision/1' => form =>
        {'create-pattern' => 1, license => 'Test', pattern => 'This is a license', risk => 5})->status_is(403);
    $t->post_ok('/snippet/decision/1' => form =>
        {'propose-pattern' => 1, license => 'Test', pattern => 'This is a license', risk => 5})->status_is(403);
    $t->post_ok('/snippet/decision/1' => form => {'mark-non-license' => 1})->status_is(403);

    $t->app->users->add_role(2, 'contributor');
    $t->post_ok('/snippet/decision/1' => form =>
        {'create-pattern' => 1, license => 'Test', pattern => 'This is a license', risk => 5})->status_is(403);
  };

  subtest 'Pattern mismatch' => sub {
    $t->post_ok('/snippet/decision/1' => form =>
        {'propose-pattern' => 1, license => 'Test', pattern => 'This is a license', risk => 5})->status_is(400)
      ->content_like(qr/License pattern does not match the original snippet/);
  };

  subtest 'Bad license and risk combinations' => sub {
    $t->post_ok('/snippet/decision/1' => form =>
        {'propose-pattern' => 1, license => 'Test', pattern => 'The license might', risk => 5})->status_is(400)
      ->content_like(qr/This license and risk combination is not allowed, only use pre-existing licenses/);
  };

  subtest 'From proposal to pattern' => sub {
    $t->post_ok('/snippet/decision/1' => form =>
        {'propose-pattern' => 1, license => 'GPL', pattern => 'The license might', risk => 5})->status_is(200)
      ->content_like(qr/Your change has been proposed/);
    $t->post_ok('/snippet/decision/1' => form =>
        {'propose-pattern' => 1, license => 'GPL', pattern => 'The license might', risk => 5})->status_is(409)
      ->content_like(qr/Conflicting license pattern proposal already exists/);
    $t->post_ok('/snippet/decision/1' => form =>
        {'create-pattern' => 1, license => 'GPL', pattern => 'The license might', risk => 5})->status_is(403);

    $t->get_ok('/licenses/proposed/meta')->status_is(200)->json_has('/changes/0')->json_hasnt('/changes/1');
    my $checksum = $t->tx->res->json->{changes}[0]{token_hexsum};
    $t->app->users->add_role(2, 'admin');
    $t->post_ok('/snippet/decision/1' => form =>
        {'create-pattern' => 1, license => 'GPL', pattern => 'The license might', risk => 5, checksum => $checksum})
      ->status_is(200)->content_like(qr/has been created/);
    $t->get_ok('/licenses/proposed/meta')->status_is(200)->json_hasnt('/changes/0');

    $t->post_ok('/snippet/decision/1' => form =>
        {'create-pattern' => 1, license => 'GPL', pattern => 'The license might', risk => 5})->status_is(409)
      ->content_like(qr/Conflicting license pattern already exists/);
  };
};

subtest 'Cancelled proposal' => sub {
  $t->app->users->remove_role(2, 'admin');
  $t->post_ok("/licenses/proposed/remove/123")->status_is(403);

  $t->post_ok(
    '/snippet/decision/2' => form => {'propose-pattern' => 1, license => 'GPL', pattern => 'The GPL', risk => 5})
    ->status_is(200)->content_like(qr/Your change has been proposed/);
  $t->get_ok('/licenses/proposed/meta')->status_is(200)->json_has('/changes/0')->json_hasnt('/changes/1');
  my $checksum = $t->tx->res->json->{changes}[0]{token_hexsum};
  $t->post_ok("/licenses/proposed/remove/$checksum")->status_is(200)->json_is('/removed', 1);

  $t->app->users->add_role(2, 'admin');
  $t->post_ok("/licenses/proposed/remove/123")->status_is(200)->json_is('/removed', 0);
};

done_testing();
