# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Mojo::Base -strict;

use Test::More;
use Cavil::Licenses qw(scancode_suggestion);

subtest 'Exact ScanCode license keys' => sub {
  is scancode_suggestion('mit'),                 'LicenseRef-scancode-mit',           'mit';
  is scancode_suggestion('apache-2.0'),          'LicenseRef-scancode-apache-2.0',    'apache-2.0 (keeps version dot)';
  is scancode_suggestion('public-domain'),       'LicenseRef-scancode-public-domain', 'public-domain';
  is scancode_suggestion('proprietary-license'), 'LicenseRef-scancode-proprietary-license', 'proprietary-license';
};

subtest 'Case insensitive' => sub {
  is scancode_suggestion('MIT'),        'LicenseRef-scancode-mit',        'upper case';
  is scancode_suggestion('Apache-2.0'), 'LicenseRef-scancode-apache-2.0', 'mixed case';
};

subtest 'Normalization of separators and whitespace' => sub {
  is scancode_suggestion('Public Domain'),    'LicenseRef-scancode-public-domain', 'spaces become dashes';
  is scancode_suggestion('  public-domain '), 'LicenseRef-scancode-public-domain', 'surrounding whitespace trimmed';
  is scancode_suggestion('public_domain'),    'LicenseRef-scancode-public-domain', 'underscores become dashes';
  is scancode_suggestion('apache 2.0'),       'LicenseRef-scancode-apache-2.0',    'space before version';
};

subtest 'Already prefixed identifiers' => sub {
  is scancode_suggestion('LicenseRef-scancode-mit'), 'LicenseRef-scancode-mit', 'existing prefix is accepted';
  is scancode_suggestion('licenseref-scancode-mit'), 'LicenseRef-scancode-mit', 'existing prefix case insensitive';
};

subtest 'Unknown or empty input' => sub {
  is scancode_suggestion('this-is-not-a-real-license-xyz'), undef, 'unknown license';
  is scancode_suggestion(''),                               undef, 'empty string';
  is scancode_suggestion('   '),                            undef, 'whitespace only';
  is scancode_suggestion(undef),                            undef, 'undef';
};

done_testing;
