# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Mojo::Base -strict, -signatures;

use FindBin;
use lib "$FindBin::Bin/lib";

use Test::More;
use Test::Mojo;
use Cavil::Components::Detector::NPM;
use Cavil::Test;
use Mojo::Date;
use Mojo::File qw(path tempdir);
use Mojo::Log;
use Mojo::Util qw(decode);

my $fixtures = path(__FILE__)->sibling('components', 'npm');

subtest 'NPM detector: lockfileVersion 3' => sub {
  my $detector = Cavil::Components::Detector::NPM->new;
  my $root     = $fixtures->child('v3');
  my $manifest = $root->child('package-lock.json');
  my $rows     = $detector->detect("$manifest", "$root", 'package-lock.json');

  is scalar @$rows, 1, 'only the present production dep is recorded';
  my $leftpad = $rows->[0];
  is $leftpad->{name},     'leftpad',  'name';
  is $leftpad->{version},  '1.3.0',    'version';
  is $leftpad->{license},  'MIT',      'license from lockfile';
  is $leftpad->{is_dev},   0,          'not dev';
  is $leftpad->{present},  1,          'on disk';
  is $leftpad->{relation}, 'CONTAINS', 'relation';
  like $leftpad->{source_url}, qr{registry\.npmjs\.org/leftpad}, 'resolved URL preserved';
  like $leftpad->{checksum},   qr{^sha512-},                     'integrity preserved';
};

subtest 'NPM detector: lockfileVersion 1 (legacy nested dependencies)' => sub {
  my $detector = Cavil::Components::Detector::NPM->new;
  my $root     = $fixtures->child('v1');
  my $manifest = $root->child('package-lock.json');
  my $rows     = $detector->detect("$manifest", "$root", 'package-lock.json');

  is scalar @$rows, 1, 'only the present production dep is recorded';
  my $leftpad = $rows->[0];
  is $leftpad->{name},    'leftpad', 'name';
  is $leftpad->{version}, '1.3.0',   'version';
  is $leftpad->{license}, 'MIT',     'object-form license normalised';
  is $leftpad->{present}, 1,         'on disk';
};

subtest 'NPM detector: malformed manifest degrades gracefully' => sub {
  my @warnings;
  my $log = Mojo::Log->new(level => 'warn');
  $log->unsubscribe('message');
  $log->on(message => sub { push @warnings, join ' ', @_[2 .. $#_] if $_[1] eq 'warn' });

  my $detector = Cavil::Components::Detector::NPM->new(log => $log);
  my $root     = $fixtures->child('broken');
  my $manifest = $root->child('package-lock.json');
  my $rows     = $detector->detect("$manifest", "$root", 'package-lock.json');

  is_deeply $rows, [], 'returns empty list on parse failure';
  ok scalar(grep {/Failed to parse/} @warnings), 'warning was logged';
};

subtest 'NPM detector: license fallback from vendored package.json' => sub {

  # Build a one-off lockfile that omits the license field; expect it to be
  # filled in from node_modules/<name>/package.json
  my $tmp    = tempdir;
  my $vendor = $tmp->child('node_modules', 'leftpad')->make_path;
  $vendor->child('package.json')->spew('{"name":"leftpad","version":"1.3.0","license":"MIT"}');
  my $manifest = $tmp->child('package-lock.json');
  $manifest->spew(<<'JSON');
{
  "lockfileVersion": 3,
  "packages": {
    "": {"name":"demo","version":"1.0.0"},
    "node_modules/leftpad": {"version":"1.3.0"}
  }
}
JSON

  my $detector = Cavil::Components::Detector::NPM->new;
  my $rows     = $detector->detect("$manifest", "$tmp", 'package-lock.json');
  is scalar @$rows,       1,     'one row';
  is $rows->[0]{license}, 'MIT', 'license filled from vendored package.json';
  is $rows->[0]{present}, 1,     'marked present';
};

subtest 'NPM detector: production dep without vendored dir is recorded as not present' => sub {
  my $tmp      = tempdir;
  my $manifest = $tmp->child('package-lock.json');
  $manifest->spew(<<'JSON');
{
  "lockfileVersion": 3,
  "packages": {
    "": {"name":"demo","version":"1.0.0"},
    "node_modules/missing-dep": {"version":"2.0.0","license":"Apache-2.0"}
  }
}
JSON

  my $detector = Cavil::Components::Detector::NPM->new;
  my $rows     = $detector->detect("$manifest", "$tmp", 'package-lock.json');
  is scalar @$rows,       1,             'declared-but-not-vendored prod dep is still recorded';
  is $rows->[0]{name},    'missing-dep', 'name';
  is $rows->[0]{present}, 0,             'marked as not present';
  is $rows->[0]{license}, 'Apache-2.0',  'license preserved from lockfile';
};

subtest 'NPM detector: broken vendored package.json does not crash' => sub {
  my $tmp    = tempdir;
  my $vendor = $tmp->child('node_modules', 'leftpad')->make_path;
  $vendor->child('package.json')->spew('{not valid json');
  my $manifest = $tmp->child('package-lock.json');
  $manifest->spew(<<'JSON');
{
  "lockfileVersion": 3,
  "packages": {
    "": {"name":"demo"},
    "node_modules/leftpad": {"version":"1.3.0"}
  }
}
JSON

  my $detector = Cavil::Components::Detector::NPM->new;
  my $rows     = $detector->detect("$manifest", "$tmp", 'package-lock.json');
  is scalar @$rows,       1,     'one row';
  is $rows->[0]{license}, undef, 'license left undef when vendored package.json is unparseable';
  is $rows->[0]{present}, 1,     'still marked present (the directory exists)';
};

subtest 'NPM detector: non-object root JSON is rejected' => sub {
  my $tmp      = tempdir;
  my $manifest = $tmp->child('package-lock.json');
  $manifest->spew('["not", "a", "lockfile"]');

  my $detector = Cavil::Components::Detector::NPM->new;
  my $rows     = $detector->detect("$manifest", "$tmp", 'package-lock.json');
  is_deeply $rows, [], 'array-rooted JSON yields no components';
};

subtest 'NPM detector: empty lockfile yields no components' => sub {
  my $tmp      = tempdir;
  my $manifest = $tmp->child('package-lock.json');
  $manifest->spew('{"lockfileVersion": 3, "packages": {"": {"name":"empty"}}}');

  my $detector = Cavil::Components::Detector::NPM->new;
  my $rows     = $detector->detect("$manifest", "$tmp", 'package-lock.json');
  is_deeply $rows, [], 'lockfile with only the root entry yields no components';
};

subtest 'NPM detector: nested transitive dep extracts name from last node_modules segment' => sub {
  my $tmp      = tempdir;
  my $nested   = $tmp->child('node_modules', 'parent', 'node_modules', 'child')->make_path;
  $nested->child('package.json')->spew('{"name":"child","version":"2.0.0","license":"MIT"}');
  $tmp->child('node_modules', 'parent')->child('package.json')
    ->spew('{"name":"parent","version":"1.0.0","license":"Apache-2.0"}');
  my $manifest = $tmp->child('package-lock.json');
  $manifest->spew(<<'JSON');
{
  "lockfileVersion": 3,
  "packages": {
    "": {"name":"demo","version":"1.0.0"},
    "node_modules/parent": {"version":"1.0.0"},
    "node_modules/parent/node_modules/child": {"version":"2.0.0"}
  }
}
JSON

  my $detector = Cavil::Components::Detector::NPM->new;
  my $rows     = $detector->detect("$manifest", "$tmp", 'package-lock.json');
  is scalar @$rows, 2, 'parent and nested child both recorded';
  my ($parent) = grep { $_->{name} eq 'parent' } @$rows;
  my ($child)  = grep { $_->{name} eq 'child' } @$rows;
  ok $parent,             'parent extracted';
  ok $child,              'child extracted (not "parent/node_modules/child")';
  is $parent->{license},  'Apache-2.0', 'parent license from vendored package.json';
  is $parent->{present},  1,            'parent present at node_modules/parent';
  is $child->{license},   'MIT',        'child license from nested vendored package.json';
  is $child->{present},   1,            'child present at nested path';
};

subtest 'NPM detector: scoped name inside nested node_modules keeps the scope' => sub {
  my $tmp    = tempdir;
  my $nested = $tmp->child('node_modules', '@babel', 'code-frame', 'node_modules', '@scope', 'tool')->make_path;
  $nested->child('package.json')->spew('{"name":"@scope/tool","version":"3.0.0","license":"ISC"}');
  my $manifest = $tmp->child('package-lock.json');
  $manifest->spew(<<'JSON');
{
  "lockfileVersion": 3,
  "packages": {
    "": {"name":"demo"},
    "node_modules/@babel/code-frame/node_modules/@scope/tool": {"version":"3.0.0"}
  }
}
JSON

  my $detector = Cavil::Components::Detector::NPM->new;
  my $rows     = $detector->detect("$manifest", "$tmp", 'package-lock.json');
  is scalar @$rows,       1,             'scoped nested dep recorded';
  is $rows->[0]{name},    '@scope/tool', 'scope preserved, parent stripped';
  is $rows->[0]{license}, 'ISC',         'license fallback from nested package.json';
  is $rows->[0]{present}, 1,             'present at nested scoped path';
};

subtest 'NPM detector: workspace entries (no node_modules prefix) are skipped' => sub {
  my $tmp      = tempdir;
  my $manifest = $tmp->child('package-lock.json');
  $manifest->spew(<<'JSON');
{
  "lockfileVersion": 3,
  "packages": {
    "": {"name":"monorepo"},
    "packages/app":  {"name":"app","version":"1.0.0"},
    "packages/lib":  {"name":"lib","version":"1.0.0"},
    "node_modules/leftpad": {"version":"1.3.0","license":"MIT"}
  }
}
JSON

  my $detector = Cavil::Components::Detector::NPM->new;
  my $rows     = $detector->detect("$manifest", "$tmp", 'package-lock.json');
  is scalar @$rows,    1,         'only the vendored dep is recorded';
  is $rows->[0]{name}, 'leftpad', 'workspaces (packages/app, packages/lib) skipped';
};

subtest 'NPM detector: v1 nested dependencies resolve at nested on-disk path' => sub {
  my $tmp    = tempdir;
  my $parent = $tmp->child('node_modules', 'parent')->make_path;
  $parent->child('package.json')->spew('{"name":"parent","version":"1.0.0"}');
  my $nested = $parent->child('node_modules', 'child')->make_path;
  $nested->child('package.json')->spew('{"name":"child","version":"2.0.0","license":"BSD-3-Clause"}');
  my $manifest = $tmp->child('package-lock.json');
  $manifest->spew(<<'JSON');
{
  "lockfileVersion": 1,
  "dependencies": {
    "parent": {
      "version": "1.0.0",
      "dependencies": {
        "child": {"version": "2.0.0"}
      }
    }
  }
}
JSON

  my $detector = Cavil::Components::Detector::NPM->new;
  my $rows     = $detector->detect("$manifest", "$tmp", 'package-lock.json');
  is scalar @$rows, 2, 'parent and nested child both recorded';
  my ($child) = grep { $_->{name} eq 'child' } @$rows;
  ok $child,             'nested child extracted';
  is $child->{license},  'BSD-3-Clause', 'license fallback walks nested path';
  is $child->{present},  1,              'nested v1 dep is found on disk';
};

subtest 'NPM detector: purl construction' => sub {
  my $detector = Cavil::Components::Detector::NPM->new;
  is $detector->purl({name => 'leftpad', version => '1.3.0'}), 'pkg:npm/leftpad@1.3.0', 'plain purl';
  is $detector->purl({name => '@angular/core', version => '17.0.0'}), 'pkg:npm/%40angular/core@17.0.0',
    'scoped name encodes leading @';
  is $detector->purl({name => 'leftpad', version => undef}), 'pkg:npm/leftpad', 'omits version when missing';
};

SKIP: {
  skip 'set TEST_ONLINE to enable end-to-end tests', 1 unless $ENV{TEST_ONLINE};

  my $cavil_test = Cavil::Test->new(online => $ENV{TEST_ONLINE}, schema => 'components_test');
  my $t          = Test::Mojo->new(Cavil => $cavil_test->default_config);
  my $pkg_id     = $cavil_test->npm_vendored_fixtures($t->app);

  subtest 'Component detection task fails before indexing' => sub {
    my $job_id = $t->app->minion->enqueue(detect_components => [$pkg_id]);
    $t->app->minion->perform_jobs;
    my $job = $t->app->minion->job($job_id);
    is $job->info->{state}, 'failed', 'job failed';
    like $job->info->{result}, qr/not indexed yet/, 'descriptive error';
    $job->remove;
  };

  subtest 'Full pipeline detects vendored NPM components' => sub {
    ok !$t->app->packages->is_indexed($pkg_id), 'package not yet indexed';
    $t->app->minion->enqueue(unpack => [$pkg_id]);
    $t->app->minion->perform_jobs;
    ok $t->app->packages->is_indexed($pkg_id), 'package indexed';
    is $t->app->minion->jobs({states => ['failed']})->total, 0, 'no failed jobs';

    my $rows = $t->app->components->for_package($pkg_id);
    is scalar @$rows, 1, 'one component detected';
    my $leftpad = $rows->[0];
    is $leftpad->{ecosystem}, 'npm',      'ecosystem';
    is $leftpad->{name},      'leftpad',  'name';
    is $leftpad->{version},   '1.3.0',    'version';
    is $leftpad->{license},   'MIT',      'license';
    is $leftpad->{is_dev},    0,          'not dev';
    is $leftpad->{present},   1,          'present on disk';
    is $leftpad->{relation},  'CONTAINS', 'relation';
    like $leftpad->{manifest_path}, qr{package-lock\.json$}, 'manifest_path';

    is scalar @{$t->app->components->for_package($pkg_id, {present_only => 1})}, 1,
      'present_only matches when vendored';
  };

  subtest 'SPDX report includes detected components' => sub {
    $t->get_ok('/login')->status_is(302)->header_is(Location => '/');
    $t->get_ok("/spdx/$pkg_id")->status_is(408)->content_like(qr/generated/);
    $t->app->minion->perform_jobs;
    is $t->app->minion->jobs({states => ['failed']})->total, 0, 'no failed jobs';

    my $report = decode 'UTF-8', $t->app->packages->spdx_report_path($pkg_id)->slurp;
    like $report, qr/^## Components/m,                                            'component box header present';
    like $report, qr/PackageName: leftpad/,                                       'component PackageName';
    like $report, qr/SPDXID: SPDXRef-component-$pkg_id-\d+/,                      'component SPDXID';
    like $report, qr/PackageVersion: 1\.3\.0/,                                    'component version';
    like $report, qr/PackageLicenseDeclared: MIT/,                                'component license';
    like $report, qr{ExternalRef: PACKAGE-MANAGER purl pkg:npm/leftpad\@1\.3\.0}, 'purl reference';
    like $report, qr/Relationship: SPDXRef-pkg-$pkg_id CONTAINS SPDXRef-component-$pkg_id-\d+/,
      'CONTAINS relationship from main package';

    $t->get_ok('/logout');
  };

  subtest 'JSON/TXT/MCP report formats include detected components' => sub {
    $t->get_ok('/login')->status_is(302)->header_is(Location => '/');
    my $expires = Mojo::Date->new(time + 86400)->to_datetime;
    $expires =~ s/:\d\dZ$//;
    $t->post_ok('/api_keys' => form => {expires => $expires, type => 'read-only', description => 'components test key'})
      ->status_is(200);
    $t->get_ok('/api_keys/meta')->status_is(200);
    my $key = $t->tx->res->json('/keys/0/api_key');
    $t->get_ok('/logout');

    $t->get_ok("/api/v1/report/$pkg_id.json" => {Authorization => "Bearer $key"})
      ->status_is(200)
      ->json_has('/components/0')
      ->json_is('/components/0/ecosystem', 'npm')
      ->json_is('/components/0/name',      'leftpad')
      ->json_is('/components/0/version',   '1.3.0')
      ->json_is('/components/0/license',   'MIT');

    $t->get_ok("/api/v1/report/$pkg_id.txt" => {Authorization => "Bearer $key"})
      ->status_is(200)
      ->content_like(qr/^## Components/m,               'txt has component section')
      ->content_like(qr/\[npm\] leftpad\@1\.3\.0: MIT/, 'txt lists leftpad');

    $t->get_ok("/api/v1/report/$pkg_id.mcp" => {Authorization => "Bearer $key"})
      ->status_is(200)
      ->content_like(qr/^## Components/m,               'mcp has component section')
      ->content_like(qr/\[npm\] leftpad\@1\.3\.0: MIT/, 'mcp lists leftpad');
  };

  subtest 'Review details page mounts Vue and exposes components in JSON payload' => sub {
    $t->get_ok('/login')->status_is(302)->header_is(Location => '/');

    $t->get_ok("/reviews/details/$pkg_id")
      ->status_is(200)
      ->element_exists('#report-details', 'Vue mount point present');

    $t->get_ok("/reviews/report_details/$pkg_id")
      ->status_is(200)
      ->json_has('/components/0', 'components in JSON payload')
      ->json_is('/components/0/ecosystem', 'npm')
      ->json_is('/components/0/name',      'leftpad')
      ->json_is('/components/0/version',   '1.3.0')
      ->json_is('/components/0/license',   'MIT');

    $t->get_ok('/logout');
  };

  subtest 'Reindex clears prior components (idempotency)' => sub {
    my $before = scalar @{$t->app->components->for_package($pkg_id)};
    $t->app->packages->reindex($pkg_id);
    $t->app->minion->perform_jobs;
    my $after = scalar @{$t->app->components->for_package($pkg_id)};
    is $after, $before, 'component count is stable across reindex';
  };
}

done_testing;
