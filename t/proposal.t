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

use Mojo::Base -strict, -signatures;

use FindBin;
use lib "$FindBin::Bin/lib";

use Test::More;
use Test::Mojo;
use Cavil::Test;
use Mojo::JSON qw(true false);
use Mojo::Util qw(md5_sum);

plan skip_all => 'set TEST_ONLINE to enable this test' unless $ENV{TEST_ONLINE};

my $cavil_test = Cavil::Test->new(online => $ENV{TEST_ONLINE}, schema => 'proposal_test');
my $t          = Test::Mojo->new(Cavil => $cavil_test->default_config);
$cavil_test->package_with_snippets_fixtures($t->app);

my $db = $t->app->pg->db;

# Helper: submit one snippet decision through the batch endpoint. All callers
# in this test file work on a single action at a time, so a one-element batch
# is the equivalent of the old per-snippet POST.
sub dec ($snippet_id, $kind, $form = {}) {
  return $t->post_ok('/snippet/batch_decision' => json =>
      {actions => [{kind => $kind, snippetId => $snippet_id + 0, formData => $form}]});
}

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

subtest 'Smart edit' => sub {
  $t->get_ok('/snippet/smart_edit/1')->status_is(401);

  $t->get_ok('/login')->status_is(302)->header_is(Location => '/');

  $t->get_ok('/snippet/smart_edit/1')
    ->status_is(200)
    ->json_has('/pattern')
    ->json_has('/start_line')
    ->json_is('/changed', true)
    ->json_like('/pattern', qr/license/)
    ->json_unlike('/pattern', qr/Must you with him from him/);

  $t->get_ok('/snippet/smart_edit/999999')->status_is(404);

  $t->get_ok('/logout')->status_is(302)->header_is(Location => '/');
};

subtest 'Pattern creation' => sub {
  subtest 'Permission errors' => sub {
    $t->get_ok('/login')->status_is(302)->header_is(Location => '/');
    $t->app->users->remove_role(2, 'admin');
    $t->get_ok('/logout')->status_is(302)->header_is(Location => '/');

    # No login at all - auth layer blocks before the controller runs.
    dec(1, 'create-pattern')->status_is(403);
    dec(1, 'propose-pattern')->status_is(403);
    dec(1, 'propose-ignore')->status_is(403);
    dec(1, 'propose-missing')->status_is(403);
    dec(1, 'mark-non-license')->status_is(403);

    # Logged in without any role - auth layer still blocks.
    $t->get_ok('/login')->status_is(302)->header_is(Location => '/');
    dec(1, 'create-pattern',  {license => 'Test', pattern => 'This is a license', risk => 5})->status_is(403);
    dec(1, 'propose-pattern', {license => 'Test', pattern => 'This is a license', risk => 5})->status_is(403);
    dec(
      1,
      'propose-ignore',
      {
        hash    => '39e8204ddebdc31a4d0e77aa647f4241',
        from    => 'perl-Mojolicious',
        pattern => 'This is a license',
        edited  => 0
      }
    )->status_is(403);
    dec(1, 'mark-non-license', {hash => '39e8204ddebdc31a4d0e77aa647f4241'})->status_is(403);

    # Contributor role - admin-only kinds still rejected (in-controller check).
    $t->app->users->add_role(2, 'contributor');
    dec(1, 'create-pattern', {license => 'Test', pattern => 'This is a license', risk => 5})
      ->status_is(403)
      ->json_like('/results/0/error', qr/Permission denied/);
  };

  subtest 'Pattern mismatch' => sub {
    dec(1, 'propose-pattern', {license => 'Test', pattern => 'This is a license', risk => 5})
      ->status_is(400)
      ->json_like('/results/0/error', qr/License pattern does not match the original snippet/);
  };

  subtest 'Pattern with misplaced skip' => sub {
    dec(1, 'propose-pattern', {license => 'Test', pattern => "\$SKIP1 The license might be\nsomething cool", risk => 5})
      ->status_is(400)
      ->json_like('/results/0/error', qr/License pattern contains redundant \$SKIP at beginning or end/);
    dec(1, 'propose-pattern',
      {license => 'Test', pattern => " \$SKIP1 The license might be\nsomething cool", risk => 5})
      ->status_is(400)
      ->json_like('/results/0/error', qr/License pattern contains redundant \$SKIP at beginning or end/);

    dec(1, 'propose-pattern', {license => 'Test', pattern => "The license might be\nsomething \$SKIP11", risk => 5})
      ->status_is(400)
      ->json_like('/results/0/error', qr/License pattern contains redundant \$SKIP at beginning or end/);
    dec(1, 'propose-pattern', {license => 'Test', pattern => "The license might be\nsomething \$SKIP11 ", risk => 5})
      ->status_is(400)
      ->json_like('/results/0/error', qr/License pattern contains redundant \$SKIP at beginning or end/);
  };

  subtest 'Bad license and risk combinations' => sub {
    dec(1, 'propose-pattern', {license => 'Test', pattern => "The license might be\nsomething cool", risk => 5})
      ->status_is(400)
      ->json_like('/results/0/error',
      qr/This license and risk combination is not allowed, only use pre-existing licenses/);
  };

  subtest 'Edited patterns cannot be ignored' => sub {
    dec(
      1,
      'propose-ignore',
      {
        hash    => '39e8204ddebdc31a4d0e77aa647f4241',
        from    => 'perl-Mojolicious',
        pattern => 'This is a license',
        edited  => 1
      }
    )->status_is(400)->json_like('/results/0/error', qr/Only unedited snippets can be ignored/);
  };

  subtest 'Edited patterns cannot be flagged as missing license' => sub {
    dec(
      1,
      'propose-missing',
      {
        hash    => '39e8204ddebdc31a4d0e77aa647f4241',
        from    => 'perl-Mojolicious',
        pattern => 'This is a license',
        edited  => 1
      }
    )->status_is(400)->json_like('/results/0/error', qr/Only unedited snippets can be reported as missing license/);
  };

  subtest 'From proposal to pattern' => sub {
    dec(
      1,
      'propose-pattern',
      {
        license                => 'GPL',
        pattern                => "The license might be\nsomething cool",
        'highlighted-keywords' => '0',
        'highlighted-licenses' => '1',
        edited                 => '1',
        risk                   => 5
      }
    )->status_is(200)->json_is('/ok', true)->json_is('/results/0/kind', 'proposal');
    dec(1, 'propose-pattern', {license => 'GPL', pattern => "The license might be\nsomething cool", risk => 5})
      ->status_is(409)
      ->json_like('/results/0/error', qr/Conflicting license pattern proposal already exists/);
    dec(1, 'create-pattern', {license => 'GPL', pattern => "The license might be\nsomething cool", risk => 5})
      ->status_is(403);

    subtest 'Filtering' => sub {
      $t->get_ok('/licenses/proposed/meta?action=create_pattern&action=create_ignore&filter=license')
        ->status_is(200)
        ->json_has('/changes/0')
        ->json_is('/changes/0/action'           => 'create_pattern')
        ->json_is('/changes/0/data/ai_assisted' => 0)
        ->json_is('/changes/0/data/license'     => 'GPL')
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
    $t->get_ok('/licenses/proposed/stats')->status_is(200)->json_is('/missing' => 0)->json_is('/proposals' => 1);
    $t->app->users->add_role(2, 'admin');
    dec(
      1,
      'create-pattern',
      {
        license     => 'GPL',
        pattern     => "The license might be\nsomething cool",
        risk        => 5,
        checksum    => $checksum,
        contributor => 'tester'
      }
    )->status_is(200)->json_is('/ok', true)->json_is('/results/0/kind', 'pattern');
    $t->get_ok('/licenses/proposed/meta?action=create_pattern&action=create_ignore')
      ->status_is(200)
      ->json_hasnt('/changes/0');
    $t->get_ok('/licenses/proposed/stats')->status_is(200)->json_is('/missing' => 0)->json_is('/proposals' => 0);

    dec(1, 'create-pattern', {license => 'GPL', pattern => "The license might be\nsomething cool", risk => 5})
      ->status_is(409)
      ->json_like('/results/0/error', qr/Conflicting license pattern already exists/);
    $t->app->users->remove_role(2, 'admin');
  };

  subtest 'From proposal to ignore pattern' => sub {
    my $form = {
      hash                   => '39e8204ddebdc31a4d0e77aa647f4241',
      from                   => 'perl-Mojolicious',
      pattern                => "This is\na license",
      edited                 => 0,
      'highlighted-keywords' => 1,
      'highlighted-licenses' => 0
    };
    dec(1, 'propose-ignore', $form)->status_is(200)->json_is('/ok', true)->json_is('/results/0/kind', 'proposal');
    dec(1, 'propose-ignore', $form)
      ->status_is(409)
      ->json_like('/results/0/error', qr/Conflicting ignore pattern proposal already exists/);
    my $ignore_form = {hash => '39e8204ddebdc31a4d0e77aa647f4241', from => 'perl-Mojolicious', contributor => 'tester'};
    dec(1, 'create-ignore', $ignore_form)->status_is(403);

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
    dec(1, 'create-ignore', $ignore_form)->status_is(200)->json_is('/ok', true)->json_is('/results/0/kind', 'ignore');
    $t->get_ok('/licenses/proposed/meta?action=create_pattern&action=create_ignore')
      ->status_is(200)
      ->json_hasnt('/changes/0');

    dec(1, 'propose-ignore', $form)
      ->status_is(409)
      ->json_like('/results/0/error', qr/Conflicting ignore pattern already exists/);

    subtest 'Same checksum and a different package' => sub {
      dec(1, 'propose-ignore', {%$form, from => 'perl-AnotherPackage'})
        ->status_is(200)
        ->json_is('/results/0/kind', 'proposal');
      dec(2, 'create-ignore', {%$ignore_form, from => 'perl-AnotherPackage'})
        ->status_is(200)
        ->json_is('/results/0/kind', 'ignore');
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
      hash                   => '39e8204ddebdc31a4d0e77aa647f4241',
      from                   => 'perl-Mojolicious',
      pattern                => "This is\na license",
      edited                 => 0,
      'highlighted-keywords' => 1,
      'highlighted-licenses' => 0
    };
    dec(1, 'propose-missing', $form)->status_is(200)->json_is('/ok', true)->json_is('/results/0/kind', 'missing');
    dec(1, 'propose-missing', $form)
      ->status_is(409)
      ->json_like('/results/0/error', qr/Conflicting pattern proposal already exists/);

    $t->get_ok('/licenses/proposed/meta?action=missing_license')
      ->status_is(200)
      ->json_has('/changes/0')
      ->json_is('/changes/0/action'                    => 'missing_license')
      ->json_is('/changes/0/data/pattern'              => "This is\na license")
      ->json_is('/changes/0/data/highlighted_keywords' => [1])
      ->json_is('/changes/0/data/highlighted_licenses' => [0])
      ->json_is('/changes/0/data/edited'               => 0)
      ->json_hasnt('/changes/1');

    dec(
      1,
      'create-pattern',
      {
        license     => 'MyCustomLicense',
        pattern     => "This is\na license",
        risk        => 5,
        checksum    => '39e8204ddebdc31a4d0e77aa647f4241',
        contributor => 'tester'
      }
    )->status_is(200)->json_is('/ok', true)->json_is('/results/0/kind', 'pattern');
    $t->get_ok('/licenses/proposed/meta?action=missing_license')->status_is(200)->json_hasnt('/changes/0');
  };

  subtest 'From proposal to not a license snippet' => sub {
    is $t->app->pg->db->query('SELECT * FROM snippets WHERE id = 3')->hash->{classified}, 0, 'not classified';
    my $form = {
      hash                   => '399908965a4311ddd48a9440a66365e0',
      from                   => 'perl-Mojolicious',
      pattern                => "Now complex: The license might",
      edited                 => 0,
      'highlighted-keywords' => 1,
      'highlighted-licenses' => 0
    };
    dec(1, 'propose-ignore', $form)->status_is(200)->json_is('/ok', true)->json_is('/results/0/kind', 'proposal');
    $t->get_ok('/licenses/proposed/meta?action=create_pattern&action=create_ignore')
      ->status_is(200)
      ->json_has('/changes/0');

    my $ignore_form = {hash => '399908965a4311ddd48a9440a66365e0'};
    dec(1, 'mark-non-license', $ignore_form)
      ->status_is(200)
      ->json_is('/ok',                   true)
      ->json_is('/results/0/kind',       'non-license')
      ->json_is('/results/0/packages/0', 1);
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
      ->json_is('/hasMore',                      false);

    $t->get_ok('/licenses/recent/meta?before=3')
      ->status_is(200)
      ->json_is('/patterns/0/id', 2)
      ->json_is('/hasMore',       false);

    subtest 'Timeframe' => sub {
      $t->get_ok('/licenses/recent/meta?before=3&timeframe=any')
        ->status_is(200)
        ->json_is('/patterns/0/id', 2)
        ->json_is('/hasMore',       false);
      $t->get_ok('/licenses/recent/meta?before=3&timeframe=hour')
        ->status_is(200)
        ->json_is('/patterns/0/id', 2)
        ->json_is('/hasMore',       false);
      $t->app->pg->db->query("UPDATE license_patterns SET created = NOW() - INTERVAL '2 weeks' WHERE id = 2");
      $t->get_ok('/licenses/recent/meta?before=3&timeframe=hour')
        ->status_is(200)
        ->json_is('/patterns/0/id', 1)
        ->json_is('/hasMore',       false);
    };

    subtest 'Contributor' => sub {
      $t->get_ok('/licenses/recent/meta?before=3&hasContributor=false')
        ->status_is(200)
        ->json_is('/patterns/0/id', 2)
        ->json_is('/hasMore',       false);
      $t->get_ok('/licenses/recent/meta?before=3&hasContributor=true')->status_is(200)->json_is('/hasMore', false);
      $t->app->pg->db->query("UPDATE license_patterns SET owner = 2, contributor = 2 WHERE id = 2");
      $t->get_ok('/licenses/recent/meta?before=3&hasContributor=true')
        ->status_is(200)
        ->json_is('/patterns/0/id', 2)
        ->json_is('/hasMore',       false);
    };
  };
};

subtest 'Cancelled proposal' => sub {
  $t->app->users->remove_role(2, 'admin');
  $t->post_ok("/licenses/proposed/remove/123")->status_is(403);

  subtest 'License pattern' => sub {
    dec(2, 'propose-pattern', {license => 'GPL', pattern => 'The GPL', risk => 5})
      ->status_is(200)
      ->json_is('/results/0/kind', 'proposal');
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
    dec(
      1,
      'propose-ignore',
      {
        hash    => '39e8204ddebdc31a4d0e77aa647f4243',
        from    => 'perl-Mojolicious',
        pattern => 'This is a license',
        edited  => 0
      }
    )->status_is(200)->json_is('/results/0/kind', 'proposal');
    $t->post_ok("/licenses/proposed/remove/39e8204ddebdc31a4d0e77aa647f4243")->status_is(200)->json_is('/removed', 1);
  };

  subtest 'Missing license' => sub {
    dec(
      1,
      'propose-missing',
      {
        hash    => '39e8204ddebdc31a4d0e77aa647f4243',
        from    => 'perl-Mojolicious',
        pattern => 'This is a license',
        edited  => 0
      }
    )->status_is(200)->json_is('/results/0/kind', 'missing');
    $t->post_ok("/licenses/proposed/remove/39e8204ddebdc31a4d0e77aa647f4243")->status_is(200)->json_is('/removed', 1);
  };
};

subtest 'Remove ignored match' => sub {
  $t->app->minion->perform_jobs;
  $t->app->users->add_role(2, 'admin');

  is $t->app->minion->jobs({tasks => ['index', 'analyze'], states => ['inactive']})->total, 0, 'no jobs';
  dec(1, 'create-ignore', {hash => 'abe8204ddebdc31a4d0e77aa647f42cd', from => 'package-with-snippets'})
    ->status_is(200)
    ->json_is('/results/0/kind', 'ignore');
  is $t->app->minion->jobs({tasks => ['index'],   states => ['inactive']})->total, 0, 'no reindex enqueued';
  is $t->app->minion->jobs({tasks => ['analyze'], states => ['inactive']})->total, 1, 'analyze job enqueued';
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

subtest 'Ignore with real snippet (analyze-only path)' => sub {
  $t->app->minion->perform_jobs;

  # Pick a real snippet hash with at least one overlapping pattern_match
  my $hash = $db->query(
    'SELECT s.hash FROM snippets s
       JOIN file_snippets fs ON fs.snippet = s.id
       JOIN pattern_matches pm ON pm.file = fs.file AND pm.package = fs.package
                              AND pm.sline <= fs.eline AND pm.eline >= fs.sline
       WHERE fs.package = 1 AND pm.ignored = FALSE LIMIT 1'
  )->hash->{hash};
  ok $hash, 'fixture has an unignored pattern_match overlapping a snippet';

  is $t->app->minion->jobs({tasks => ['index', 'analyze'], states => ['inactive']})->total, 0, 'no jobs';
  dec(1, 'create-ignore', {hash => $hash, from => 'package-with-snippets'})
    ->status_is(200)
    ->json_is('/results/0/kind', 'ignore');
  is $t->app->minion->jobs({tasks => ['index'],   states => ['inactive']})->total, 0, 'no reindex enqueued';
  is $t->app->minion->jobs({tasks => ['analyze'], states => ['inactive']})->total, 1, 'analyze job enqueued';
  $t->app->minion->perform_jobs;

  $t->get_ok('/pagination/matches/ignored?filter=with-snippets')
    ->status_is(200)
    ->json_has('/page/0')
    ->json_is('/page/0/hash',     $hash)
    ->json_is('/page/0/packname', 'package-with-snippets')
    ->json_is('/page/0/packages', 1);
  my $marked = $t->tx->res->json->{page}[0]{matches};
  my $id     = $t->tx->res->json->{page}[0]{id};
  ok $marked > 0, "pattern_matches marked ignored via analyze ($marked rows)";

  subtest 'Re-ignoring the same hash is idempotent' => sub {
    dec(1, 'create-ignore', {hash => $hash, from => 'package-with-snippets'})
      ->status_is(200)
      ->json_is('/results/0/kind', 'ignore');
    $t->get_ok('/pagination/matches/ignored?filter=with-snippets')
      ->status_is(200)
      ->json_is('/page/0/id',      $id)
      ->json_is('/page/0/matches', $marked);
  };

  subtest 'Removing the ignore un-ignores the matches' => sub {
    $t->app->minion->perform_jobs;
    $t->delete_ok("/ignored-matches/$id")->status_is(200)->json_is('ok');
    is $t->app->minion->jobs({tasks => ['index'], states => ['inactive']})->total, 1, 'reindex enqueued on removal';
    $t->app->minion->perform_jobs;

    $t->get_ok('/pagination/matches/ignored?filter=with-snippets')->status_is(200)->json_is('/total', 0);
    my $still = $db->query('SELECT COUNT(*) AS c FROM pattern_matches WHERE ignored_line = ?', $id)->hash->{c};
    is $still, 0, 'no pattern_matches still reference the removed ignored_line';
    my $unignored = $db->query(
      'SELECT COUNT(*) AS c FROM pattern_matches pm
         JOIN file_snippets fs ON pm.file = fs.file AND pm.package = fs.package
                              AND pm.sline <= fs.eline AND pm.eline >= fs.sline
         JOIN snippets s ON fs.snippet = s.id
         WHERE pm.package = 1 AND s.hash = ? AND pm.ignored = FALSE', $hash
    )->hash->{c};
    ok $unignored > 0, "matches now unignored ($unignored rows)";
  };

  subtest 'Re-creating the ignore after removal marks again' => sub {
    dec(1, 'create-ignore', {hash => $hash, from => 'package-with-snippets'})
      ->status_is(200)
      ->json_is('/results/0/kind', 'ignore');
    $t->app->minion->perform_jobs;
    $t->get_ok('/pagination/matches/ignored?filter=with-snippets')
      ->status_is(200)
      ->json_is('/page/0/hash',     $hash)
      ->json_is('/page/0/packages', 1);
    my $remarked = $t->tx->res->json->{page}[0]{matches};
    isnt $t->tx->res->json->{page}[0]{id}, $id, 'new ignored_lines id';
    ok $remarked > 0, "matches re-marked after recreating the ignore ($remarked rows)";
  };
};

subtest 'Propose ignore glob' => sub {
  $t->app->minion->perform_jobs;

  # Clean role baseline: contributor proposes, admin accepts (mirrors the pattern proposal flow)
  $t->app->users->remove_role(2, 'admin');
  $t->app->users->add_role(2, 'contributor');

  # The fixture package has a single matched file "README"; globs are validated against the
  # package's matched files, so the proposed glob has to actually cover it.
  ok $db->query('SELECT 1 AS ok FROM matched_files WHERE package = 1 AND filename = ?', 'README')->hash,
    'fixture has a matched README file';
  my $glob = 'READ*';

  # Glob proposals are file-path based and carry no snippet id
  my $glob_dec = sub ($kind, $form) {
    return $t->post_ok('/snippet/batch_decision' => json => {actions => [{kind => $kind, formData => $form}]});
  };

  subtest 'Contributor proposes a glob' => sub {
    $glob_dec->('propose-glob', {glob => $glob, from => 'package-with-snippets', package => 1})
      ->status_is(200)
      ->json_is('/ok',             true)
      ->json_is('/results/0/kind', 'proposal');

    # Duplicate proposal is rejected
    $glob_dec->('propose-glob', {glob => $glob, from => 'package-with-snippets', package => 1})
      ->status_is(409)
      ->json_like('/results/0/error', qr/Conflicting ignore glob proposal already exists/);
  };

  subtest 'Glob proposal on the Change Proposals page' => sub {
    $t->get_ok('/licenses/proposed/meta?action=create_glob')
      ->status_is(200)
      ->json_has('/changes/0')
      ->json_is('/changes/0/action'       => 'create_glob')
      ->json_is('/changes/0/data/glob'    => $glob)
      ->json_is('/changes/0/data/from'    => 'package-with-snippets')
      ->json_is('/changes/0/package/name' => 'package-with-snippets')
      ->json_is('/changes/0/closest'      => undef)
      ->json_hasnt('/changes/1');
    is $t->tx->res->json->{changes}[0]{token_hexsum}, md5_sum($glob), 'token is the glob checksum';

    # Counted by the proposal stats (drives the menu badge)
    $t->get_ok('/licenses/proposed/stats')->status_is(200)->json_is('/proposals' => 1);
  };

  subtest 'Only admins may accept a glob' => sub {
    $glob_dec->('create-glob', {glob => $glob, package => 1, checksum => md5_sum($glob)})->status_is(403);
  };

  subtest 'Admin accepts the glob' => sub {
    is $t->app->minion->jobs({tasks => ['index'], states => ['inactive']})->total, 0, 'no reindex yet';
    $t->app->users->add_role(2, 'admin');
    $glob_dec->('create-glob', {glob => $glob, package => 1, checksum => md5_sum($glob), contributor => 'tester'})
      ->status_is(200)
      ->json_is('/ok',             true)
      ->json_is('/results/0/kind', 'glob');

    # Originating package is reindexed so its report picks up the new glob
    is $t->app->minion->jobs({tasks => ['index'], states => ['inactive']})->total, 1,
      'reindex enqueued for originating package';

    my $ignored = $db->query('SELECT * FROM ignored_files WHERE glob = ?', $glob)->hash;
    ok $ignored, 'glob stored in ignored_files';
    is $ignored->{owner},       2, 'owner is the accepting admin';
    is $ignored->{contributor}, 2, 'contributor is the original proposer';

    # Proposal is gone once accepted
    $t->get_ok('/licenses/proposed/meta?action=create_glob')->status_is(200)->json_hasnt('/changes/0');
  };

  subtest 'Proposing an existing glob conflicts' => sub {
    $glob_dec->('propose-glob', {glob => $glob, from => 'package-with-snippets', package => 1})
      ->status_is(409)
      ->json_like('/results/0/error', qr/Conflicting ignore glob already exists/);
  };

  subtest 'Missing glob is rejected' => sub {
    $glob_dec->('propose-glob', {from => 'package-with-snippets', package => 1})
      ->status_is(400)
      ->json_like('/results/0/error', qr/Missing required field: glob/);
  };

  subtest 'Glob that matches no reported file is rejected' => sub {
    $glob_dec->(
      'propose-glob',
      {glob => 'package-with-snippets-*/does/not/exist-*.xyz', from => 'package-with-snippets', package => 1}
    )->status_is(400)->json_like('/results/0/error', qr/Glob does not match any files in the package report/);
    $t->get_ok('/licenses/proposed/meta?action=create_glob')->status_is(200)->json_hasnt('/changes/0');
  };

  subtest 'Rejecting a glob proposal' => sub {
    my $other = 'R*';
    $glob_dec->('propose-glob', {glob => $other, from => 'package-with-snippets', package => 1})
      ->status_is(200)
      ->json_is('/results/0/kind', 'proposal');
    $t->post_ok('/licenses/proposed/remove/' . md5_sum($other))->status_is(200)->json_is('/removed', 1);
    $t->get_ok('/licenses/proposed/meta?action=create_glob')->status_is(200)->json_hasnt('/changes/0');
  };

  $t->app->minion->perform_jobs;
};

done_testing();
