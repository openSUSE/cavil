# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Mojo::Base -strict, -signatures;

use FindBin;
use lib "$FindBin::Bin/lib";

use Test::More;
use Test::Mojo;
use Cavil::Test;
use Mojo::File             qw(path tempfile);
use Mojo::JSON             qw(decode_json);
use IO::Uncompress::Gunzip qw(gunzip $GunzipError);

plan skip_all => 'set TEST_ONLINE to enable this test' unless $ENV{TEST_ONLINE};

my $cavil_test = Cavil::Test->new(online => $ENV{TEST_ONLINE}, schema => 'component_detection_test');
my $t          = Test::Mojo->new(Cavil => $cavil_test->default_config);
my $id         = $cavil_test->components_fixtures($t->app);

subtest 'Detection through the real unpack/index pipeline' => sub {
  $t->app->minion->enqueue(unpack => [$id]);
  $t->app->minion->perform_jobs;
  ok $t->app->packages->is_indexed($id), 'package indexed';
  is $t->app->minion->jobs({states => ['failed']})->total, 0, 'no failed jobs';

  my $rows    = $t->app->pg->db->select('package_components', '*', {package => $id})->hashes->to_array;
  my %by_purl = map { $_->{purl} => $_ } @$rows;
  my %names   = map { $_->{name} => 1 } @$rows;

  # Found by content despite obscured directory names and depth
  ok $by_purl{'pkg:npm/react@18.2.0'}, 'npm module under node_modules.obscpio._/package._1/ detected';
  is $by_purl{'pkg:npm/react@18.2.0'}{type},    'npm', 'ecosystem recorded';
  is $by_purl{'pkg:npm/react@18.2.0'}{license}, 'MIT', 'license from metadata';

  ok $by_purl{'pkg:cargo/serde@1.0.197'}, 'cargo crate under an obscured vendor/ dir detected';
  is $by_purl{'pkg:cargo/serde@1.0.197'}{license}, 'MIT OR Apache-2.0', 'cargo license from metadata';

  # Declared but not vendored (devDependencies with no files on disk) must NOT be invented
  ok !$names{eslint},   'declared-only devDependency eslint is not reported';
  ok !$names{prettier}, 'declared-only devDependency prettier is not reported';

  # The project's own top-level manifest is the primary artifact, not a vendored subcomponent: it must
  # not be reported (otherwise the SBOM lists the package as a dependency of itself)
  ok !$names{'my-app'},                 'root project manifest is not reported as a vendored component';
  ok !$by_purl{'pkg:npm/my-app@1.0.0'}, 'root project purl absent';

  # A module whose metadata omits the license gets it backfilled from Cavil's own detection
  ok $by_purl{'pkg:npm/no-license-mod@2.0.0'}, 'license-less module still detected';
  is $by_purl{'pkg:npm/no-license-mod@2.0.0'}{license}, 'MIT', 'license backfilled from Cavil detection';

  # A directory holding one licensed and one unlicensed component is ambiguous: the license Cavil detects
  # there must NOT be cross-attributed to the unlicensed component
  ok $by_purl{'pkg:npm/mixed-npm@1.0.0'}, 'licensed component in a mixed directory detected';
  is $by_purl{'pkg:npm/mixed-npm@1.0.0'}{license}, 'MIT', 'its own metadata license is kept';
  ok $by_purl{'pkg:cargo/mixed-crate@1.0.0'}, 'unlicensed component in a mixed directory detected';
  is $by_purl{'pkg:cargo/mixed-crate@1.0.0'}{license}, undef,
    'unlicensed component in a mixed-license directory is not backfilled';
};

subtest 'Components in the SPDX report' => sub {
  my $tmp = tempfile;
  $t->app->spdx->generate_to_file($id, "$tmp");
  gunzip("$tmp" => \my $buffer) or die "gunzip failed: $GunzipError";
  my $doc = decode_json($buffer);

  my @graph   = @{$doc->{'@graph'}};
  my %by_id   = map { ($_->{spdxId} // $_->{'@id'}) => $_ } @graph;
  my ($sbom)  = grep { ($_->{type} // '') eq 'software_Sbom' } @graph;
  my $primary = $sbom->{rootElement}[0];

  # Each detected component is a software_Package carrying its purl
  my %component;
  for my $n (grep { ($_->{type} // '') eq 'software_Package' } @graph) {
    $component{$_->{identifier}} = $n for @{$n->{externalIdentifier} // []};
  }
  ok $component{'pkg:npm/react@18.2.0'},    'react is a software_Package with its purl';
  ok $component{'pkg:cargo/serde@1.0.197'}, 'serde is a software_Package with its purl';

  # Version carried on the component element
  is $component{'pkg:npm/react@18.2.0'}{software_packageVersion},    '18.2.0',  'component version in SPDX';
  is $component{'pkg:cargo/serde@1.0.197'}{software_packageVersion}, '1.0.197', 'cargo component version in SPDX';

  # Relationships from the primary component, indexed by (type, target)
  my %rel;
  for my $r (grep { ($_->{type} // '') eq 'Relationship' && $_->{from} eq $primary } @graph) {
    push @{$rel{$r->{relationshipType}}}, $r;
  }

  # License expression carried by each component, per relationship type
  my (%concluded, %declared);
  for my $r (grep { ($_->{type} // '') eq 'Relationship' } @graph) {
    my $expr = $by_id{$r->{to}[0]}{simplelicensing_licenseExpression} // next;
    $concluded{$r->{from}} = $expr if $r->{relationshipType} eq 'hasConcludedLicense';
    $declared{$r->{from}}  = $expr if $r->{relationshipType} eq 'hasDeclaredLicense';
  }

  # Each component is a dependency of the primary (with completeness), and carries both the required
  # distribution licence (hasConcludedLicense) and the original licence (hasDeclaredLicense)
  for my $spec (
    ['pkg:npm/react@18.2.0', 'MIT'], ['pkg:cargo/serde@1.0.197', 'MIT OR Apache-2.0'],
    ['pkg:npm/no-license-mod@2.0.0', 'MIT'],    # backfilled from Cavil detection, flows into SPDX
    )
  {
    my ($purl, $license) = @$spec;
    my $cid = $component{$purl}{spdxId};
    my ($depends) = grep { $_->{to}[0] eq $cid } @{$rel{dependsOn} // []};
    ok $depends, "primary dependsOn $purl";
    is $depends->{completeness}, 'complete', "$purl dependency completeness";
    is $concluded{$cid},         $license,   "$purl distribution licence (concluded) in SPDX";
    is $declared{$cid},          $license,   "$purl original licence (declared) in SPDX";
  }

  # Referential integrity: every reference (including the new component/dependency/license nodes) resolves
  my @dangling;
  for my $n (@graph) {
    my @refs = grep {defined} $n->{creationInfo}, $n->{from}, $n->{subject}, $n->{software_snippetFromFile};
    push @refs,     @{$n->{$_} // []} for qw(createdBy createdUsing rootElement originatedBy to);
    push @dangling, $_                for grep { !$by_id{$_} } @refs;
  }
  is_deeply \@dangling, [], 'no dangling references with components present';

  # Still schema-valid with the components present
  my $validator = eval {
    require JSON::Validator;
    my $v = JSON::Validator->new;
    $v->schema("$FindBin::Bin/resources/spdx-3.0.1-schema.json");
    $v;
  };
SKIP: {
    skip "JSON::Validator unavailable: $@", 1 unless $validator;
    my @errors = $validator->validate($doc);
    ok !@errors, 'document with components validates against the SPDX 3.0.1 schema'
      or diag join "\n", map {"$_"} @errors;
  }
};

subtest 'Components in the report data (UI/MCP)' => sub {
  my $report  = $t->app->reports->sanitized_dig_report($id);
  my %by_name = map { $_->{name} => $_ } @{$report->{components}};
  ok $by_name{react}, 'report lists the react component';
  is $by_name{react}{version}, '18.2.0',               'with version';
  is $by_name{react}{purl},    'pkg:npm/react@18.2.0', 'with purl';
  is $by_name{react}{type},    'npm',                  'with ecosystem';

  # The backfilled license must reach the cached report too, not only the SPDX export (they are built
  # from the same data and must agree)
  is $by_name{'no-license-mod'}{license}, 'MIT', 'backfilled license reaches the report data';
};

subtest 'Component enrichment in the report_details JSON (UI)' => sub {
  $t->get_ok('/login')->status_is(302);
  my $details = $t->get_ok("/reviews/report_details/$id")->status_is(200)->tx->res->json;
  my %by_name = map { $_->{name} => $_ } @{$details->{components}};

  my $react = $by_name{react};
  ok $react, 'react component present in report_details';
  like $react->{file_url},     qr{/reviews/file_view/$id/}, 'name links to the metadata file in the file browser';
  like $react->{license_html}, qr/spdx-link/,               'license rendered as a clickable SPDX link';
  like $react->{license_html}, qr/MIT/,                     'license text present';

  # The backfilled license is a clickable link too (consistent rendering for every license)
  like $by_name{'no-license-mod'}{license_html}, qr/spdx-link/, 'backfilled license is a clickable SPDX link';

  # A component whose imported metadata carries a malicious license string must not become a stored XSS
  # vector: license_html is rendered with v-html, so the untrusted markup has to be HTML-escaped while
  # the recognised SPDX id is still linked
  my $evil = $by_name{'evil-mod'};
  ok $evil, 'component with malicious license metadata is still detected';
  like $evil->{license_html},   qr/spdx-link/,           'recognised SPDX id in a malicious string is still linked';
  like $evil->{license_html},   qr/&lt;img/,             'injected markup is HTML-escaped';
  unlike $evil->{license_html}, qr/<img/,                'no raw markup reaches the DOM';
  unlike $evil->{license_html}, qr/onerror=alert\(1\)>/, 'payload cannot break out of text';
};

subtest 'Reindex clears and repopulates' => sub {
  $t->app->packages->reindex($id);
  $t->app->minion->perform_jobs;
  my $count = $t->app->pg->db->select('package_components', 'count(*)', {package => $id})->array->[0];
  ok $count >= 2, 'components still present after reindex (no duplication)';
  is $t->app->pg->db->query('SELECT count(*) FROM package_components WHERE package = ? AND purl = ?',
    $id, 'pkg:npm/react@18.2.0')->array->[0], 1, 'react present exactly once';
};

subtest 'Root-level Go vendoring is read (listing files are exempt from the root-skip)' => sub {
  my $gid = $cavil_test->go_vendor_fixtures($t->app);
  $t->app->minion->enqueue(unpack => [$gid]);
  $t->app->minion->perform_jobs;
  ok $t->app->packages->is_indexed($gid), 'go-vendor package indexed';

  my %by_purl = map { $_->{purl} => 1 }
    @{$t->app->pg->db->select('package_components', 'purl', {package => $gid})->hashes->to_array};

  # vendor/modules.txt sits at the root of the unpacked tree (depth <= 1); a package manifest there would
  # be skipped as the primary, but a listing file must still be read
  ok $by_purl{'pkg:golang/github.com/gorilla/mux@v1.8.1'}, 'root-level vendor/modules.txt is read';
  ok $by_purl{'pkg:golang/golang.org/x/sys@v0.16.0'},      'all modules from the root listing detected';
};

subtest 'Depth-1 vendored archives are kept when several archives unpack side by side' => sub {
  my $mid = $cavil_test->multiarchive_fixtures($t->app);
  $t->app->minion->enqueue(unpack => [$mid]);
  $t->app->minion->perform_jobs;
  ok $t->app->packages->is_indexed($mid), 'multiarchive package indexed';

  my %by_purl = map { $_->{purl} => 1 }
    @{$t->app->pg->db->select('package_components', 'purl', {package => $mid})->hashes->to_array};

  # serde-1.0.197/Cargo.toml is at depth 1 but the tree has multiple top-level directories, so it is a
  # separately-vendored archive, not the primary wrapper - it must be reported
  ok $by_purl{'pkg:cargo/serde@1.0.197'}, 'depth-1 vendored crate archive is detected';

  # A deeply nested module in the main archive is detected as before
  ok $by_purl{'pkg:npm/inner@2.0.0'}, 'nested vendored module in the main archive is detected';
};

done_testing;
