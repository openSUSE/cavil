# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Mojo::Base -strict;

use FindBin;
use lib "$FindBin::Bin/lib";

use Test::More;
use Test::Mojo;
use Cavil::Test;
use Mojo::File qw(path);
use Mojo::JSON qw(false true);

plan skip_all => 'set TEST_ONLINE to enable this test' unless $ENV{TEST_ONLINE};

my $cavil_test = Cavil::Test->new(online => $ENV{TEST_ONLINE}, schema => 'custom_review_test');
my $t          = Test::Mojo->new(Cavil => $cavil_test->default_config);
$cavil_test->mojo_fixtures($t->app);

# Modify spec files to trigger a few special cases
my $pkg = $t->app->packages->find(1);
my $dir = path($cavil_test->checkout_dir, 'perl-Mojolicious', $pkg->{checkout_dir});
$dir->child('perl-Mojolicious-whatever.spec')->spew(<<EOF);
License: MIT
Description: Just a test package
Version: 1.2.3
Summary: Fake summary
License: BSD
License: Artistic2
Group: Fake group
EOF
my $spec    = $dir->child('perl-Mojolicious.spec');
my $content = $spec->slurp;
$content =~ s/Artistic-2.0/Fake-Artistic/g;
$spec->spew($content);

subtest 'Details after import (with login)' => sub {
  $t->get_ok('/login')->status_is(302)->header_is(Location => '/');

  $t->get_ok('/reviews/meta/1')->status_is(200);

  $t->get_ok('/logout')->status_is(302)->header_is(Location => '/');
};

# Unpack and index
$t->app->minion->enqueue(unpack => [1]);
$t->app->minion->perform_jobs;


subtest 'Details after indexing' => sub {
  $t->get_ok('/login')->status_is(302)->header_is(Location => '/');

  $t->get_ok('/reviews/meta/1')
    ->status_is(200)
    ->json_is('/package_type',           'spec')
    ->json_is('/declarations/0/file',    'perl-Mojolicious.spec')
    ->json_is('/declarations/0/license', 'Fake-Artistic')
    ->json_is('/declarations/0/spdx',    false)
    ->json_is('/declarations/1/file',    'perl-Mojolicious-whatever.spec')
    ->json_is('/declarations/1/license', 'MIT')
    ->json_hasnt('/declarations/2')
    ->json_like('/package_shortname', qr/\w+/)
    ->json_like('/package_version',   qr!7\.25!)
    ->json_like('/package_summary',   qr!Real-time web framework!)
    ->json_like('/package_url',       qr!http://search\.cpan\.org/dist/Mojolicious/!)
    ->json_like('/state',             qr!new!)
    ->json_is('/incomplete_checkout', []);

  my $mcp = $t->app->build_controller->mcp_report(1);
  like $mcp, qr/^Declared-License: Fake-Artistic \(from perl-Mojolicious\.spec\) \(not a valid SPDX expression\)$/m,
    'invalid declared license marked';
  like $mcp,   qr/^\* `perl-Mojolicious-whatever\.spec` \(spec\): 1\.2\.3, MIT$/m, 'second declaration listed';
  unlike $mcp, qr/Checkout May Be Incomplete/,                                     'no incomplete checkout section';

  $t->get_ok('/reviews/report_artifacts/1')
    ->status_is(200)
    ->json_like('/emails/values/0/0',     qr!coolo\@suse\.com!)
    ->json_like('/urls/values/0/0',       qr!http://mojolicious.org!)
    ->json_like('/copyrights/values/0/0', qr!Copyright!);
  $t->get_ok('/reviews/report_details/1')
    ->status_is(200)
    ->json_has('/chart/licenses')
    ->json_is('/missed_files/0/max_risk', 9)
    ->json_has('/risks');

  $t->get_ok('/reviews/fetch_source/1')
    ->status_is(200)
    ->content_type_is('application/json;charset=UTF-8')
    ->json_like('/source/name', qr/perl-Mojolicious/);
  $t->get_ok('/reviews/fetch_source/1.json')
    ->status_is(200)
    ->content_type_is('application/json;charset=UTF-8')
    ->json_like('/source/name', qr/perl-Mojolicious/);

  $t->get_ok('/logout')->status_is(302)->header_is(Location => '/');
};

subtest 'JSON report' => sub {
  $t->get_ok('/login')->status_is(302)->header_is(Location => '/');

  $t->get_ok('/reviews/report/1.json')->header_like(Vary => qr/Accept-Encoding/)->status_is(200);
  ok my $json = $t->tx->res->json, 'JSON response';

  ok my $pkg = $json->{package}, 'package';
  is $pkg->{id},   1,                  'id';
  is $pkg->{name}, 'perl-Mojolicious', 'name';
  like $pkg->{checksum}, qr!Unknown-9!, 'checksum';
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

  # The rebuild is assembled beside the live report and only replaces it at the very end, so a consumer
  # asking for the report while it runs gets the previous one in full instead of being turned away
  $t->app->packages->reindex(1);
  $t->get_ok('/reviews/report/1.json')->status_is(200)->json_has('/report/licenses');
  $t->app->minion->perform_jobs;
  $t->get_ok('/reviews/report/1.json')->status_is(200)->json_has('/report/licenses');

  $t->get_ok('/logout')->status_is(302)->header_is(Location => '/');
};

subtest 'Manual review' => sub {
  $t->get_ok('/login')->status_is(302)->header_is(Location => '/');

  $t->post_ok('/reviews/review_package/1' => form => {comment => 'Test review', acceptable => 'Good Enough'})
    ->status_is(200)
    ->json_is('/ok',    1)
    ->json_is('/name',  'perl-Mojolicious')
    ->json_is('/state', 'acceptable');

  $t->get_ok('/reviews/meta/1')
    ->status_is(200)
    ->json_is('/package_type',           'spec')
    ->json_is('/declarations/0/file',    'perl-Mojolicious.spec')
    ->json_is('/declarations/0/license', 'Fake-Artistic')
    ->json_is('/declarations/0/spdx',    false)
    ->json_is('/declarations/1/file',    'perl-Mojolicious-whatever.spec')
    ->json_is('/declarations/1/license', 'MIT')
    ->json_hasnt('/declarations/2')
    ->json_like('/package_shortname', qr/\w+/)
    ->json_like('/package_version',   qr!7\.25!)
    ->json_like('/package_summary',   qr!Real-time web framework!)
    ->json_like('/package_url',       qr!http://search\.cpan\.org/dist/Mojolicious/!)
    ->json_like('/state',             qr!acceptable!)
    ->json_like('/result',            qr/Test review/);

  $t->get_ok('/reviews/report_artifacts/1')
    ->status_is(200)
    ->json_like('/emails/values/0/0',     qr!coolo\@suse\.com!)
    ->json_like('/urls/values/0/0',       qr!http://mojolicious.org!)
    ->json_like('/copyrights/values/0/0', qr!Copyright!);
  $t->get_ok('/reviews/report_details/1')
    ->status_is(200)
    ->json_has('/chart/licenses')
    ->json_is('/missed_files/1/name',     'Mojolicious-7.25/LICENSE')
    ->json_is('/missed_files/1/license',  'Keyword')
    ->json_is('/missed_files/1/max_risk', 9)
    ->json_has('/risks/5');

  $t->get_ok('/logout')->status_is(302)->header_is(Location => '/');
};

done_testing;
