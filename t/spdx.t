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
use Cavil::SPDX;
use Mojolicious::Lite;
use Mojo::File qw(path tempfile);
use Mojo::Util qw(decode);

plan skip_all => 'set TEST_ONLINE to enable this test' unless $ENV{TEST_ONLINE};

my $cavil_test = Cavil::Test->new(online => $ENV{TEST_ONLINE}, schema => 'spdx_test');
my $t          = Test::Mojo->new(Cavil => $cavil_test->default_config);
$cavil_test->spdx_fixtures($t->app);
$t->app->pg->db->query('UPDATE license_patterns SET spdx = ? WHERE license = ?', '', 'Apache-2.0');

subtest 'Unpack and index' => sub {
  ok !$t->app->packages->is_indexed(1), 'package has not been indexed';
  $t->app->minion->enqueue(unpack => [1]);
  $t->app->minion->perform_jobs;
  ok $t->app->packages->is_indexed(1), 'package has been indexed';
  is $t->app->minion->jobs({states => ['failed']})->total, 0, 'no failed jobs';
};

subtest 'Generate SPDX report' => sub {
  $t->get_ok('/login')->status_is(302)->header_is(Location => '/');

  is $t->app->pg->db->query('UPDATE snippets SET classified = true, license = false WHERE id = any(?)', [1])->rows, 1,
    'one snippet is not a license';
  is $t->app->pg->db->query(
    'UPDATE snippets SET classified = true, license = true, like_pattern = 1, likelyness = 0.95 WHERE id = any(?)', [2])
    ->rows, 1, 'one snippet is a license';

  ok !$t->app->packages->has_spdx_report(1), 'package has no SPDX report';
  $t->get_ok('/spdx/1')->status_is(408)->content_like(qr/generated/)->content_unlike(qr/SPDXVersion/);
  $t->get_ok('/spdx/1')->status_is(408)->content_like(qr/generated/)->content_unlike(qr/SPDXVersion/);
  $t->app->minion->perform_jobs;
  is $t->app->minion->jobs({states => ['failed']})->total, 0, 'no failed jobs';
  ok $t->app->packages->has_spdx_report(1), 'package has SPDX report';
  $t->get_ok('/spdx/1')->status_is(200)->content_unlike(qr/generated/)->content_like(qr/SPDXVersion/);

  $t->get_ok('/logout')->status_is(302)->header_is(Location => '/');
};

subtest 'Always generate SPDX reports when reindexing' => sub {
  $t->app->packages->reindex(1);
  $t->app->minion->perform_jobs;
  ok !$t->app->packages->has_spdx_report(1), 'package has no SPDX report';

  $t->app->config->{always_generate_spdx_reports} = 1;
  $t->app->packages->reindex(1);
  $t->app->minion->perform_jobs;
  ok $t->app->packages->has_spdx_report(1), 'package has SPDX report';
};

subtest 'SPDX report contents' => sub {
  my $path = $t->app->packages->spdx_report_path(1);
  ok !-e "$path.tmp",       'SPDX temp file has been cleaned up';
  ok !-e "$path.files.tmp", 'SPDX file section temp file has been cleaned up';
  ok !-e "$path.refs.tmp",  'SPDX ref temp file has been cleaned up';
  my $report = decode('UTF-8', $path->slurp);

  subtest 'Document Information' => sub {
    like $report, qr/DocumentNamespace: http.+legaldb.+spdx.+1/, 'has DocumentNamespace';
    like $report, qr/DocumentName: report.spdx/,                 'has DocumentName';
    like $report, qr/SPDXID: SPDXRef-DOCUMENT/,                  'has SPDXID for document';
  };

  subtest 'Creation Information' => sub {
    like $report, qr/SPDXVersion: SPDX-2.3/, 'has SPDXVersion 2.3';
    like $report, qr/DataLicense: CC0-1.0/,  'has DataLicense';
    like $report, qr/Creator: Tool: Cavil/,  'has Creator';
    like $report, qr/Created: .+T.+Z/,       'has Created';
  };

  subtest 'Package Information' => sub {
    like $report, qr/PackageName: perl-Mojolicious/,                                     'has PackageName';
    like $report, qr/SPDXID: SPDXRef-pkg-1/,                                             'has SPDXID for package';
    like $report, qr/PackageDownloadLocation: NOASSERTION/,                              'has PackageDownloadLocation';
    like $report, qr/PackageVerificationCode: 18e5ffc40dd3a06717d15fa74608bbbfbe9ae8e4/, 'has PackageVerificationCode';
    like $report, qr/PackageVersion: 7.25/,                                              'has PackageVersion';
    like $report, qr/PackageLicenseDeclared: Artistic-2.0/,                              'has PackageLicenseDeclared';
    like $report, qr/PackageDescription: Real-time/,                                     'has PackageDescription';
    like $report, qr/PackageHomePage: http/,                                             'has PackageHomePage';
    like $report,   qr/PackageLicenseInfoFromFiles: LicenseRef-1-1/,            'has PackageLicenseInfoFromFiles';
    unlike $report, qr/PackageLicenseInfoFromFiles: NOASSERTION/,               'does not fall back to NOASSERTION';
    like $report,   qr/PackageLicenseConcluded: NOASSERTION/,                   'has PackageLicenseConcluded';
    like $report,   qr/PackageCopyrightText: NOASSERTION/,                      'has PackageCopyrightText';
    like $report,   qr/PackageChecksum: MD5: .+/,                               'has PackageCheckSum';
    like $report,   qr/Relationship: SPDXRef-DOCUMENT DESCRIBES SPDXRef-pkg-1/, 'has relationship to document';
    like $report, qr/Package Information.+PackageChecksum: MD5:.+File Information/s,
      'has package section before file section';
  };

  subtest 'File Information' => sub {
    like $report, qr/FileName: \.\/Mojolicious-7.25\/\.perltidyrc/, 'has .perltidyrc file';
    like $report, qr/SPDXID: SPDXRef-item-1-1/,                     'has SPDXID for file';

    like $report, qr/FileName: \.\/Mojolicious-7.25\/Changes/,                      'has Changes file';
    like $report, qr/FileChecksum: SHA1: ac24afaef6590f55e1fd90f2d9c57fde4e899ab9/, 'has Changes checksum';
    like $report, qr/LicenseInfoInFile: LicenseRef-1/,                              'has Changes license';

    like $report, qr/FileName: \.\/Mojolicious-7.25\/LICENSE/,                      'has LICENSE file';
    like $report, qr/FileChecksum: SHA1: 2f8018a02043ed1a43f032379e036bb6b88265f2/, 'has LICENSE checksum';
    like $report, qr/LicenseInfoInFile: LicenseRef-1-2/,                            'has LICENSE license';
    like $report, qr/FileCopyrightText: .*Copyright.*2006.*The Perl Foundation.*/,  'has LICENSE copyright';
  };

  subtest 'Other Licensing Information' => sub {
    like $report, qr/LicenseID: LicenseRef-1/,                   'has license reference 1';
    like $report, qr/LicenseName: NOASSERTION/,                  'has license reference 1 without name';
    like $report, qr/LicenseComment: Risk: 5/,                   'has license reference 1 risk';
    like $report, qr/ExtractedText: .*Fixed copyright notice.*/, 'has license reference 1 text';

    like $report, qr/LicenseID: LicenseRef-1-6/, 'has license reference 6';
    like $report,
      qr/LicenseComment: <text>Risk: 9 \(.+\)\nSimilar: Apache-2.0 \(95% similarity, estimated risk 5\)<\/text>/,
      'has license reference with risk and similarity in one multiline comment';

    like $report, qr/LicenseID: LicenseRef-Apache-2.0-1-30/, 'has license reference 30';
    like $report, qr/LicenseName: Apache-2.0/,               'has license reference 30 name';
    like $report, qr/LicenseComment: Risk: 5/,               'has license reference 30 risk';
    like $report, qr/ExtractedText: .*Licensed under the Apache License, Version 2.0.*/,
      'has license reference 30 text';
    unlike $report, qr/LicenseId: LicenseRef.+40/, 'no license reference 40';
  };

  subtest 'No component box when no components have been detected' => sub {
    unlike $report, qr/^## Components/m,                       'no component box header';
    unlike $report, qr/SPDXID: SPDXRef-component-/,            'no component SPDXID';
    unlike $report, qr/ExternalRef: PACKAGE-MANAGER purl pkg/, 'no purl ExternalRef';
  };

  subtest 'Pre-processed files are replaced with the real files' => sub {
    unlike $report, qr/FileName: .+run_prettify\.processed\.js/,                      'no pre-processed file';
    unlike $report, qr/FileChecksum: SHA1: f6a8e660f0a8ce1d7458451bdcf76b41fef2a8a7/, 'no pre-processed checksum';

    like $report, qr/FileName: .+prettify\/run_prettify\.js/,                       'has original file name';
    like $report, qr/FileChecksum: SHA1: face8177a6804506c67c5644c00f3c6e0e50f02b/, 'has original checksum';
    like $report, qr/FileCopyrightText: .+Copyright.+Google/,                       'has copyright text';
  };
};

subtest 'SPDX writer escapes closing text tag in text values' => sub {
  my $tmp_file = tempfile;
  my $handle   = path($tmp_file)->open('>');
  my $writer   = _SPDXWriter->new(handle => $handle);

  $writer->text(ExtractedText => 'foo</text>bar');
  close $handle;

  my $content = path($tmp_file)->slurp;
  like $content, qr/ExtractedText: <text>foo< \/text>bar<\/text>/, 'escaped embedded closing text tag';
};

subtest 'SPDX report is obsolete' => sub {
  $t->get_ok('/login')->status_is(302)->header_is(Location => '/');

  is $t->app->pg->db->query('UPDATE bot_packages SET obsolete = true WHERE id = any(?)', [1])->rows, 1,
    'one package obsoleted';
  $t->get_ok('/spdx/1')->status_is(410)->content_like(qr/package is obsolete/);
  $t->get_ok('/spdx/1')->status_is(410)->content_like(qr/package is obsolete/);

  $t->get_ok('/logout')->status_is(302)->header_is(Location => '/');
};

done_testing;
