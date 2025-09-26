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
  $t->get_ok('/login')->status_is(302)->header_is(Location => '/');

  my $unpack_id = $t->app->minion->enqueue(unpack => [1]);
  $t->app->minion->perform_jobs;
  $t->get_ok('/snippet/meta/1')
    ->status_is(200)
    ->json_is('/snippet/sline', 1)
    ->json_like('/snippet/text', qr/The license might be\nsomething cool/)
    ->json_is('/snippet/package/id',   1)
    ->json_is('/snippet/package/name', 'package-with-snippets')
    ->json_is('/snippet/keywords',     {0 => 1});
  $t->get_ok('/snippet/meta/2')
    ->status_is(200)
    ->json_is('/snippet/sline', 29)
    ->json_like('/snippet/text', qr/The GPL might be/)
    ->json_is('/snippet/package/id',   1)
    ->json_is('/snippet/package/name', 'package-with-snippets');

  $t->get_ok('/logout')->status_is(302)->header_is(Location => '/');
};

subtest 'Pattern creation' => sub {
  subtest 'Permission errors' => sub {
    $t->get_ok('/login')->status_is(302)->header_is(Location => '/');
    $t->app->users->remove_role(2, 'admin');
    $t->get_ok('/logout')->status_is(302)->header_is(Location => '/');
    $t->post_ok('/snippet/decision/1' => form => {'create-pattern'   => 1})->status_is(403);
    $t->post_ok('/snippet/decision/1' => form => {'propose-pattern'  => 1})->status_is(403);
    $t->post_ok('/snippet/decision/1' => form => {'propose-ignore'   => 1})->status_is(403);
    $t->post_ok('/snippet/decision/1' => form => {'propose-missing'  => 1})->status_is(403);
    $t->post_ok('/snippet/decision/1' => form => {'mark-non-license' => 1})->status_is(403);

    $t->get_ok('/login')->status_is(302)->header_is(Location => '/');
    $t->post_ok('/snippet/decision/1' => form =>
        {'create-pattern' => 1, license => 'Test', pattern => 'This is a license', risk => 5})->status_is(403);
    $t->post_ok('/snippet/decision/1' => form =>
        {'propose-pattern' => 1, license => 'Test', pattern => 'This is a license', risk => 5})->status_is(403);
    $t->post_ok(
      '/snippet/decision/1' => form => {
        'propose-ignore' => 1,
        hash             => '39e8204ddebdc31a4d0e77aa647f4241',
        from             => 'perl-Mojolicious',
        pattern          => 'This is a license',
        edited           => 0
      }
    )->status_is(403);
    $t->post_ok('/snippet/decision/1' => form => {'mark-non-license' => 1, hash => '39e8204ddebdc31a4d0e77aa647f4241'})
      ->status_is(403);

    $t->app->users->add_role(2, 'contributor');
    $t->post_ok('/snippet/decision/1' => form =>
        {'create-pattern' => 1, license => 'Test', pattern => 'This is a license', risk => 5})->status_is(403);
  };

  subtest 'Pattern mismatch' => sub {
    $t->post_ok('/snippet/decision/1' => form =>
        {'propose-pattern' => 1, license => 'Test', pattern => 'This is a license', risk => 5})
      ->status_is(400)
      ->content_like(qr/License pattern does not match the original snippet/);
  };

  subtest 'Pattern with misplaced skip' => sub {
    $t->post_ok(
      '/snippet/decision/1' => form => {
        'propose-pattern' => 1,
        license           => 'Test',
        pattern           => "\$SKIP1 The license might be\nsomething cool",
        risk              => 5
      }
    )->status_is(400)->content_like(qr/License pattern contains redundant \$SKIP at beginning or end/);
    $t->post_ok(
      '/snippet/decision/1' => form => {
        'propose-pattern' => 1,
        license           => 'Test',
        pattern           => " \$SKIP1 The license might be\nsomething cool",
        risk              => 5
      }
    )->status_is(400)->content_like(qr/License pattern contains redundant \$SKIP at beginning or end/);

    $t->post_ok('/snippet/decision/1' => form =>
        {'propose-pattern' => 1, license => 'Test', pattern => "The license might be\nsomething \$SKIP11", risk => 5})
      ->status_is(400)
      ->content_like(qr/License pattern contains redundant \$SKIP at beginning or end/);
    $t->post_ok('/snippet/decision/1' => form =>
        {'propose-pattern' => 1, license => 'Test', pattern => "The license might be\nsomething \$SKIP11 ", risk => 5})
      ->status_is(400)
      ->content_like(qr/License pattern contains redundant \$SKIP at beginning or end/);
  };

  subtest 'Bad license and risk combinations' => sub {
    $t->post_ok('/snippet/decision/1' => form =>
        {'propose-pattern' => 1, license => 'Test', pattern => "The license might be\nsomething cool", risk => 5})
      ->status_is(400)
      ->content_like(qr/This license and risk combination is not allowed, only use pre-existing licenses/);
  };

  subtest 'Edited patterns cannot be ignored' => sub {
    $t->post_ok(
      '/snippet/decision/1' => form => {
        'propose-ignore' => 1,
        hash             => '39e8204ddebdc31a4d0e77aa647f4241',
        from             => 'perl-Mojolicious',
        pattern          => 'This is a license',
        edited           => 1
      }
    )->status_is(400)->content_like(qr/Only unedited snippets can be ignored/);
  };

  subtest 'Edited patterns cannot be flagged as missing license' => sub {
    $t->post_ok(
      '/snippet/decision/1' => form => {
        'propose-missing' => 1,
        hash              => '39e8204ddebdc31a4d0e77aa647f4241',
        from              => 'perl-Mojolicious',
        pattern           => 'This is a license',
        edited            => 1
      }
    )->status_is(400)->content_like(qr/Only unedited snippets can be reported as missing license/);
  };

  subtest 'From proposal to pattern' => sub {
    $t->post_ok(
      '/snippet/decision/1' => form => {
        'propose-pattern'      => 1,
        license                => 'GPL',
        pattern                => "The license might be\nsomething cool",
        'highlighted-keywords' => '0',
        'highlighted-licenses' => '1',
        edited                 => '1',
        risk                   => 5
      }
    )->status_is(200)->content_like(qr/Your change has been proposed/);
    $t->post_ok('/snippet/decision/1' => form =>
        {'propose-pattern' => 1, license => 'GPL', pattern => "The license might be\nsomething cool", risk => 5})
      ->status_is(409)
      ->content_like(qr/Conflicting license pattern proposal already exists/);
    $t->post_ok('/snippet/decision/1' => form =>
        {'create-pattern' => 1, license => 'GPL', pattern => "The license might be\nsomething cool", risk => 5})
      ->status_is(403);

    subtest 'Filtering' => sub {
      $t->get_ok('/licenses/proposed/meta?action=create_pattern&action=create_ignore&filter=license')
        ->status_is(200)
        ->json_has('/changes/0')
        ->json_is('/changes/0/action'       => 'create_pattern')
        ->json_is('/changes/0/data/license' => 'GPL')
        ->json_hasnt('/changes/1');
      $t->get_ok('/licenses/proposed/meta?action=create_pattern&action=create_ignore&filter=Apache')
        ->status_is(200)
        ->json_hasnt('/changes/0');
    };

    $t->get_ok('/licenses/proposed/meta?action=create_pattern&action=create_ignore')
      ->status_is(200)
      ->json_has('/changes/0')
      ->json_is('/changes/0/action'                    => 'create_pattern')
      ->json_is('/changes/0/data/license'              => 'GPL')
      ->json_is('/changes/0/data/pattern'              => "The license might be\nsomething cool")
      ->json_is('/changes/0/data/highlighted_keywords' => [0])
      ->json_is('/changes/0/data/highlighted_licenses' => [1])
      ->json_is('/changes/0/data/edited'               => 1)
      ->json_hasnt('/changes/1');
    my $checksum = $t->tx->res->json->{changes}[0]{token_hexsum};
    $t->app->users->add_role(2, 'admin');
    $t->post_ok(
      '/snippet/decision/1' => form => {
        'create-pattern' => 1,
        license          => 'GPL',
        pattern          => "The license might be\nsomething cool",
        risk             => 5,
        checksum         => $checksum,
        contributor      => 'tester'
      }
    )->status_is(200)->content_like(qr/has been created/);
    $t->get_ok('/licenses/proposed/meta?action=create_pattern&action=create_ignore')
      ->status_is(200)
      ->json_hasnt('/changes/0');

    $t->post_ok('/snippet/decision/1' => form =>
        {'create-pattern' => 1, license => 'GPL', pattern => "The license might be\nsomething cool", risk => 5})
      ->status_is(409)
      ->content_like(qr/Conflicting license pattern already exists/);
    $t->app->users->remove_role(2, 'admin');
  };

  subtest 'From proposal to ignore pattern' => sub {
    my $form = {
      'propose-ignore'       => 1,
      hash                   => '39e8204ddebdc31a4d0e77aa647f4241',
      from                   => 'perl-Mojolicious',
      pattern                => "This is\na license",
      edited                 => 0,
      'highlighted-keywords' => 1,
      'highlighted-licenses' => 0
    };
    $t->post_ok('/snippet/decision/1' => form => $form)
      ->status_is(200)
      ->content_like(qr/Your change has been proposed/);
    $t->post_ok('/snippet/decision/1' => form => $form)
      ->status_is(409)
      ->content_like(qr/Conflicting ignore pattern proposal already exists/);
    my $ignore_form = {
      'create-ignore' => 1,
      hash            => '39e8204ddebdc31a4d0e77aa647f4241',
      from            => 'perl-Mojolicious',
      contributor     => 'tester'
    };
    $t->post_ok('/snippet/decision/1' => form => $ignore_form)->status_is(403);

    $t->get_ok('/licenses/proposed/meta?action=create_pattern&action=create_ignore')
      ->status_is(200)
      ->json_has('/changes/0')
      ->json_is('/changes/0/action'                    => 'create_ignore')
      ->json_is('/changes/0/data/pattern'              => "This is\na license")
      ->json_is('/changes/0/data/highlighted_keywords' => [1])
      ->json_is('/changes/0/data/highlighted_licenses' => [0])
      ->json_is('/changes/0/data/edited'               => 0)
      ->json_hasnt('/changes/1');
    $t->app->users->add_role(2, 'admin');
    $t->post_ok('/snippet/decision/1' => form => $ignore_form)
      ->status_is(200)
      ->content_like(qr/ignore pattern has been created/);
    $t->get_ok('/licenses/proposed/meta?action=create_pattern&action=create_ignore')
      ->status_is(200)
      ->json_hasnt('/changes/0');

    $t->post_ok('/snippet/decision/1' => form => $form)
      ->status_is(409)
      ->content_like(qr/Conflicting ignore pattern already exists/);

    subtest 'Same checksum and a different package' => sub {
      $t->post_ok('/snippet/decision/1' => form => {%$form, from => 'perl-AnotherPackage'})
        ->status_is(200)
        ->content_like(qr/Your change has been proposed/);
      $t->post_ok('/snippet/decision/2' => form => {%$ignore_form, from => 'perl-AnotherPackage'})
        ->status_is(200)
        ->content_like(qr/ignore pattern has been created/);
    };

    my $ignore
      = $t->app->pg->db->query('SELECT * FROM ignored_lines WHERE hash = ?', '39e8204ddebdc31a4d0e77aa647f4241')->hash;
    is $ignore->{id},          1,                  'right id';
    is $ignore->{packname},    'perl-Mojolicious', 'right package';
    is $ignore->{owner},       2,                  'right owner';
    is $ignore->{contributor}, 2,                  'right contributor';
  };

  subtest 'Report missing license' => sub {
    my $form = {
      'propose-missing'      => 1,
      hash                   => '39e8204ddebdc31a4d0e77aa647f4241',
      from                   => 'perl-Mojolicious',
      pattern                => "This is\na license",
      edited                 => 0,
      'highlighted-keywords' => 1,
      'highlighted-licenses' => 0
    };
    $t->post_ok('/snippet/decision/1' => form => $form)
      ->status_is(200)
      ->content_like(qr/Missing license has been reported/);
    $t->post_ok('/snippet/decision/1' => form => $form)
      ->status_is(409)
      ->content_like(qr/Conflicting pattern proposal already exists/);

    $t->get_ok('/licenses/proposed/meta?action=missing_license')
      ->status_is(200)
      ->json_has('/changes/0')
      ->json_is('/changes/0/action'                    => 'missing_license')
      ->json_is('/changes/0/data/pattern'              => "This is\na license")
      ->json_is('/changes/0/data/highlighted_keywords' => [1])
      ->json_is('/changes/0/data/highlighted_licenses' => [0])
      ->json_is('/changes/0/data/edited'               => 0)
      ->json_hasnt('/changes/1');

    $t->post_ok(
      '/snippet/decision/1' => form => {
        'create-pattern' => 1,
        license          => 'MyCustomLicense',
        pattern          => "This is\na license",
        risk             => 5,
        checksum         => '39e8204ddebdc31a4d0e77aa647f4241',
        contributor      => 'tester'
      }
    )->status_is(200)->content_like(qr/has been created/);
    $t->get_ok('/licenses/proposed/meta?action=missing_license')->status_is(200)->json_hasnt('/changes/0');
  };

  subtest 'From proposal to not a license snippet' => sub {
    is $t->app->pg->db->query('SELECT * FROM snippets WHERE id = 3')->hash->{classified}, 0, 'not classified';
    my $form = {
      'propose-ignore'       => 1,
      hash                   => '399908965a4311ddd48a9440a66365e0',
      from                   => 'perl-Mojolicious',
      pattern                => "Now complex: The license might",
      edited                 => 0,
      'highlighted-keywords' => 1,
      'highlighted-licenses' => 0
    };
    $t->post_ok('/snippet/decision/1' => form => $form)
      ->status_is(200)
      ->content_like(qr/Your change has been proposed/);
    $t->get_ok('/licenses/proposed/meta?action=create_pattern&action=create_ignore')
      ->status_is(200)
      ->json_has('/changes/0');

    my $ignore_form = {'mark-non-license' => 1, hash => '399908965a4311ddd48a9440a66365e0'};
    $t->post_ok('/snippet/decision/1' => form => $ignore_form)->status_is(200)->content_like(qr/Reindexing 1 package/);
    is $t->app->pg->db->query('SELECT * FROM snippets WHERE id = 3')->hash->{classified}, 1, 'classified';
    $t->get_ok('/licenses/proposed/meta?action=create_pattern&action=create_ignore')
      ->status_is(200)
      ->json_hasnt('/changes/0');
  };

  subtest 'Pattern performance' => sub {
    $t->get_ok('/licenses/recent/meta')
      ->status_is(200)
      ->json_is('/patterns/0/id',                6)
      ->json_is('/patterns/0/pattern',           "This is\na license")
      ->json_is('/patterns/0/owner_login',       'tester')
      ->json_is('/patterns/0/contributor_login', 'tester')
      ->json_is('/patterns/1/id',                5)
      ->json_is('/patterns/1/pattern',           "The license might be\nsomething cool")
      ->json_is('/patterns/1/owner_login',       'tester')
      ->json_is('/patterns/1/contributor_login', 'tester')
      ->json_is('/patterns/2/id',                4)
      ->json_like('/patterns/2/pattern', qr/Permission is granted to copy, distribute and/)
      ->json_is('/patterns/2/owner_login',       undef)
      ->json_is('/patterns/2/contributor_login', undef)
      ->json_is('/total',                        6);

    $t->get_ok('/licenses/recent/meta?before=3')->status_is(200)->json_is('/patterns/0/id', 2)->json_is('/total', 2);

    subtest 'Timeframe' => sub {
      $t->get_ok('/licenses/recent/meta?before=3&timeframe=any')
        ->status_is(200)
        ->json_is('/patterns/0/id', 2)
        ->json_is('/total',         2);
      $t->get_ok('/licenses/recent/meta?before=3&timeframe=hour')
        ->status_is(200)
        ->json_is('/patterns/0/id', 2)
        ->json_is('/total',         2);
      $t->app->pg->db->query("UPDATE license_patterns SET created = NOW() - INTERVAL '2 weeks' WHERE id = 2");
      $t->get_ok('/licenses/recent/meta?before=3&timeframe=hour')
        ->status_is(200)
        ->json_is('/patterns/0/id', 1)
        ->json_is('/total',         1);
    };

    subtest 'Contributor' => sub {
      $t->get_ok('/licenses/recent/meta?before=3&hasContributor=false')
        ->status_is(200)
        ->json_is('/patterns/0/id', 2)
        ->json_is('/total',         2);
      $t->get_ok('/licenses/recent/meta?before=3&hasContributor=true')->status_is(200)->json_is('/total', 0);
      $t->app->pg->db->query("UPDATE license_patterns SET owner = 2, contributor = 2 WHERE id = 2");
      $t->get_ok('/licenses/recent/meta?before=3&hasContributor=true')
        ->status_is(200)
        ->json_is('/patterns/0/id', 2)
        ->json_is('/total',         1);
    };
  };
};

subtest 'Cancelled proposal' => sub {
  $t->app->users->remove_role(2, 'admin');
  $t->post_ok("/licenses/proposed/remove/123")->status_is(403);

  subtest 'License pattern' => sub {
    $t->post_ok(
      '/snippet/decision/2' => form => {'propose-pattern' => 1, license => 'GPL', pattern => 'The GPL', risk => 5})
      ->status_is(200)
      ->content_like(qr/Your change has been proposed/);
    $t->get_ok('/licenses/proposed/meta?action=create_pattern&action=create_ignore')
      ->status_is(200)
      ->json_has('/changes/0')
      ->json_hasnt('/changes/1');
    my $checksum = $t->tx->res->json->{changes}[0]{token_hexsum};
    $t->post_ok("/licenses/proposed/remove/$checksum")->status_is(200)->json_is('/removed', 1);

    $t->app->users->add_role(2, 'admin');
    $t->post_ok("/licenses/proposed/remove/123")->status_is(200)->json_is('/removed', 0);
  };

  subtest 'Ignore pattern' => sub {
    $t->post_ok(
      '/snippet/decision/1' => form => {
        'propose-ignore' => 1,
        hash             => '39e8204ddebdc31a4d0e77aa647f4243',
        from             => 'perl-Mojolicious',
        pattern          => 'This is a license',
        edited           => 0
      }
    )->status_is(200)->content_like(qr/Your change has been proposed/);
    $t->post_ok("/licenses/proposed/remove/39e8204ddebdc31a4d0e77aa647f4243")->status_is(200)->json_is('/removed', 1);
  };

  subtest 'Missing license' => sub {
    $t->post_ok(
      '/snippet/decision/1' => form => {
        'propose-missing' => 1,
        hash              => '39e8204ddebdc31a4d0e77aa647f4243',
        from              => 'perl-Mojolicious',
        pattern           => 'This is a license',
        edited            => 0
      }
    )->status_is(200)->content_like(qr/Missing license has been reported/);
    $t->post_ok("/licenses/proposed/remove/39e8204ddebdc31a4d0e77aa647f4243")->status_is(200)->json_is('/removed', 1);
  };
};

subtest 'Remove ignored match' => sub {
  $t->app->minion->perform_jobs;
  $t->app->users->add_role(2, 'admin');

  is $t->app->minion->jobs({tasks => ['index'], states => ['inactive']})->total, 0, 'no jobs';
  $t->post_ok('/snippet/decision/1' => form =>
      {'create-ignore' => 1, hash => 'abe8204ddebdc31a4d0e77aa647f42cd', from => 'package-with-snippets'})
    ->status_is(200)
    ->content_like(qr/ignore pattern has been created/);
  is $t->app->minion->jobs({tasks => ['index'], states => ['inactive']})->total, 1, 'job created';
  $t->get_ok('/pagination/matches/ignored')
    ->status_is(200)
    ->json_has('/page/0')
    ->json_is('/start',           1)
    ->json_is('/end',             3)
    ->json_is('/total',           3)
    ->json_is('/page/0/hash',     'abe8204ddebdc31a4d0e77aa647f42cd')
    ->json_is('/page/0/packname', 'package-with-snippets')
    ->json_is('/page/0/matches',  0)
    ->json_is('/page/0/packages', 0);
  my $id = $t->tx->res->json->{page}[0]{id};

  $t->get_ok('/pagination/matches/ignored?filter=with-snippets')
    ->status_is(200)
    ->json_has('/page/0')
    ->json_is('/start',       1)
    ->json_is('/end',         1)
    ->json_is('/total',       1)
    ->json_is('/page/0/hash', 'abe8204ddebdc31a4d0e77aa647f42cd');
  $t->get_ok('/pagination/matches/ignored?filter=does_not_exist')
    ->status_is(200)
    ->json_is('/start', 1)
    ->json_is('/end',   0)
    ->json_is('/total', 0);

  $t->app->minion->perform_jobs;
  is $t->app->minion->jobs({tasks => ['index'], states => ['inactive']})->total, 0, 'no jobs';
  my $logs = $t->app->log->capture('trace');
  $t->delete_ok("/ignored-matches/$id")->status_is(200)->json_is('ok');
  $t->delete_ok("/ignored-matches/$id")->status_is(400)->json_is({error => 'Ignored match does not exist'});
  like $logs, qr!User "tester" removed ignored match "abe8204ddebdc31a4d0e77aa647f42cd"!, 'right message';
  is $t->app->minion->jobs({tasks => ['index'], states => ['inactive']})->total, 1, 'job created';
};

done_testing();
