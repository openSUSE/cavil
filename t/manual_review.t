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
use Mojo::Pg;
use Cavil::Util qw(SNIPPET_SCORE_VERSION);
use Mojo::Util  qw(url_escape);
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
    $t->post_ok('/ignored-files' => form => {glob => 'does/not/exist/*'})->status_is(200)->json_is('ok');
    is $t->app->pg->db->select('ignored_files')->hashes->to_array->[0]{glob}, 'does/not/exist/*', 'glob added';

    $t->get_ok('/pagination/files/ignored')
      ->status_is(200)
      ->json_is('/start',     1)
      ->json_is('/end',       1)
      ->json_is('/total',     1)
      ->json_is('/page/0/id', 1)
      ->json_like('/page/0/glob', qr/does/)
      ->json_is('/page/0/login', 'tester')
      ->json_has('/page/0/created_epoch')
      ->json_hasnt('/page/1');
    $t->get_ok('/pagination/files/ignored?filter=does')
      ->status_is(200)
      ->json_is('/start',     1)
      ->json_is('/end',       1)
      ->json_is('/total',     1)
      ->json_is('/page/0/id', 1)
      ->json_like('/page/0/glob', qr/does/)
      ->json_hasnt('/page/1');
    $t->get_ok('/pagination/files/ignored?filter=whatever')
      ->status_is(200)
      ->json_is('/start', 1)
      ->json_is('/end',   0)
      ->json_is('/total', 0)
      ->json_hasnt('/page/1');

    my $logs = $t->app->log->capture('trace');
    $t->delete_ok('/ignored-files/1')->status_is(200)->json_is('ok');
    $t->delete_ok('/ignored-files/1')->status_is(400)->json_is({error => 'Glob does not exist'});
    like $logs, qr!User "tester" removed glob "does/not/exist/\*"!, 'right message';

    $t->get_ok('/logout')->status_is(302)->header_is(Location => '/');
  };
};

subtest 'Details after import (indexing in progress)' => sub {
  $t->get_ok('/login')->status_is(302)->header_is(Location => '/');

  $t->get_ok('/reviews/meta/1')
    ->status_is(200)
    ->json_is('/package_name',   'perl-Mojolicious')
    ->json_is('/state',          'new')
    ->json_is('/unpacked_files', undef);

  $t->json_is('/errors', [])->json_is('/warnings', []);

  $t->get_ok('/reviews/report/1')->status_is(408)->content_like(qr/not indexed/);
  $t->get_ok('/reviews/report_details/1')
    ->status_is(408)
    ->json_is('/error', 'not indexed')
    ->json_is('/stage', 2)
    ->json_has('/imported_epoch')
    ->json_is('/unpacked_epoch', undef)
    ->json_is('/indexed_epoch',  undef);
  $t->get_ok('/reviews/fetch_source/1')->status_is(404)->json_is('/error', 'unknown file');

  $t->get_ok('/logout')->status_is(302)->header_is(Location => '/');
};

# Unpack and index
$t->app->minion->enqueue(unpack => [1]);
$t->app->minion->perform_jobs;

subtest 'Details after indexing' => sub {
  $t->get_ok('/login')->status_is(302)->header_is(Location => '/');

  $t->get_ok('/reviews/meta/1')
    ->status_is(200)
    ->json_like('/package_license/name', qr!Artistic-2.0!)
    ->json_is('/package_license/spdx', 1)
    ->json_like('/package_version',        qr!7\.25!)
    ->json_like('/package_summary',        qr!Real-time web framework!)
    ->json_like('/package_group',          qr!Development/Libraries/Perl!)
    ->json_like('/package_url',            qr!http://search\.cpan\.org/dist/Mojolicious/!)
    ->json_like('/state',                  qr!new!)
    ->json_like('/legal_review_notices/0', qr!Upstream project maintained by SUSE employee!)
    ->json_is('/unpacked_files', 339)
    ->json_is('/unpacked_size',  '2.5MiB');

  $t->json_like('/package_files/0/file',       qr/perl-Mojolicious\.spec/)
    ->json_like('/package_files/0/licenses/0', qr/Artistic-2.0/)
    ->json_like('/package_files/0/version',    qr/7\.25/)
    ->json_like('/package_files/0/sources/0',  qr/http:\/\/www\.cpan\.org/)
    ->json_like('/package_files/0/summary',    qr/Real-time web framework/)
    ->json_like('/package_files/0/url',        qr/http:\/\//)
    ->json_like('/package_files/0/group',      qr/Development\/Libraries\/Perl/);

  $t->json_is('/errors', [])->json_is('/warnings', []);

  $t->get_ok('/logout')->status_is(302)->header_is(Location => '/');
};

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

  $t->get_ok('/reviews/meta/1')
    ->status_is(200)
    ->json_like('/package_license/name', qr!Artistic-2.0!)
    ->json_is('/package_license/spdx', 1)
    ->json_like('/package_version', qr!7\.25!)
    ->json_like('/package_summary', qr!Real-time web framework!)
    ->json_like('/package_group',   qr!Development/Libraries/Perl!)
    ->json_like('/package_url',     qr!http://search\.cpan\.org/dist/Mojolicious/!)
    ->json_like('/state',           qr!new!);

  $t->get_ok('/reviews/report_details/1')
    ->status_is(200)
    ->json_like('/emails/0/0', qr!coolo\@suse\.com!)
    ->json_like('/urls/0/0',   qr!http://mojolicious.org!)
    ->json_has('/files/0/id')
    ->json_has('/files/0/path')
    ->json_like('/files/0/file_url', qr!/reviews/file_view/1/!)
    ->json_has('/chart/licenses')
    ->json_has('/chart/num-files')
    ->json_has('/chart/colours')
    ->json_has('/risks');

  subtest 'Expanded file limit' => sub {
    my $db       = $t->app->pg->db;
    my $row      = $db->select('bot_reports', 'ldig_report', {package => 1})->hash;
    my $original = $row->{ldig_report};
    my $dig      = Mojo::JSON::from_json($original);
    my $fpid     = 999998;
    for my $id (9100 .. 9249) {
      $dig->{files}{$id}           = "fake/missed/missed$id.txt";
      $dig->{missed_snippets}{$id} = [[1, 1, $id, 'deadbeef', 0.1, $fpid]];
      $dig->{missed_files}{$id}    = [9, 0.1, 'Keyword', undef];
    }
    $db->update('bot_reports', {ldig_report => Mojo::JSON::to_json($dig)}, {package => 1});

    $t->get_ok('/reviews/report_details/1')->status_is(200);
    my $details = $t->tx->res->json;
    my $expand  = grep { $_->{expand} } @{$details->{files}};
    cmp_ok $expand,                     '<=', 100,     'expand=true count capped at max_expanded_files';
    cmp_ok scalar @{$details->{files}}, '>',  $expand, 'remaining files are sent collapsed';
    is $details->{max_expanded_files}, 100, 'max_expanded_files reported in response';
    cmp_ok $details->{hidden_inline_previews}, '>', 0, 'hidden_inline_previews counts missed files past the inline cap';
    is $details->{hidden_inline_previews}, scalar(@{$details->{missed_files}}) - $expand,
      'hidden_inline_previews equals total missed files minus inline-expanded ones';

    $db->update('bot_reports', {ldig_report => $original}, {package => 1});
  };

  $t->get_ok('/reviews/fetch_source/1')
    ->status_is(200)
    ->content_type_is('application/json;charset=UTF-8')
    ->json_like('/source/name', qr/perl-Mojolicious/)
    ->json_has('/source/lines/0');
  $t->get_ok('/reviews/fetch_source/1.json')
    ->status_is(200)
    ->content_type_is('application/json;charset=UTF-8')
    ->json_like('/source/name', qr/perl-Mojolicious/);

  subtest 'Vue file browser metadata' => sub {
    $t->get_ok('/reviews/file_view_meta/1/')
      ->status_is(200)
      ->content_type_is('application/json;charset=UTF-8')
      ->json_is('/kind',         'directory')
      ->json_is('/package/name', 'perl-Mojolicious')
      ->json_has('/entries/0/name')
      ->json_has('/breadcrumbs/0/url');

    $t->get_ok('/reviews/report_details/1')->status_is(200);
    my $path = $t->tx->res->json->{files}[0]{path};
    my $url  = join '/', map { url_escape $_ } split '/', $path;
    $t->get_ok("/reviews/file_view_meta/1/$url")
      ->status_is(200)
      ->content_type_is('application/json;charset=UTF-8')
      ->json_is('/kind',            'file')
      ->json_is('/source/filename', $path)
      ->json_has('/source/id')
      ->json_has('/source/lines/0/0')
      ->json_has('/source/lines/0/1/risk')
      ->json_has('/source/lines/0/2');

    $t->get_ok('/reviews/file_view_meta/1/Mojolicious-7.25/lib/Mojolicious.pm')->status_is(200);
    my $source = $t->tx->res->json->{source};
    cmp_ok scalar @{$source->{lines}}, '>', 1000, 'file browser returns the whole source file';
    ok grep({ $_->[1]{pid} } @{$source->{lines}}), 'whole source file keeps pattern annotations';

    local $t->app->config->{max_file_browser_size} = 10;
    my $package = $t->app->packages->find(1);
    my $large
      = $cavil_test->checkout_dir->child('perl-Mojolicious', $package->{checkout_dir}, '.unpacked', 'large.txt');
    $large->spurt("This file is too large for the configured browser limit.\n");
    $t->get_ok('/reviews/file_view_meta/1/large.txt')
      ->status_is(200)
      ->json_is('/kind',             'file')
      ->json_is('/source/filename',  'large.txt')
      ->json_is('/source/oversized', 1)
      ->json_is('/source/maxSize',   10)
      ->json_has('/source/sizeLabel')
      ->json_has('/source/maxSizeLabel')
      ->json_hasnt('/source/lines');

    $t->get_ok('/reviews/file_view_meta/1/does-not-exist')->status_is(404);
    $t->get_ok('/reviews/file_view_meta/1/../COPYING')->status_is(400);
  };

  $t->get_ok('/logout')->status_is(302)->header_is(Location => '/');
};

subtest 'JSON report' => sub {
  $t->get_ok('/login')->status_is(302)->header_is(Location => '/');

  $t->get_ok('/reviews/report/1.json')->header_like(Vary => qr/Accept-Encoding/)->status_is(200);
  ok my $json = $t->tx->res->json, 'JSON response';

  ok my $pkg = $json->{package}, 'package';
  is $pkg->{id},   1,                  'id';
  is $pkg->{name}, 'perl-Mojolicious', 'name';
  like $pkg->{checksum}, qr!Artistic-2.0-9!, 'checksum';
  is $pkg->{login},  undef,                                                                 'no login';
  is $pkg->{state},  'new',                                                                 'state';
  is $pkg->{notice}, 'Manual review is required because no previous reports are available', 'requires manual review';

  ok my $report = $json->{report}, 'report';
  is $report->{emails}[0][0], 'coolo@suse.com', 'right email';
  ok $report->{emails}[0][1], 'multiple matches';
  is $report->{urls}[0][0], 'http://mojolicious.org', 'right URL';
  ok $report->{urls}[0][1], 'multiple matches';

  ok my $missed_files = $report->{missed_files}, 'missed files';
  is $missed_files->[0]{id},       1,         'id';
  is $missed_files->[0]{license},  'Keyword', 'license';
  is $missed_files->[0]{match},    0,         'no match';
  is $missed_files->[0]{max_risk}, 9,         'max risk';
  ok $missed_files->[0]{name}, 'name';
  is $missed_files->[1]{id},       2,         'id';
  is $missed_files->[1]{license},  'Keyword', 'license';
  is $missed_files->[1]{match},    0,         'no match';
  is $missed_files->[1]{max_risk}, 9,         'max risk';
  ok $missed_files->[1]{name}, 'name';
  is $missed_files->[2]{id},       5,         'id';
  is $missed_files->[2]{license},  'Keyword', 'license';
  is $missed_files->[2]{match},    0,         'no match';
  is $missed_files->[2]{max_risk}, 9,         'max risk';
  ok $missed_files->[2]{name}, 'name';
  is $missed_files->[3]{id},       7,         'id';
  is $missed_files->[3]{license},  'Keyword', 'license';
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

  subtest 'Index jobs are deduplicated' => sub {
    $t->app->packages->reindex(1);
    is $t->app->minion->jobs({tasks => ['index'], states => ['inactive']})->total, 1, 'one index job';
    $t->app->packages->reindex(1);
    is $t->app->minion->jobs({tasks => ['index'], states => ['inactive']})->total, 1, 'one index job';
  };

  $t->get_ok('/reviews/report/1')->status_is(408)->content_like(qr/package being processed/);
  $t->app->minion->perform_jobs;

  $t->get_ok('/logout')->status_is(302)->header_is(Location => '/');
};

# Analyze scores a package's snippets as part of its run, so after (re)indexing every snippet carries
# a current-version score. In this tiny fixture corpus the required-phrase gate (covered in
# t/patterns_similarity.t) leaves none with a confident license, but they are no longer unscored - the
# score version is stamped, which is what unblocks fold-in once a real match is found.
subtest 'Snippets after reindexing' => sub {
  my $snippets = $t->app->pg->db->select('snippets', '*', {}, {order_by => 'id'})->hashes->to_array;
  is scalar(@$snippets), 6, 'six snippets';
  for my $snippet (@$snippets) {
    is $snippet->{score_version}, SNIPPET_SCORE_VERSION, "snippet $snippet->{id} is scored to the current version";
    is $snippet->{like_pattern},  undef,                 'no confident license in this small corpus';
    ok !$snippet->{likelyness}, 'and no likelyness';
  }
};

subtest 'Details after reindexing' => sub {
  $t->get_ok('/login')->status_is(302)->header_is(Location => '/');

  $t->get_ok('/reviews/meta/1')
    ->status_is(200)
    ->json_has('/package_shortname')
    ->json_like('/package_license/name', qr!Artistic-2.0!)
    ->json_is('/package_license/spdx', 1)
    ->json_like('/package_version', qr!7\.25!)
    ->json_like('/package_summary', qr!Real-time web framework!)
    ->json_like('/package_group',   qr!Development/Libraries/Perl!)
    ->json_like('/package_url',     qr!http://search\.cpan\.org/dist/Mojolicious/!)
    ->json_like('/state',           qr!new!);

  $t->get_ok('/reviews/report_details/1')
    ->status_is(200)
    ->json_like('/emails/0/0', qr!coolo\@suse\.com!)
    ->json_like('/urls/0/0',   qr!http://mojolicious.org!)
    ->json_has('/chart/licenses')
    ->json_has('/chart/num-files')
    ->json_has('/chart/colours')
    ->json_is('/incompatible_licenses',   [])
    ->json_is('/missed_files/0/name',     'Mojolicious-7.25/Changes')
    ->json_is('/missed_files/0/license',  'Keyword')
    ->json_is('/missed_files/0/max_risk', 9)
    ->json_like('/missed_files/0/license_html', qr!Keyword!)
    ->json_is('/missed_files/1/name',     'Mojolicious-7.25/LICENSE')
    ->json_is('/missed_files/1/license',  'Keyword')
    ->json_is('/missed_files/1/max_risk', 9)
    ->json_is('/missed_files/2/name',     'Mojolicious-7.25/lib/Mojolicious.pm')
    ->json_is('/missed_files/2/max_risk', 9)
    ->json_is('/missed_files/3/name',     'perl-Mojolicious.changes')
    ->json_is('/missed_files/3/max_risk', 9)
    ->json_is('/missed_files/4',          undef)
    ->json_is('/risks/5/0/name',          'Apache-2.0')
    ->json_like('/risks/5/0/name_html', qr!Apache-2.0!);

  $t->get_ok('/logout')->status_is(302)->header_is(Location => '/');
};

subtest 'Manual review' => sub {
  $t->get_ok('/login')->status_is(302)->header_is(Location => '/');

  $t->post_ok('/reviews/review_package/1' => form => {comment => 'Test review', acceptable => 'Good Enough'})
    ->status_is(200)
    ->text_like('#content a', qr!perl-Mojolicious!)
    ->text_like('#content b', qr!acceptable!);

  $t->get_ok('/reviews/meta/1')
    ->status_is(200)
    ->json_has('/package_shortname')
    ->json_like('/package_license/name', qr!Artistic-2.0!)
    ->json_is('/package_license/spdx', 1)
    ->json_like('/package_version', qr!7\.25!)
    ->json_like('/package_summary', qr!Real-time web framework!)
    ->json_like('/package_group',   qr!Development/Libraries/Perl!)
    ->json_like('/package_url',     qr!http://search\.cpan\.org/dist/Mojolicious/!)
    ->json_like('/state',           qr!acceptable!)
    ->json_like('/result',          qr/Test review/);

  $t->get_ok('/reviews/report_details/1')
    ->status_is(200)
    ->json_like('/emails/0/0', qr!coolo\@suse\.com!)
    ->json_like('/urls/0/0',   qr!http://mojolicious.org!)
    ->json_has('/chart/licenses')
    ->json_is('/missed_files/1/name',     'Mojolicious-7.25/LICENSE')
    ->json_is('/missed_files/1/license',  'Keyword')
    ->json_is('/missed_files/1/max_risk', 9)
    ->json_has('/risks/5');

  $t->get_ok('/pagination/reviews/recent')
    ->json_is('/start',     1)
    ->json_is('/end',       1)
    ->json_is('/total',     1)
    ->json_is('/page/0/id', 1)
    ->json_like('/page/0/checksum', qr/Artistic/)
    ->json_is('/page/0/external_link', 'mojo#1')
    ->json_is('/page/0/login',         'tester')
    ->json_is('/page/0/name',          'perl-Mojolicious')
    ->json_is('/page/0/priority',      5)
    ->json_is('/page/0/result',        'Test review')
    ->json_is('/page/0/state',         'acceptable')
    ->json_has('/page/0/created_epoch')
    ->json_has('/page/0/imported_epoch')
    ->json_has('/page/0/indexed_epoch')
    ->json_has('/page/0/unpacked_epoch')
    ->json_is('/page/0/active_jobs'        => 0)
    ->json_is('/page/0/failed_jobs'        => 0)
    ->json_is('/page/0/unresolved_matches' => 6)
    ->json_hasnt('/page/1');

  $t->get_ok('/pagination/reviews/recent?unresolvedMatches=true')
    ->json_is('/start', 1)
    ->json_is('/end',   1)
    ->json_is('/total', 1)
    ->json_is('/page/0/unresolved_matches' => 6);

  $t->get_ok('/logout')->status_is(302)->header_is(Location => '/');
};

subtest 'Final JSON report' => sub {
  $t->get_ok('/login')->status_is(302)->header_is(Location => '/');

  $t->get_ok('/reviews/report/1.json')->status_is(200);
  ok my $json = $t->tx->res->json, 'JSON response';

  ok my $pkg = $json->{package}, 'package';
  is $pkg->{id},   1,                  'id';
  is $pkg->{name}, 'perl-Mojolicious', 'name';
  like $pkg->{checksum}, qr!Artistic-2.0-9!, 'checksum';
  is $pkg->{login},  'tester',      'login';
  is $pkg->{state},  'acceptable',  'state';
  is $pkg->{result}, 'Test review', 'result';

  ok my $report = $json->{report}, 'report';
  is $report->{emails}[0][0], 'coolo@suse.com', 'right email';
  ok $report->{emails}[0][1], 'multiple matches';
  is $report->{urls}[0][0], 'http://mojolicious.org', 'right URL';
  ok $report->{urls}[0][1], 'multiple matches';

  ok my $missed_files = $report->{missed_files}, 'missed files';
  is $missed_files->[0]{id},       8,         'id';
  is $missed_files->[0]{license},  'Keyword', 'license';
  is $missed_files->[0]{match},    0,         'no match';
  is $missed_files->[0]{max_risk}, 9,         'max risk';
  ok $missed_files->[0]{name}, 'name';
  is $missed_files->[1]{id},       9,         'id';
  is $missed_files->[1]{license},  'Keyword', 'license';
  is $missed_files->[1]{match},    0,         'no match';
  is $missed_files->[1]{max_risk}, 9,         'max risk';
  ok $missed_files->[1]{name}, 'name';
  is $missed_files->[2]{id},       12,        'id';
  is $missed_files->[2]{license},  'Keyword', 'license';
  is $missed_files->[2]{match},    0,         'no match';
  is $missed_files->[2]{max_risk}, 9,         'max risk';
  ok $missed_files->[2]{name}, 'name';
  is $missed_files->[3]{id},       14,        'id';
  is $missed_files->[3]{license},  'Keyword', 'license';
  is $missed_files->[3]{match},    0,         'no match';
  is $missed_files->[3]{max_risk}, 9,         'max risk';
  ok $missed_files->[3]{name}, 'name';
  is $missed_files->[4], undef, 'no more missed files';

  ok $report->{files}, 'files';
  ok my $licenses = $report->{licenses},       'licenses';
  ok my $apache   = $licenses->{'Apache-2.0'}, 'Apache';
  is $apache->{name}, 'Apache-2.0', 'name';
  is $apache->{spdx}, 'Apache-2.0', 'spdx';
  is $apache->{risk}, 5,            'risk';

  $t->get_ok('/logout')->status_is(302)->header_is(Location => '/');
};

done_testing;
