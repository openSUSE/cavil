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
use Mojo::File qw(path tempdir);
use Mojo::Pg;
use Mojolicious::Lite;

plan skip_all => 'set TEST_ONLINE to enable this test' unless $ENV{TEST_ONLINE};

my $cavil_test = Cavil::Test->new(online => $ENV{TEST_ONLINE}, schema => 'manual_review_test');
my $t          = Test::Mojo->new(Cavil => $cavil_test->default_config);
$cavil_test->mojo_fixtures($t->app);

subtest 'Globs' => sub {
  subtest 'Permission errors' => sub {
    $t->get_ok('/ignored-files')->status_is(403)->content_like(qr/permission/);
    $t->post_ok('/ignored-files')->status_is(403)->content_like(qr/permission/);
    $t->get_ok('/pagination/files/ignored')->status_is(403)->content_like(qr/permission/);
    $t->delete_ok('/ignored-files/1')->status_is(403)->content_like(qr/permission/);
  };

  subtest 'Edit globs' => sub {
    $t->get_ok('/login')->status_is(302)->header_is(Location => '/');

    is $t->app->minion->jobs({tasks => ['analyze']})->total, 0, 'no jobs';
    $t->post_ok('/ignored-files' => form => {glob => 'does/not/exist/*', package => 1})->status_is(200)->json_is('ok');
    is $t->app->pg->db->select('ignored_files')->hashes->to_array->[0]{glob}, 'does/not/exist/*', 'glob added';
    is $t->app->minion->jobs({tasks => ['analyze']})->total,                  1,                  'job enqueued';
    $t->app->minion->perform_jobs;

    $t->get_ok('/pagination/files/ignored')->status_is(200)->json_is('/start', 1)->json_is('/end', 1)
      ->json_is('/total',        1)->json_is('/page/0/id', 1)->json_like('/page/0/glob', qr/does/)
      ->json_is('/page/0/login', 'tester')->json_has('/page/0/created_epoch')->json_hasnt('/page/1');
    $t->get_ok('/pagination/files/ignored?filter=does')->status_is(200)->json_is('/start', 1)->json_is('/end', 1)
      ->json_is('/total', 1)->json_is('/page/0/id', 1)->json_like('/page/0/glob', qr/does/)->json_hasnt('/page/1');
    $t->get_ok('/pagination/files/ignored?filter=whatever')->status_is(200)->json_is('/start', 1)->json_is('/end', 0)
      ->json_is('/total', 0)->json_hasnt('/page/1');

    my $logs = $t->app->log->capture('trace');
    $t->delete_ok('/ignored-files/1')->status_is(200)->json_is('ok');
    $t->delete_ok('/ignored-files/1')->status_is(400)->json_is({error => 'Glob does not exist'});
    like $logs, qr!User "tester" removed glob "does/not/exist/\*"!, 'right message';

    $t->get_ok('/logout')->status_is(302)->header_is(Location => '/');
  };
};

subtest 'Details after import (indexing in progress)' => sub {
  $t->get_ok('/login')->status_is(302)->header_is(Location => '/');

  $t->get_ok('/reviews/meta/1')->status_is(200)->json_like('/package_license/name', qr!Artistic-2.0!)
    ->json_is('/package_license/spdx', 1)->json_like('/package_version', qr!7\.25!)
    ->json_like('/package_summary',                                      qr!Real-time web framework!)
    ->json_like('/package_group',                                        qr!Development/Libraries/Perl!)
    ->json_like('/package_url', qr!http://search\.cpan\.org/dist/Mojolicious/!)->json_like('/state', qr!new!);

  $t->json_like('/package_files/0/file',       qr/perl-Mojolicious\.spec/)
    ->json_like('/package_files/0/licenses/0', qr/Artistic-2.0/)->json_like('/package_files/0/version', qr/7\.25/)
    ->json_like('/package_files/0/sources/0',  qr/http:\/\/www\.cpan\.org/)
    ->json_like('/package_files/0/summary',    qr/Real-time web framework/)
    ->json_like('/package_files/0/url',        qr/http:\/\//)
    ->json_like('/package_files/0/group',      qr/Development\/Libraries\/Perl/);

  $t->json_is('/errors', [])->json_is('/warnings', []);

  $t->get_ok('/reviews/calc_report/1')->status_is(408)->content_like(qr/not indexed/);
  $t->get_ok('/reviews/fetch_source/1')->status_is(404);

  $t->get_ok('/logout')->status_is(302)->header_is(Location => '/');
};

subtest 'Details after import (with login)' => sub {
  $t->get_ok('/login')->status_is(302)->header_is(Location => '/');

  $t->get_ok('/reviews/meta/1')->status_is(200)->json_like('/package_license/name', qr!Artistic-2.0!)
    ->json_is('/package_license/spdx', 1)->json_like('/package_version', qr!7\.25!)
    ->json_like('/package_summary',                                      qr!Real-time web framework!)
    ->json_like('/package_group',                                        qr!Development/Libraries/Perl!)
    ->json_like('/package_url', qr!http://search\.cpan\.org/dist/Mojolicious/!)->json_like('/state', qr!new!);

  $t->get_ok('/reviews/calc_report/1')->status_is(408)->content_like(qr/not indexed/);

  $t->get_ok('/logout')->status_is(302)->header_is(Location => '/');
};

# Unpack and index
$t->app->minion->enqueue(unpack => [1]);
$t->app->minion->perform_jobs;

subtest 'Snippets after indexing' => sub {
  my $snippets = $t->app->pg->db->select('snippets')->hashes->to_array;
  is $snippets->[0]{id},           1,     'snippet';
  is $snippets->[0]{like_pattern}, undef, 'unlike any pattern';
  ok !$snippets->[0]{likelyness}, 'no likelyness';
  is $snippets->[1]{id},           2,     'snippet';
  is $snippets->[1]{like_pattern}, undef, 'unlike any pattern';
  ok !$snippets->[1]{likelyness}, 'no likelyness';
  is $snippets->[2]{id},           3,     'snippet';
  is $snippets->[2]{like_pattern}, undef, 'unlike any pattern';
  ok !$snippets->[2]{likelyness}, 'no likelyness';
  is $snippets->[3]{id},           4,     'snippet';
  is $snippets->[3]{like_pattern}, undef, 'unlike any pattern';
  ok !$snippets->[3]{likelyness}, 'no likelyness';
  is $snippets->[4]{id},           5,     'snippet';
  is $snippets->[4]{like_pattern}, undef, 'unlike any pattern';
  ok !$snippets->[4]{likelyness}, 'no likelyness';
  is $snippets->[5]{id},           6,     'snippet';
  is $snippets->[5]{like_pattern}, undef, 'unlike any pattern';
  ok !$snippets->[5]{likelyness}, 'no likelyness';
  is $snippets->[6], undef, 'no more snippets';
};

subtest 'Details after indexing' => sub {
  $t->get_ok('/login')->status_is(302)->header_is(Location => '/');

  $t->get_ok('/reviews/meta/1')->status_is(200)->json_like('/package_license/name', qr!Artistic-2.0!)
    ->json_is('/package_license/spdx', 1)->json_like('/package_version', qr!7\.25!)
    ->json_like('/package_summary',                                      qr!Real-time web framework!)
    ->json_like('/package_group',                                        qr!Development/Libraries/Perl!)
    ->json_like('/package_url', qr!http://search\.cpan\.org/dist/Mojolicious/!)->json_like('/state', qr!new!);

  $t->get_ok('/reviews/calc_report/1')->status_is(200)->element_exists('#license-chart')->element_exists('#emails')
    ->text_like('#emails tr td', qr!coolo\@suse\.com!)->element_exists('#urls')
    ->text_like('#urls tr td',   qr!http://mojolicious.org!);

  $t->get_ok('/reviews/fetch_source/1')->status_is(200)->content_type_isnt('application/json;charset=UTF-8')
    ->content_like(qr/perl-Mojolicious/);
  $t->get_ok('/reviews/fetch_source/1.json')->status_is(200)->content_type_is('application/json;charset=UTF-8')
    ->content_like(qr/perl-Mojolicious/);

  $t->get_ok('/logout')->status_is(302)->header_is(Location => '/');
};

subtest 'JSON report' => sub {
  $t->get_ok('/login')->status_is(302)->header_is(Location => '/');

  $t->get_ok('/reviews/calc_report/1.json')->header_like(Vary => qr/Accept-Encoding/)->status_is(200);
  ok my $json = $t->tx->res->json, 'JSON response';

  ok my $pkg = $json->{package}, 'package';
  is $pkg->{id},   1,                  'id';
  is $pkg->{name}, 'perl-Mojolicious', 'name';
  like $pkg->{checksum}, qr!Artistic-2.0-9!, 'checksum';
  is $pkg->{login},  undef, 'no login';
  is $pkg->{state},  'new', 'state';
  is $pkg->{result}, undef, 'no result';

  ok my $report = $json->{report}, 'report';
  is $report->{emails}[0][0], 'coolo@suse.com', 'right email';
  ok $report->{emails}[0][1], 'multiple matches';
  is $report->{urls}[0][0], 'http://mojolicious.org', 'right URL';
  ok $report->{urls}[0][1], 'multiple matches';

  ok my $missed_files = $report->{missed_files}, 'missed files';
  is $missed_files->[0]{id},       1,         'id';
  is $missed_files->[0]{license},  'Snippet', 'license';
  is $missed_files->[0]{match},    0,         'no match';
  is $missed_files->[0]{max_risk}, 9,         'max risk';
  ok $missed_files->[0]{name}, 'name';
  is $missed_files->[1]{id},       2,         'id';
  is $missed_files->[1]{license},  'Snippet', 'license';
  is $missed_files->[1]{match},    0,         'no match';
  is $missed_files->[1]{max_risk}, 9,         'max risk';
  ok $missed_files->[1]{name}, 'name';
  is $missed_files->[2]{id},       5,         'id';
  is $missed_files->[2]{license},  'Snippet', 'license';
  is $missed_files->[2]{match},    0,         'no match';
  is $missed_files->[2]{max_risk}, 9,         'max risk';
  ok $missed_files->[2]{name}, 'name';
  is $missed_files->[3]{id},       7,         'id';
  is $missed_files->[3]{license},  'Snippet', 'license';
  is $missed_files->[3]{match},    0,         'no match';
  is $missed_files->[3]{max_risk}, 9,         'max risk';
  ok $missed_files->[3]{name}, 'name';
  is $missed_files->[4], undef, 'no more missed files';

  ok $report->{files}, 'files';
  ok my $licenses = $report->{licenses},       'licenses';
  ok my $apache   = $licenses->{'Apache-2.0'}, 'Apache';
  is $apache->{name}, 'Apache-2.0', 'name';
  is $apache->{risk}, 5,            'risk';

  $t->get_ok('/logout')->status_is(302)->header_is(Location => '/');
};

subtest 'Reindex (with updated stats)' => sub {
  $t->get_ok('/login')->status_is(302)->header_is(Location => '/');

  $t->app->minion->enqueue('pattern_stats');
  $t->app->minion->perform_jobs;
  $t->app->packages->reindex(1);
  $t->get_ok('/reviews/calc_report/1')->status_is(408)->content_like(qr/package being processed/);
  $t->app->minion->perform_jobs;

  $t->get_ok('/logout')->status_is(302)->header_is(Location => '/');
};

subtest 'Snippets after reindexing' => sub {
  my $snippets = $t->app->pg->db->select('snippets')->hashes->to_array;
  is $snippets->[0]{id},           1, 'snippet';
  is $snippets->[0]{like_pattern}, 6, 'like pattern';
  ok $snippets->[0]{likelyness} > 0, 'likelyness';
  is $snippets->[1]{id}, 2, 'snippet';
  ok $snippets->[1]{like_pattern},   'like pattern (ambiguous... could be 1 or 6)';
  ok $snippets->[1]{likelyness} > 0, 'likelyness';
  is $snippets->[2]{id},           3, 'snippet';
  is $snippets->[2]{like_pattern}, 5, 'like pattern';
  ok $snippets->[2]{likelyness} > 0, 'likelyness';
  is $snippets->[3]{id},           4, 'snippet';
  is $snippets->[3]{like_pattern}, 5, 'like pattern';
  ok $snippets->[3]{likelyness} > 0, 'likelyness';
  is $snippets->[4]{id},           5, 'snippet';
  is $snippets->[4]{like_pattern}, 2, 'like pattern';
  ok $snippets->[4]{likelyness} > 0, 'likelyness';
  is $snippets->[5]{id},           6, 'snippet';
  is $snippets->[5]{like_pattern}, 6, 'like pattern';
  ok $snippets->[5]{likelyness} > 0, 'likelyness';
  is $snippets->[6], undef, 'no more snippets';
};

subtest 'Details after reindexing' => sub {
  $t->get_ok('/login')->status_is(302)->header_is(Location => '/');

  $t->get_ok('/reviews/meta/1')->status_is(200)->json_has('/package_shortname')
    ->json_like('/package_license/name', qr!Artistic-2.0!)->json_is('/package_license/spdx', 1)
    ->json_like('/package_version',      qr!7\.25!)->json_like('/package_summary', qr!Real-time web framework!)
    ->json_like('/package_group',        qr!Development/Libraries/Perl!)
    ->json_like('/package_url',          qr!http://search\.cpan\.org/dist/Mojolicious/!)->json_like('/state', qr!new!);

  $t->get_ok('/reviews/calc_report/1')->header_like(Vary => qr/Accept-Encoding/)->status_is(200)
    ->element_exists('#license-chart')->element_exists('#unmatched-files')->text_is('#unmatched-count', '4')
    ->text_like('#unmatched-files tr:nth-of-type(1) td:nth-of-type(1) a',                qr!Mojolicious-7.25/LICENSE!)
    ->text_like('#unmatched-files tr:nth-of-type(1) td:nth-of-type(2) b',                qr![0-9.]+%!)
    ->text_like('#unmatched-files tr:nth-of-type(1) td:nth-of-type(2)',                  qr!similarity to!)
    ->text_like('#unmatched-files tr:nth-of-type(1) td:nth-of-type(2) b:nth-of-type(2)', qr!Snippet!)
    ->text_like('#unmatched-files tr:nth-of-type(1) td:nth-of-type(3) .estimated-risk',  qr!Risk 7!)
    ->text_like('#unmatched-files tr:nth-of-type(2) td:nth-of-type(1) a', qr!Mojolicious-7.25/lib/Mojolicious.pm!)
    ->text_like('#unmatched-files tr:nth-of-type(2) td:nth-of-type(2) b', qr![0-9.]+%!)
    ->text_like('#unmatched-files tr:nth-of-type(2) td:nth-of-type(2)',   qr!similarity to!)
    ->text_like('#unmatched-files tr:nth-of-type(2) td:nth-of-type(2) b:nth-of-type(2)', qr!Apache-2.0!)
    ->text_like('#unmatched-files tr:nth-of-type(2) td:nth-of-type(3) .estimated-risk',  qr!Risk 7!)
    ->text_like('#unmatched-files tr:nth-of-type(3) td:nth-of-type(1) a',                qr!Mojolicious-7.25/Changes!)
    ->text_like('#unmatched-files tr:nth-of-type(3) td:nth-of-type(2) b',                qr!100%!)
    ->text_like('#unmatched-files tr:nth-of-type(3) td:nth-of-type(2)',                  qr!similarity to!)
    ->text_like('#unmatched-files tr:nth-of-type(3) td:nth-of-type(2) b:nth-of-type(2)', qr!Snippet!)
    ->text_like('#unmatched-files tr:nth-of-type(3) td:nth-of-type(3) .estimated-risk',  qr!Risk 5!)
    ->text_like('#unmatched-files tr:nth-of-type(4) td:nth-of-type(1) a',                qr!perl-Mojolicious.changes!)
    ->text_like('#unmatched-files tr:nth-of-type(4) td:nth-of-type(2) b',                qr!100%!)
    ->text_like('#unmatched-files tr:nth-of-type(4) td:nth-of-type(2)',                  qr!similarity to!)
    ->text_like('#unmatched-files tr:nth-of-type(4) td:nth-of-type(2) b:nth-of-type(2)', qr!Snippet!)
    ->text_like('#unmatched-files tr:nth-of-type(4) td:nth-of-type(3) .estimated-risk',  qr!Risk 5!)
    ->element_exists('#risk-5')->text_like('#risk-5 li', qr!Apache-2.0!)
    ->text_like('#risk-5 li ul li:nth-of-type(1) a', qr!Mojolicious-7.25/lib/Mojolicious.pm!)
    ->text_like('#risk-5 li ul li:nth-of-type(2) a', qr!Mojolicious-7.25/lib/Mojolicious/resources/public/!);
  $t->element_exists('#emails')->text_like('#emails tr td', qr!coolo\@suse\.com!)->element_exists('#urls')
    ->text_like('#urls tr td', qr!http://mojolicious.org!);

  $t->get_ok('/logout')->status_is(302)->header_is(Location => '/');
};

subtest 'Manual review' => sub {
  $t->get_ok('/login')->status_is(302)->header_is(Location => '/');

  $t->post_ok('/reviews/review_package/1' => form => {comment => 'Test review', acceptable => 'Good Enough'})
    ->status_is(200)->text_like('#content a', qr!perl-Mojolicious!)->text_like('#content b', qr!acceptable!);

  $t->get_ok('/reviews/meta/1')->status_is(200)->json_has('/package_shortname')
    ->json_like('/package_license/name', qr!Artistic-2.0!)->json_is('/package_license/spdx', 1)
    ->json_like('/package_version',      qr!7\.25!)->json_like('/package_summary', qr!Real-time web framework!)
    ->json_like('/package_group',        qr!Development/Libraries/Perl!)
    ->json_like('/package_url', qr!http://search\.cpan\.org/dist/Mojolicious/!)->json_like('/state', qr!acceptable!)
    ->json_like('/result',      qr/Test review/);

  $t->get_ok('/reviews/calc_report/1')->status_is(200)->element_exists('#license-chart')
    ->element_exists('#unmatched-files')->text_is('#unmatched-count', '4')
    ->text_like('#unmatched-files tr:nth-of-type(2) td:nth-of-type(1) a', qr!Mojolicious-7.25/lib/Mojolicious.pm!)
    ->text_like('#unmatched-files tr:nth-of-type(2) td:nth-of-type(2) b', qr![0-9.]+%!)
    ->text_like('#unmatched-files tr:nth-of-type(2) td:nth-of-type(2)',   qr!similarity to!)
    ->text_like('#unmatched-files tr:nth-of-type(2) td:nth-of-type(2) b:nth-of-type(2)', qr!Apache-2.0!)
    ->text_like('#unmatched-files tr:nth-of-type(2) td:nth-of-type(3) .estimated-risk',  qr!Risk 7!)
    ->element_exists('#risk-5');
  $t->element_exists('#emails')->text_like('#emails tr td', qr!coolo\@suse\.com!)->element_exists('#urls')
    ->text_like('#urls tr td', qr!http://mojolicious.org!);

  $t->get_ok('/pagination/reviews/recent')->json_is('/start', 1)->json_is('/end', 1)->json_is('/total', 1)
    ->json_is('/page/0/id', 1)->json_like('/page/0/checksum', qr/Artistic/)->json_is('/page/0/external_link', 'mojo#1')
    ->json_is('/page/0/login',  'tester')->json_is('/page/0/name', 'perl-Mojolicious')->json_is('/page/0/priority', 5)
    ->json_is('/page/0/result', 'Test review')->json_is('/page/0/state', 'acceptable')
    ->json_has('/page/0/created_epoch')->json_has('/page/0/imported_epoch')->json_has('/page/0/indexed_epoch')
    ->json_has('/page/0/unpacked_epoch')->json_is('/page/0/active_jobs' => 0)->json_is('/page/0/failed_jobs' => 0)
    ->json_is('/page/0/unresolved_matches' => 6)->json_hasnt('/page/1');

  $t->get_ok('/pagination/reviews/recent?unresolvedMatches=true')->json_is('/start', 1)->json_is('/end', 1)
    ->json_is('/total', 1)->json_is('/page/0/unresolved_matches' => 6);

  $t->get_ok('/logout')->status_is(302)->header_is(Location => '/');
};

subtest 'Final JSON report' => sub {
  $t->get_ok('/login')->status_is(302)->header_is(Location => '/');

  $t->get_ok('/reviews/calc_report/1.json')->status_is(200);
  ok my $json = $t->tx->res->json, 'JSON response';

  ok my $pkg = $json->{package}, 'package';
  is $pkg->{id},   1,                  'id';
  is $pkg->{name}, 'perl-Mojolicious', 'name';
  like $pkg->{checksum}, qr!Artistic-2.0-7!, 'checksum';
  is $pkg->{login},  'tester',      'login';
  is $pkg->{state},  'acceptable',  'state';
  is $pkg->{result}, 'Test review', 'result';

  ok my $report = $json->{report}, 'report';
  is $report->{emails}[0][0], 'coolo@suse.com', 'right email';
  ok $report->{emails}[0][1], 'multiple matches';
  is $report->{urls}[0][0], 'http://mojolicious.org', 'right URL';
  ok $report->{urls}[0][1], 'multiple matches';

  ok my $missed_files = $report->{missed_files}, 'missed files';
  is $missed_files->[0]{id},      9,         'id';
  is $missed_files->[0]{license}, 'Snippet', 'license';
  ok $missed_files->[0]{match} > 0, 'match';
  is $missed_files->[0]{max_risk}, 7, 'max risk';
  ok $missed_files->[0]{name}, 'name';
  is $missed_files->[1]{id},      12,           'id';
  is $missed_files->[1]{license}, 'Apache-2.0', 'license';
  ok $missed_files->[1]{match} > 0, 'match';
  is $missed_files->[1]{max_risk}, 7, 'max risk';
  ok $missed_files->[1]{name}, 'name';
  is $missed_files->[2]{id},       8,         'id';
  is $missed_files->[2]{license},  'Snippet', 'license';
  is $missed_files->[2]{match},    100,       'match';
  is $missed_files->[2]{max_risk}, 5,         'max risk';
  ok $missed_files->[2]{name}, 'name';
  is $missed_files->[3]{id},      14,        'id';
  is $missed_files->[3]{license}, 'Snippet', 'license';
  ok $missed_files->[3]{match} > 0, 'match';
  is $missed_files->[3]{max_risk}, 5, 'max risk';
  ok $missed_files->[3]{name}, 'name';
  is $missed_files->[4], undef, 'no more missed files';

  ok $report->{files}, 'files';
  ok my $licenses = $report->{licenses},       'licenses';
  ok my $apache   = $licenses->{'Apache-2.0'}, 'Apache';
  is $apache->{name}, 'Apache-2.0', 'name';
  is $apache->{risk}, 5,            'risk';

  $t->get_ok('/logout')->status_is(302)->header_is(Location => '/');
};

done_testing;

