# Copyright (C) 2025 SUSE LLC
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

my $cavil_test = Cavil::Test->new(online => $ENV{TEST_ONLINE}, schema => 'incompatible_licenses_test');
my $t          = Test::Mojo->new(Cavil => $cavil_test->default_config);
$cavil_test->mojo_fixtures($t->app);

# Add patterns for known incompatible licenses
$t->app->pg->db->query('DELETE FROM license_patterns');
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

subtest 'GPL-2.0-only and Apache-2.0 detected as incompatible' => sub {
  $t->get_ok('/login')->status_is(302)->header_is(Location => '/');

  subtest 'Details after indexing' => sub {
    $t->get_ok('/reviews/meta/1')
      ->status_is(200)
      ->json_like('/package_license/name', qr!Artistic-2.0!)
      ->json_is('/package_license/spdx', 1)
      ->json_like('/package_version', qr!7\.25!)
      ->json_like('/package_summary', qr!Real-time web framework!)
      ->json_like('/package_group',   qr!Development/Libraries/Perl!)
      ->json_like('/package_url',     qr!http://search\.cpan\.org/dist/Mojolicious/!)
      ->json_like('/state',           qr!new!)
      ->json_is('/unpacked_files', 341)
      ->json_is('/unpacked_size',  '2.5MiB');

    $t->json_like('/package_files/0/file',       qr/perl-Mojolicious\.spec/)
      ->json_like('/package_files/0/licenses/0', qr/Artistic-2.0/)
      ->json_like('/package_files/0/version',    qr/7\.25/)
      ->json_like('/package_files/0/sources/0',  qr/http:\/\/www\.cpan\.org/)
      ->json_like('/package_files/0/summary',    qr/Real-time web framework/)
      ->json_like('/package_files/0/url',        qr/http:\/\//)
      ->json_like('/package_files/0/group',      qr/Development\/Libraries\/Perl/);

    $t->json_is('/errors', [])->json_is('/warnings', []);
  };

  subtest 'JSON report' => sub {
    $t->get_ok('/reviews/report/1.json')->status_is(200);
    ok my $json = $t->tx->res->json, 'JSON response';

    ok my $pkg = $json->{package}, 'package';
    is $pkg->{id},   1,                  'id';
    is $pkg->{name}, 'perl-Mojolicious', 'name';
    like $pkg->{checksum}, qr!Artistic-2.0-9!, 'checksum with elevated risk because of incompatible licenses';
    is $pkg->{state},  'new',                                                                 'state';
    is $pkg->{notice}, 'Manual review is required because no previous reports are available', 'requires manual review';

    ok my $report = $json->{report},                  'report';
    ok my $compat = $report->{license_compatibility}, 'license compatibility matrix';
    is_deeply $compat->{licenses}, ['Apache-2.0', 'GPL-2.0-only'], 'both licenses on the axes';

    # OSADL flags both directions as "No", verbatim.
    is $compat->{matrix}{'Apache-2.0'}{'GPL-2.0-only'}{compatibility}, 'No', 'Apache-2.0 <- GPL-2.0-only: No';
    is $compat->{matrix}{'GPL-2.0-only'}{'Apache-2.0'}{compatibility}, 'No', 'GPL-2.0-only <- Apache-2.0: No';
    like $compat->{matrix}{'Apache-2.0'}{'GPL-2.0-only'}{explanation},   qr/\S/, 'verbatim OSADL explanation present';
    unlike $compat->{matrix}{'Apache-2.0'}{'GPL-2.0-only'}{explanation}, qr/&quot;/, 'explanation entities decoded';

    $t->get_ok('/reviews/report_details/1')
      ->status_is(200)
      ->json_is('/license_compatibility/licenses',                                     ['Apache-2.0', 'GPL-2.0-only'])
      ->json_is('/license_compatibility/matrix/Apache-2.0/GPL-2.0-only/compatibility', 'No');
  };

  subtest 'Text report' => sub {
    $t->get_ok('/reviews/report/1.txt')->status_is(200);
    ok my $text = $t->tx->res->text, 'text response';
    like $text, qr/Elevated risk, package might contain incompatible licenses/,
      'text report warns about incompatible licenses';
    like $text, qr/OSADL compatibility matrix/, 'text report references the OSADL matrix';
    like $text, qr/Apache-2\.0: GPL-2\.0-only/, 'text report lists the mutually incompatible pair';
  };

  $t->get_ok('/logout')->status_is(302)->header_is(Location => '/');
};

done_testing;
