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

my $cavil_test = Cavil::Test->new(online => $ENV{TEST_ONLINE}, schema => 'legal_documents_test');
my $t          = Test::Mojo->new(Cavil => $cavil_test->default_config);
$cavil_test->mojo_fixtures($t->app);

$t->app->pg->db->query('DELETE FROM license_patterns');
$t->app->patterns->create(pattern => "SPDX-License-Identifier: $_", license => $_) for qw(Artistic-2.0 Apache-2.0);
$t->app->pg->db->query('UPDATE license_patterns SET spdx = $1 WHERE license = $1', $_) for qw(Artistic-2.0 Apache-2.0);

# A grab-bag marker (catch_all, seeded from the "Any ..." naming rule) and a bare keyword pattern. The
# first counts as recognised text, the second does not - see the NOTICE case in the coverage subtest.
$t->app->patterns->create(pattern => 'All rights reserved by the authors', license => 'Any copyright');
$t->app->patterns->create(pattern => 'redistribution of this document');

my $pkg = $t->app->packages->find(1);
my $dir = path($cavil_test->checkout_dir, $pkg->{name}, $pkg->{checkout_dir});

# A license file whose first line Cavil recognises and whose remaining terms it does not. This is the
# case the coverage number exists for: the file resolves cleanly, yet most of it is unaccounted for.
$dir->child('LICENSE')->spurt(<<'EOF');
SPDX-License-Identifier: Artistic-2.0
All rights reserved by the authors

You may not use this software for evil.
You may not use this software commercially without a separate agreement.
Contact sales@example.com for enterprise terms.
There is a redistribution of this document clause hiding on this line.
EOF

# A vendored dependency's own license file, which must not bury the package's
$dir->child('vendor', 'foo')->make_path->child('LICENSE')
  ->spurt("# SPDX-License-Identifier: Apache-2.0\n\nBundled dependency terms.\n");

# Go source that merely happens to be named after a license word
$dir->child('src')->make_path->child('license.go')->spurt("# SPDX-License-Identifier: Artistic-2.0\n\npackage main\n");

$t->app->minion->enqueue(unpack => [1]);
$t->app->minion->perform_jobs;

subtest 'Legal documents and what Cavil can explain of them' => sub {
  ok my $documents = $t->app->reports->annotations(1)->{legal_documents}, 'documents stored with the report';
  is $documents->{dropped}, 0, 'nothing was left out by the limit';

  my ($license) = grep { $_->{path} eq 'LICENSE' } @{$documents->{documents}};
  ok $license, 'the top-level LICENSE is listed';
  is $license->{kind},  'license', 'kind is carried on every row';
  is $license->{lines}, 6,         'blank lines do not count towards the total';

  # Recognised: the SPDX line, and the "All rights reserved" line via a catch_all marker - the question
  # this number answers is whether Cavil recognised the text, not whether it could name a license.
  # Unrecognised: the three lines of novel terms, plus the line carrying only a bare keyword match,
  # because a trigger word is not recognition of legal text. The file resolves cleanly either way and
  # raises no unresolved match, which is exactly why this is measured outside the snippet resolver.
  is $license->{unexplained}, 4, 'catch_all markers count as recognised, bare keyword matches do not';

  my @paths = map { $_->{path} } @{$documents->{documents}};
  is_deeply \@paths, ['LICENSE'], 'a vendored license and a Go file named license.go are both left out';
};

subtest 'Report metadata carries the documents with file browser links' => sub {
  $t->get_ok('/login')->status_is(302);

  $t->get_ok('/reviews/meta/1')
    ->status_is(200)
    ->json_is('/legal_documents/documents/0/path',        'LICENSE')
    ->json_is('/legal_documents/documents/0/lines',       6)
    ->json_is('/legal_documents/documents/0/unexplained', 4)
    ->json_is('/legal_documents/documents/0/kind',        'license')
    ->json_like('/legal_documents/documents/0/url', qr!/reviews/file_view/1/LICENSE!)
    ->json_is('/legal_documents/dropped', 0);
};

# Every package in production starts out like this, because the documents are only written when a
# package is analyzed. Package 2 of the standard fixtures is imported but never indexed, so it is the
# real thing rather than a doctored row.
subtest 'A package that has not been analyzed yet simply has no documents' => sub {
  is $t->app->reports->annotations(2), undef, 'nothing stored';

  $t->get_ok('/reviews/meta/2')
    ->status_is(200)
    ->json_is('/legal_documents', undef, 'the metadata says so explicitly, so the UI renders nothing');
};

# Both reports mark file paths with backticks; kept in a single-quoted variable so the pattern itself
# stays free of them.
my $DOCUMENT_LINE = '`LICENSE`: 6 lines, 4 unexplained';

subtest 'Text report lists the documents' => sub {
  $t->get_ok('/reviews/report/1.txt')->status_is(200);
  ok my $text = $t->tx->res->text, 'text response';

  like $text, qr/## Legal Documents/, 'documents get a section';
  like $text, qr/\Q$DOCUMENT_LINE\E/, 'with the unexplained remainder';

  unlike $text, qr/## Declared License/, 'and nothing grades the declared license';
};

subtest 'MCP report lists the documents' => sub {
  my $mcp = $t->app->build_controller->mcp_report(1);

  like $mcp, qr/## Legal Documents/, 'documents reach the AI too';
  like $mcp, qr/\Q$DOCUMENT_LINE\E/, 'so it can read the part Cavil does not explain';

  like $mcp,   qr/^Declared-License: Artistic-2\.0$/m, 'the declared value is still in the header';
  unlike $mcp, qr/^Declaration:/m,                     'but nothing grades it';
};

done_testing;
