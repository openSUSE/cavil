# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Mojo::Base -strict;

use FindBin;
use lib "$FindBin::Bin/lib";

use Test::More;
use Test::Mojo;
use Cavil::Test;
use Mojo::File qw(path);
use Mojo::JSON qw(true);

plan skip_all => 'set TEST_ONLINE to enable this test' unless $ENV{TEST_ONLINE};

my $cavil_test = Cavil::Test->new(online => $ENV{TEST_ONLINE}, schema => 'incompatible_licenses_test');
my $t          = Test::Mojo->new(Cavil => $cavil_test->default_config);
$cavil_test->mojo_fixtures($t->app);

$t->app->pg->db->query('DELETE FROM license_patterns');
$t->app->patterns->create(pattern => 'SPDX-License-Identifier: Apache-2.0',   license => 'Apache-2.0');
$t->app->patterns->create(pattern => 'SPDX-License-Identifier: GPL-2.0-only', license => 'GPL-2.0-only');
$t->app->patterns->create(pattern => 'SPDX-License-Identifier: GPL-3.0-only', license => 'GPL-3.0-only');
$t->app->patterns->create(pattern => 'SPDX-License-Identifier: MPL-1.1',      license => 'MPL-1.1');
$t->app->pg->db->query('UPDATE license_patterns SET spdx = $1 WHERE license = $1', $_)
  for qw(Apache-2.0 GPL-2.0-only GPL-3.0-only MPL-1.1);

my $pkg = $t->app->packages->find(1);
my $dir = path($cavil_test->checkout_dir, $pkg->{name}, $pkg->{checkout_dir});
$dir->child('apache_file.txt')->spurt("# SPDX-License-Identifier: Apache-2.0\n\nThis is a test file.\n");
$dir->child('gpl2_file.txt')->spurt("# SPDX-License-Identifier: GPL-2.0-only\n\nThis is another test file.\n");

# Deeper co-location must outrank package-root proximity.
my $module = $dir->child('src', 'net')->make_path;
$module->child('tls.c')->spurt("# SPDX-License-Identifier: Apache-2.0\n\nDeeply nested Apache file.\n");
$module->child('http.c')->spurt("# SPDX-License-Identifier: GPL-2.0-only\n\nDeeply nested GPL file.\n");

# A vendored dependency is its own tier: still worth a spot check, because it can be linked into the build.
my $vendored = $dir->child('vendor', 'foo')->make_path;
$vendored->child('lib.c')->spurt("# SPDX-License-Identifier: GPL-2.0-only\n\nVendored GPL-2.0 library.\n");
$vendored->child('plugin.c')->spurt("# SPDX-License-Identifier: GPL-3.0-only\n\nVendored GPL-3.0 plugin.\n");

# Build machinery never ends up in the binary package, so a pair meeting only there is as ignorable as tests
my $m4 = $dir->child('m4')->make_path;
$m4->child('ax_mpl.m4')->spurt("dnl SPDX-License-Identifier: MPL-1.1\n\nAC_DEFUN([AX_MPL], [])\n");
$m4->child('ax_gpl.m4')->spurt("dnl SPDX-License-Identifier: GPL-2.0-only\n\nAC_DEFUN([AX_GPL], [])\n");
$dir->child('configure')->spurt("#!/bin/sh\n# SPDX-License-Identifier: MPL-1.1\n\necho configured\n");

$t->app->minion->enqueue(unpack => [1]);
$t->app->minion->perform_jobs;

subtest 'GPL-2.0-only and Apache-2.0 detected as incompatible' => sub {
  $t->get_ok('/login')->status_is(302)->header_is(Location => '/');

  subtest 'Details after indexing' => sub {
    $t->get_ok('/reviews/meta/1')
      ->status_is(200)
      ->json_is('/declarations/0/file',    'perl-Mojolicious.spec')
      ->json_is('/declarations/0/license', 'Artistic-2.0')
      ->json_is('/declarations/0/spdx',    true)
      ->json_like('/package_version', qr!7\.25!)
      ->json_like('/package_summary', qr!Real-time web framework!)
      ->json_like('/package_url',     qr!http://search\.cpan\.org/dist/Mojolicious/!)
      ->json_like('/state',           qr!new!)
      ->json_is('/unpacked_files', 348)
      ->json_is('/unpacked_size',  '2.5MiB');
  };

  subtest 'JSON report' => sub {
    $t->get_ok('/reviews/report/1.json')->status_is(200);
    ok my $json = $t->tx->res->json, 'JSON response';

    ok my $pkg = $json->{package}, 'package';
    is $pkg->{id},   1,                  'id';
    is $pkg->{name}, 'perl-Mojolicious', 'name';
    like $pkg->{checksum},   qr!Artistic-2\.0-\d:!, 'checksum shortname carries the license and a risk';
    unlike $pkg->{checksum}, qr!Artistic-2\.0-9:!,  'incompatibility no longer elevates the risk to 9';
    is $pkg->{state},  'new',                                                                 'state';
    is $pkg->{notice}, 'Manual review is required because no previous reports are available', 'requires manual review';

    ok my $report = $json->{report},                  'report';
    ok my $compat = $report->{license_compatibility}, 'license compatibility matrix';
    is_deeply $compat->{licenses}, ['Apache-2.0', 'GPL-2.0-only', 'GPL-3.0-only', 'MPL-1.1'],
      'every flagged license on the axes';

    # OSADL flags both directions as "No", verbatim.
    is $compat->{matrix}{'Apache-2.0'}{'GPL-2.0-only'}{compatibility}, 'No', 'Apache-2.0 <- GPL-2.0-only: No';
    is $compat->{matrix}{'GPL-2.0-only'}{'Apache-2.0'}{compatibility}, 'No', 'GPL-2.0-only <- Apache-2.0: No';
    like $compat->{matrix}{'Apache-2.0'}{'GPL-2.0-only'}{explanation},   qr/\S/, 'verbatim OSADL explanation present';
    unlike $compat->{matrix}{'Apache-2.0'}{'GPL-2.0-only'}{explanation}, qr/&quot;/, 'explanation entities decoded';

    # Proximity ranks the pair by its closest co-location: the two files inside src/net (depth 2), not
    # the copies at the package root (depth 0).
    ok my $prox = $compat->{proximity}{'Apache-2.0'}{'GPL-2.0-only'}, 'proximity for the flagged pair';
    is $prox->{lca_depth}, 2, 'ranked by the deepest shared directory (src/net)';
    is $prox->{same_file}, 0, 'not a same-file co-occurrence';
    is_deeply [sort @{$prox->{files}}], ['src/net/http.c', 'src/net/tls.c'], 'representative closest file pair';
    is $prox->{tier}, 0, 'shipped source';

    # The vendored pair meets in its own tier, between shipped source and tests/docs.
    ok my $vprox = $compat->{proximity}{'GPL-2.0-only'}{'GPL-3.0-only'}, 'proximity for the vendored pair';
    is $vprox->{tier}, 1, 'vendored code';
    is_deeply [sort @{$vprox->{files}}], ['vendor/foo/lib.c', 'vendor/foo/plugin.c'], 'the vendored files';

    # The frontend gets the proximity ranking alongside the matrix, so the grid can colour by likelihood
    # and the detail panel can link to the files.
    $t->get_ok('/reviews/report_details/1')
      ->status_is(200)
      ->json_is('/license_compatibility/licenses', ['Apache-2.0', 'GPL-2.0-only', 'GPL-3.0-only', 'MPL-1.1'])
      ->json_is('/license_compatibility/matrix/Apache-2.0/GPL-2.0-only/compatibility', 'No')
      ->json_is('/license_compatibility/proximity/Apache-2.0/GPL-2.0-only/same_file',  0)
      ->json_is('/license_compatibility/proximity/Apache-2.0/GPL-2.0-only/lca_depth',  2)
      ->json_is('/license_compatibility/proximity/Apache-2.0/GPL-2.0-only/tier',       0)
      ->json_is('/license_compatibility/proximity/Apache-2.0/GPL-2.0-only/confidence', 3);
  };

  subtest 'Text report' => sub {
    $t->get_ok('/reviews/report/1.txt')->status_is(200);
    ok my $text = $t->tx->res->text, 'text response';
    like $text, qr/### Incompatible Licenses/, 'text report has a dedicated section for the incompatible pairs';
    like $text, qr/Only matters if the code is combined into one work/,
      'text report gives a neutral, informational compatibility note';
    unlike $text, qr/Elevated risk/, 'text report no longer frames incompatibilities as elevated risk';
    like $text,   qr/\* Apache-2\.0 and GPL-2\.0-only/, 'text report lists the incompatible pair symmetrically';

    # Packagers get the location so they can find the files that co-locate the two licenses.
    like $text, qr!\Qsame directory `src/net`\E!, 'text report annotates where the licenses co-locate';
    like $text, qr!\Q* GPL-2.0-only and GPL-3.0-only (same directory `vendor/foo`\E!,
      'a vendored pair keeps its location instead of being written off';
    like $text, qr/a\s+vendored library that gets linked in is/,
      'and the note says vendoring is not automatically separate';
  };

  subtest 'MCP report' => sub {
    my $mcp = $t->app->build_controller->mcp_report(1);
    like $mcp, qr/### Incompatible Licenses/, 'MCP report has the incompatibilities section';
    like $mcp, qr/Worth investigating \(co-located in shipped code\)/,
      'MCP report separates the co-located pairs worth investigating';

    # The AI is handed the exact files and told to confirm the combination itself.
    like $mcp, qr/Apache-2\.0 \+ GPL-2\.0-only \[mutual\]/,                       'names the pair and its severity';
    like $mcp, qr!same directory `src/net`: `src/net/tls\.c`, `src/net/http\.c`!, 'points at the co-located files';
    like $mcp, qr/Proximity locates the code/,                                    'tells the AI proximity is not proof';
    like $mcp, qr/cavil_get_file/, 'points the AI at the tool to confirm';

    # Vendored pairs are a gate of their own: listed with their files for a spot check, not folded into the
    # lower-priority count, because vendored code can still be linked into the shipped build.
    like $mcp, qr/Vendored dependencies \(spot check/, 'vendored pairs get their own section';
    like $mcp, qr!\QGPL-2.0-only + GPL-3.0-only [mutual] - same directory `vendor/foo`\E!,
      'with the pair and the files to open';
  };

  subtest 'Build files' => sub {
    my $scope = sub {
      $t->get_ok('/reviews/report_details/1')->status_is(200);
      my ($mpl) = grep { $_->{name} eq 'MPL-1.1' } map {@$_} values %{$t->tx->res->json->{risks}};
      return $mpl->{scope};
    };
    is $t->app->reports->dig_report(1)->{license_compatibility}{proximity}{'GPL-2.0-only'}{'MPL-1.1'}{tier}, 2,
      'a pair meeting only in build files is ignorable';
    is_deeply $scope->(), ['build'], 'the license is only in build files';
    my $mcp = $t->app->build_controller->mcp_report(1);
    like $mcp, qr/\* MPL-1\.1: 2 files \(only in build files\)/, 'MCP report says where the license is';
    like $mcp, qr!\* 3 in tests/docs/examples/build files/license catalogs \(ignorable even inside a vendored tree\)!,
      'MCP report counts the pairs with MPL-1.1 as lower priority';
    $t->get_ok('/reviews/report/1.txt')
      ->status_is(200)
      ->content_like(qr!\* GPL-2\.0-only and MPL-1\.1 \(tests/docs/examples/build files/license catalogs only\)!,
      'text report says where the pair meets');

    # A build tool ships its build files, so for it they are shipped source
    $t->app->pg->db->update('bot_users', {roles => ['admin']}, {login => 'tester'});
    $t->put_ok('/settings/legal-reports.json' => json => {values => {build_tool_packages => ['perl-Mojolicious']}})
      ->status_is(200)
      ->json_is('/values/build_tool_packages', ['perl-Mojolicious']);
    $t->app->minion->perform_jobs;
    is $t->app->reports->dig_report(1)->{license_compatibility}{proximity}{'GPL-2.0-only'}{'MPL-1.1'}{tier}, 0,
      'shipped source of a build tool';
    $t->get_ok('/reviews/report/1.json')
      ->status_is(200)
      ->json_is('/report/license_compatibility/proximity/GPL-2.0-only/MPL-1.1/tier', 0,
      'the cached report was rebuilt');
    is $scope->(), undef, 'no scope label';
    like $t->app->build_controller->mcp_report(1), qr!\QGPL-2.0-only + MPL-1.1 [mutual] - same directory `m4`\E!,
      'worth investigating again';

    $t->put_ok('/settings/legal-reports.json' => json => {reset => ['build_tool_packages']})->status_is(200);
    $t->app->minion->perform_jobs;
    is_deeply $scope->(), ['build'], 'labelled again after a reset';
  };

  $t->get_ok('/logout')->status_is(302)->header_is(Location => '/');
};

done_testing;
