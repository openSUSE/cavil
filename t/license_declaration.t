# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Mojo::Base -strict;

use FindBin;
use lib "$FindBin::Bin/lib";

use Test::More;
use Test::Mojo;
use Cavil::Test;
use Mojo::File qw(path);

plan skip_all => 'set TEST_ONLINE to enable this test' unless $ENV{TEST_ONLINE};

my $cavil_test = Cavil::Test->new(online => $ENV{TEST_ONLINE}, schema => 'license_declaration_test');
my $t          = Test::Mojo->new(Cavil => $cavil_test->default_config);
$cavil_test->mojo_fixtures($t->app);

# The fixture package declares Artistic-2.0. Give Cavil a pattern for that and for the two licenses the
# package is about to be caught shipping without declaring them.
$t->app->pg->db->query('DELETE FROM license_patterns');
$t->app->patterns->create(pattern => "SPDX-License-Identifier: $_", license => $_)
  for qw(Artistic-2.0 GPL-2.0-only Apache-2.0);
$t->app->pg->db->query('UPDATE license_patterns SET spdx = $1 WHERE license = $1', $_)
  for qw(Artistic-2.0 GPL-2.0-only Apache-2.0);

my $pkg = $t->app->packages->find(1);
my $dir = path($cavil_test->checkout_dir, $pkg->{name}, $pkg->{checkout_dir});

# Shipped code under a license the package file never mentions - the mismatch a reviewer must see
$dir->child('src')->make_path->child('engine.c')->spurt("# SPDX-License-Identifier: GPL-2.0-only\n\nCore code.\n");

# A vendored dependency under a third license. Expected for an aggregation, so it must be counted apart
# from the shipped-code mismatch rather than raising one of its own.
$dir->child('vendor', 'foo')->make_path->child('a.c')->spurt("# SPDX-License-Identifier: Apache-2.0\n\nBundled.\n");

# The declared license really is present in the package, so nothing should be reported as missing
$dir->child('artistic.txt')->spurt("# SPDX-License-Identifier: Artistic-2.0\n\nThe package's own code.\n");

# A license file whose first line Cavil recognises and whose remaining terms it does not. This is the
# case the coverage number exists for: the file resolves cleanly, yet most of it is unaccounted for.
$dir->child('LICENSE')->spurt(<<'EOF');
SPDX-License-Identifier: Artistic-2.0

You may not use this software for evil.
You may not use this software commercially without a separate agreement.
Contact sales@example.com for enterprise terms.
EOF

$t->app->minion->enqueue(unpack => [1]);
$t->app->minion->perform_jobs;

subtest 'Declared license reconciled against the code' => sub {
  ok my $declaration = $t->app->reports->license_declaration(1), 'declaration stored with the report';

  is $declaration->{declared}, 'Artistic-2.0', 'the declared license from the spec file';
  is $declaration->{valid},    1,              'it parses as SPDX';
  is $declaration->{verdict},  'mismatch',     'shipped code carries a license the declaration misses';

  is_deeply $declaration->{undeclared}, [{license => 'GPL-2.0-only', count => 1, files => ['src/engine.c']}],
    'the undeclared license is named with the file that carries it';

  is $declaration->{peripheral}, 1, 'the vendored Apache-2.0 is counted apart, not reported as a mismatch';
  is_deeply $declaration->{not_found}, [], 'the declared license is present, so nothing is missing';
};

subtest 'Legal documents and what Cavil can explain of them' => sub {
  my $documents = $t->app->reports->license_declaration(1)->{documents};
  ok $documents, 'documents travel with the declaration';
  is $documents->{dropped}, 0, 'nothing was left out by the limit';

  my ($license) = grep { $_->{path} eq 'LICENSE' } @{$documents->{documents}};
  ok $license, 'the top-level LICENSE is listed';
  is $license->{kind},  'license', 'kind is carried on every row';
  is $license->{lines}, 4,         'blank lines do not count towards the total';

  # Only the SPDX line is explained by a concrete license; the three lines of novel terms are not, even
  # though the file itself resolves cleanly and raises no unresolved match.
  is $license->{unexplained}, 3, 'the unrecognised terms are counted';

  ok !(grep { $_->{path} eq 'src/engine.c' } @{$documents->{documents}}), 'ordinary source files are not documents';
  ok !(grep { $_->{path} =~ m!^vendor/! } @{$documents->{documents}}), 'vendored trees do not bury the package license';
};

subtest 'Report metadata annotates the declared license' => sub {
  $t->get_ok('/login')->status_is(302);

  $t->get_ok('/reviews/meta/1')
    ->status_is(200)
    ->json_is('/package_license/name',             'Artistic-2.0')
    ->json_is('/declaration/verdict',              'mismatch')
    ->json_is('/declaration/undeclared/0/license', 'GPL-2.0-only')
    ->json_is('/declaration/undeclared/0/count',   1)
    ->json_is('/declaration/peripheral',           1)
    ->json_is('/declaration/not_found',            []);

  # The web report lists which licenses are missing from the declaration, not where each one sits; only
  # the documents are links, and they point into the file browser.
  $t->json_is('/declaration/documents/0/path',        'LICENSE')
    ->json_is('/declaration/documents/0/lines',       4)
    ->json_is('/declaration/documents/0/unexplained', 3)
    ->json_is('/declaration/documents/0/kind',        'license')
    ->json_like('/declaration/documents/0/url', qr!/reviews/file_view/1/LICENSE!)
    ->json_is('/declaration/documents_dropped', 0);
};

# The declaration is a statement about the package file, so it annotates the declared license and stops
# there. The Licenses section reports what the code carries and must stay free of package file concerns.
subtest 'The declaration does not leak into the license report' => sub {
  $t->get_ok('/reviews/report_details/1')->status_is(200);
  ok my $risks = $t->tx->res->json('/risks'), 'risk buckets';

  my @entries = map {@$_} values %$risks;
  ok @entries,                                     'the report has licenses';
  ok !(grep { exists $_->{undeclared} } @entries), 'and not one of them carries a declaration flag';
};

# Every package in production starts out like this, because the declaration is only written when a
# package is analyzed. Package 2 of the standard fixtures is imported but never indexed, so it is the
# real thing rather than a doctored row.
subtest 'A package that has not been analyzed yet simply has no declaration' => sub {
  is $t->app->reports->license_declaration(2), undef, 'nothing stored';

  $t->get_ok('/reviews/meta/2')
    ->status_is(200)
    ->json_is('/declaration', undef, 'the metadata says so explicitly, so the UI renders nothing');
};

# Both reports mark file paths with backticks; kept in single-quoted variables so the pattern itself
# stays free of them.
my $UNDECLARED_LINE = 'Not declared: GPL-2.0-only in `src/engine.c`';
my $DOCUMENT_LINE   = '`LICENSE`: 4 lines, 3 unexplained';

subtest 'Text report explains the mismatch to a packager' => sub {
  $t->get_ok('/reviews/report/1.txt')->status_is(200);
  ok my $text = $t->tx->res->text, 'text response';

  like $text, qr/## Declared License/,  'has its own section';
  like $text, qr/\Q$UNDECLARED_LINE\E/, 'names the license and the file';
  like $text, qr/correcting the package file rather than by changing the code/,
    'points at the fix a packager can actually make';
  like $text, qr/1 further license appears only in vendored or test files/, 'vendored licenses accounted for';

  like $text, qr/## Legal Documents/, 'documents get a section';
  like $text, qr/\Q$DOCUMENT_LINE\E/, 'with the unexplained remainder';
};

subtest 'MCP report keeps the header tidy and puts the detail in a section' => sub {
  my $mcp = $t->app->build_controller->mcp_report(1);

  like $mcp, qr/^Declaration: does NOT match the licenses found in shipped code \(see below\)$/m,
    'one header line, pointing further down';
  unlike $mcp, qr/^Declaration:.*\n\*/m, 'the key-value header does not sprout bullets';

  like $mcp, qr/## Declared License/,  'the detail is a section of its own';
  like $mcp, qr/\Q$UNDECLARED_LINE\E/, 'names the license and the file';
  like $mcp, qr/weigh whether the found licenses are themselves acceptable/,
    'tells the AI to judge fixable metadata rather than assume a licensing problem';

  like $mcp, qr/## Legal Documents/, 'documents reach the AI too';
  like $mcp, qr/\Q$DOCUMENT_LINE\E/, 'so it can read the part Cavil does not explain';
};

subtest 'The declaration is informational and never drives a re-review' => sub {
  my $json = $t->app->packages->find(1);
  like $json->{checksum},   qr!Artistic-2\.0-\d:!, 'shortname still carries the declared license and a risk';
  unlike $json->{checksum}, qr!Artistic-2\.0-9:!,  'a declaration mismatch does not elevate the risk';
};

done_testing;
