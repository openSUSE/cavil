# Copyright (C) 2023 SUSE LLC
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
use Mojolicious::Lite;
use Mojo::Util qw(decode);

plan skip_all => 'set TEST_ONLINE to enable this test' unless $ENV{TEST_ONLINE};

my $cavil_test = Cavil::Test->new(online => $ENV{TEST_ONLINE}, schema => 'spdx_test');
my $t          = Test::Mojo->new(Cavil => $cavil_test->default_config);
$cavil_test->spdx_fixtures($t->app);

subtest 'Unpack and index' => sub {
  ok !$t->app->packages->is_indexed(1), 'package has not been indexed';
  $t->app->minion->enqueue(unpack => [1]);
  $t->app->minion->perform_jobs;
  ok $t->app->packages->is_indexed(1), 'package has been indexed';
  is $t->app->minion->jobs({states => ['failed']})->total, 0, 'no failed jobs';
};

subtest 'Generate SPDX report' => sub {
  ok !$t->app->packages->has_spdx_report(1), 'package has no SPDX report';
  $t->app->minion->enqueue(spdx_report => [1]);
  $t->app->minion->perform_jobs;
  ok $t->app->packages->has_spdx_report(1), 'package has SPDX report';
  is $t->app->minion->jobs({states => ['failed']})->total, 0, 'no failed jobs';
};

subtest 'SPDX report contents' => sub {
  my $path = $t->app->packages->spdx_report_path(1);
  ok !-e "$path.tmp",      'SPDX temp file has been cleaned up';
  ok !-e "$path.refs.tmp", 'SPDX ref temp file has been cleaned up';
  my $report = decode('UTF-8', $path->slurp);

  subtest 'Creation Information' => sub {
    like $report, qr/SPDXVersion: SPDX-\d.\d/, 'has SPDXVersion';
    like $report, qr/DataLicense: CC0-1.0/,    'has DataLicense';
    like $report, qr/Creator: Tool: Cavil/,    'has Creator';
    like $report, qr/Created: .+T.+Z/,         'has Created';
  };

  subtest 'Package Information' => sub {
    like $report, qr/PackageName: perl-Mojolicious/,        'has PackageName';
    like $report, qr/PackageVersion: 7.25/,                 'has PackageVersion';
    like $report, qr/PackageLicenseDeclared: Artistic-2.0/, 'has PackageLicenseDeclared';
    like $report, qr/PackageDescription: Real-time/,        'has PackageDescription';
    like $report, qr/PackageHomePage: http/,                'has PackageHomePage';
    like $report, qr/PackageChecksum: MD5: .+/,             'has PackageCheckSum';
  };

  subtest 'File Information' => sub {
    like $report, qr/FileName: \.\/Mojolicious-7.25\/\.perltidyrc/, 'has .perltidyrc file';

    like $report, qr/FileName: \.\/Mojolicious-7.25\/Changes/,                      'has Changes file';
    like $report, qr/FileChecksum: SHA1: ac24afaef6590f55e1fd90f2d9c57fde4e899ab9/, 'has Changes checksum';
    like $report, qr/LicenseInfoInFile: LicenseRef-1/,                              'has Changes license';

    like $report, qr/FileName: \.\/Mojolicious-7.25\/LICENSE/,                      'has LICENSE file';
    like $report, qr/FileChecksum: SHA1: 2f8018a02043ed1a43f032379e036bb6b88265f2/, 'has LICENSE checksum';
    like $report, qr/LicenseInfoInFile: LicenseRef-2/,                              'has LICENSE license';
    like $report, qr/FileCopyrightText: .*Copyright.*2006.*The Perl Foundation.*/,  'has LICENSE copyright';
  };

  subtest 'Other Licensing Information' => sub {
    like $report, qr/LicenseId: LicenseRef-1/,                   'has license reference 1';
    like $report, qr/LicenseName: NOASSERTION/,                  'has license reference 1 without name';
    like $report, qr/LicenseComment: Risk: 5/,                   'has license reference 1 risk';
    like $report, qr/ExtractedText: .*Fixed copyright notice.*/, 'has license reference 1 text';

    like $report, qr/LicenseId: LicenseRef-Apache-2.0-33/, 'has license reference 35';
    like $report, qr/LicenseName: Apache-2.0/,             'has license reference 35 name';
    like $report, qr/LicenseComment: Risk: 5/,             'has license reference 35 risk';
    like $report, qr/ExtractedText: .*Licensed under the Apache License, Version 2.0.*/,
      'has license reference 35 text';
  };
};

done_testing;
