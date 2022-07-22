# Copyright (C) 2021 SUSE LLC
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

plan skip_all => 'set TEST_ONLINE to enable this test' unless $ENV{TEST_ONLINE};

my $cavil_test = Cavil::Test->new(online => $ENV{TEST_ONLINE}, schema => 'custom_review_test');
my $t          = Test::Mojo->new(Cavil => $cavil_test->default_config);
$cavil_test->mojo_fixtures($t->app);

# Modify spec files to trigger a few special cases
my $pkg = $t->app->packages->find(1);
my $dir = path($cavil_test->checkout_dir, 'perl-Mojolicious', $pkg->{checkout_dir});
$dir->child('perl-Mojolicious-whatever.spec')->spurt(<<EOF);
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
$spec->spurt($content);

subtest 'Details after import (with login)' => sub {
  $t->get_ok('/login')->status_is(302)->header_is(Location => '/');

  $t->get_ok('/reviews/details/1')->status_is(200);

  $t->get_ok('/logout')->status_is(302)->header_is(Location => '/');
};

# Unpack and index
$t->app->minion->enqueue(unpack => [1]);
$t->app->minion->perform_jobs;


subtest 'Details after indexing' => sub {
  $t->get_ok('/login')->status_is(302)->header_is(Location => '/');

  $t->get_ok('/reviews/details/1')->status_is(200)->text_like('#pkg-license', qr!Fake-Artistic!)
    ->text_like('#pkg-license small', qr/\(not SPDX\)/)->text_like('#pkg-shortname', qr/\w+/)
    ->text_like('#num-spec-files a',  qr/2 files/)->text_like('#pkg-version', qr!7\.25!)
    ->text_like('#pkg-summary', qr!Real-time web framework!)->text_like('#pkg-group', qr!Development/Libraries/Perl!)
    ->text_like('#pkg-url a',   qr!http://search\.cpan\.org/dist/Mojolicious/!)->text_like('#pkg-state', qr!new!)
    ->element_exists('#pkg-review')->element_exists('#pkg-shortname')->element_exists('#pkg-review label[for=comment]')
    ->element_exists('#pkg-review textarea[name=comment]')->element_exists('#correct')->element_exists('#acceptable')
    ->element_exists('#unacceptable');

  $t->text_like('#spec-files table tr:nth-of-type(2) th',                         qr/perl-Mojolicious\.spec/)
    ->text_like('#spec-files table tr:nth-of-type(2) table tr td',                qr/Licenses/)
    ->text_like('#spec-files table tr:nth-of-type(2) table tr td:nth-of-type(2)', qr/Fake-Artistic/)
    ->text_like('#spec-files table tr:nth-of-type(2) table tr:nth-of-type(3) td', qr/Version/)
    ->text_like('#spec-files table tr:nth-of-type(2) table tr:nth-of-type(3) td:nth-of-type(2)', qr/7\.25/)
    ->text_like('#spec-files table tr:nth-of-type(2) table tr:nth-of-type(4) td',                qr/Summary/)
    ->text_like('#spec-files table tr:nth-of-type(2) table tr:nth-of-type(4) td:nth-of-type(2)',
    qr/Real-time web framework/)
    ->text_like('#spec-files table tr:nth-of-type(2) table tr:nth-of-type(5) td', qr/Group/)
    ->text_like('#spec-files table tr:nth-of-type(2) table tr:nth-of-type(5) td:nth-of-type(2)',
    qr/Development\/Libraries\/Perl/)->text_like('#spec-files table tr th', qr/perl-Mojolicious-whatever\.spec/)
    ->text_like('#spec-files table table tr td',                               qr/Licenses/)
    ->text_like('#spec-files table tr td:nth-of-type(2)',                      qr/MIT, BSD, Artistic2/)
    ->text_like('#spec-files table tr:nth-of-type(3) td',                      qr/Version/)
    ->text_like('#spec-files table tr:nth-of-type(3) td:nth-of-type(2)',       qr/1\.2\.3/)
    ->text_like('#spec-files table tr:nth-of-type(4) td',                      qr/Summary/)
    ->text_like('#spec-files table tr:nth-of-type(4) td:nth-of-type(2)',       qr/Fake summary/)
    ->text_like('#spec-files table table tr:nth-of-type(5) td',                qr/Group/)
    ->text_like('#spec-files table table tr:nth-of-type(5) td:nth-of-type(2)', qr/Fake group/);

  $t->text_like('#spec-errors p',     qr/Package file errors/)
    ->text_like('#spec-errors ul li', qr/Invalid SPDX license: Fake-Artistic/)->element_exists_not('#spec-warnings');

  $t->get_ok('/reviews/calc_report/1')->status_is(200)->element_exists('#license-chart')->element_exists('#emails')
    ->text_like('#emails tbody td', qr!coolo\@suse\.com!)->element_exists('#urls')
    ->text_like('#urls tbody td',   qr!http://mojolicious.org!);

  $t->get_ok('/reviews/fetch_source/1')->status_is(200)->content_type_isnt('application/json;charset=UTF-8')
    ->content_like(qr/perl-Mojolicious/);
  $t->get_ok('/reviews/fetch_source/1.json')->status_is(200)->content_type_is('application/json;charset=UTF-8')
    ->content_like(qr/perl-Mojolicious/);

  $t->get_ok('/logout')->status_is(302)->header_is(Location => '/');
};

subtest 'JSON report' => sub {
  $t->get_ok('/reviews/calc_report/1.json')->header_like(Vary => qr/Accept-Encoding/)->status_is(200);
  ok my $json = $t->tx->res->json, 'JSON response';

  ok my $pkg = $json->{package}, 'package';
  is $pkg->{id},   1,                  'id';
  is $pkg->{name}, 'perl-Mojolicious', 'name';
  like $pkg->{checksum}, qr!Error-9!, 'checksum';
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
};

# Reindex (with updated stats)
$t->app->minion->enqueue('pattern_stats');
$t->app->minion->perform_jobs;
$t->app->packages->reindex(1);
$t->get_ok('/reviews/calc_report/1')->status_is(408)->content_like(qr/package being processed/);
$t->app->minion->perform_jobs;

subtest 'Manual review' => sub {
  $t->get_ok('/login')->status_is(302)->header_is(Location => '/');

  $t->post_ok('/reviews/review_package/1' => form => {comment => 'Test review', acceptable => 'Good Enough'})
    ->status_is(200)->text_like('#content a', qr!perl-Mojolicious!)->text_like('#content b', qr!acceptable!);

  $t->get_ok('/reviews/details/1')->status_is(200)->text_like('#pkg-license', qr!Fake-Artistic!)
    ->text_like('#pkg-version', qr!7\.25!)->text_like('#pkg-summary', qr!Real-time web framework!)
    ->text_like('#pkg-group',   qr!Development/Libraries/Perl!)
    ->text_like('#pkg-url a',   qr!http://search\.cpan\.org/dist/Mojolicious/!)->text_like('#pkg-state', qr!acceptable!)
    ->element_exists('#pkg-review')->element_exists('#pkg-shortname')->element_exists('#pkg-review label[for=comment]')
    ->element_exists('#pkg-review textarea[name=comment]')->element_exists('#correct')->element_exists('#acceptable')
    ->element_exists('#unacceptable');

  $t->get_ok('/reviews/calc_report/1')->status_is(200)->element_exists('#license-chart')
    ->element_exists('#unmatched-files')->text_is('#unmatched-count', '4')
    ->text_like('#unmatched-files li:nth-of-type(2) a', qr!Mojolicious-7.25/lib/Mojolicious.pm!)
    ->text_like('#unmatched-files li:nth-of-type(2)',   qr![0-9.]+% Apache-2.0 - estimated risk 7!)
    ->element_exists('#risk-5');
  $t->element_exists('#emails')->text_like('#emails tbody td', qr!coolo\@suse\.com!)->element_exists('#urls')
    ->text_like('#urls tbody td', qr!http://mojolicious.org!);

  $t->get_ok('/logout')->status_is(302)->header_is(Location => '/');
};

done_testing;
