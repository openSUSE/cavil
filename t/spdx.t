# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Mojo::Base -strict, -signatures;

use FindBin;
use lib "$FindBin::Bin/lib";

use Test::More;
use Test::Mojo;
use Cavil::Test;
use Cavil::SPDX;
use Mojolicious::Lite;
use Mojo::File             qw(path tempfile);
use Mojo::JSON             qw(decode_json);
use IO::Uncompress::Gunzip qw(gunzip $GunzipError);
use Digest::SHA;

plan skip_all => 'set TEST_ONLINE to enable this test' unless $ENV{TEST_ONLINE};

my $cavil_test = Cavil::Test->new(online => $ENV{TEST_ONLINE}, schema => 'spdx_test');
my $t          = Test::Mojo->new(Cavil => $cavil_test->default_config);
$cavil_test->spdx_fixtures($t->app);

# Make the "Apache-2.0" pattern unknown to SPDX, so it has to fall back to a ScanCode identifier
$t->app->pg->db->query('UPDATE license_patterns SET spdx = ? WHERE license = ?', '', 'Apache-2.0');

# Index by spdxId (or blank node @id) for easy graph lookups
sub graph_index ($doc) {
  return {map { ($_->{spdxId} // $_->{'@id'}) => $_ } @{$doc->{'@graph'}}};
}

sub of_type ($doc, $type) {
  return [grep { ($_->{type} // '') eq $type } @{$doc->{'@graph'}}];
}

# All license expressions listed anywhere in the document
sub license_exprs ($doc) {
  return [map { $_->{simplelicensing_licenseExpression} } @{of_type($doc, 'simplelicensing_LicenseExpression')}];
}

# Decompress and parse a gzip-compressed SPDX report from disk
sub read_report ($path) {
  gunzip("$path" => \my $buffer) or die "gunzip failed: $GunzipError";
  return decode_json($buffer);
}

# Generate a fresh SPDX report for package 1 (with whatever config/data is currently set) and parse it
sub gen_doc {
  my $tmp = tempfile;
  $t->app->spdx->generate_to_file(1, "$tmp");
  return read_report("$tmp");
}

# Shared schema validator, built once (skips gracefully if JSON::Validator cannot handle the schema)
my $validator = eval {
  require JSON::Validator;
  my $v = JSON::Validator->new;
  $v->schema("$FindBin::Bin/resources/spdx-3.0.1-schema.json");
  $v;
};

sub schema_ok ($doc, $desc) {
SKIP: {
    skip "JSON::Validator cannot load the SPDX schema: $@", 1 unless $validator;
    my @errors = $validator->validate($doc);
    ok !@errors, $desc or diag join "\n", map {"$_"} @errors;
  }
}

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
  $t->get_ok('/spdx/1')->status_is(408)->content_like(qr/generated/)->content_unlike(qr/\@graph/);
  $t->get_ok('/spdx/1')->status_is(408)->content_like(qr/generated/)->content_unlike(qr/\@graph/);
  $t->app->minion->perform_jobs;
  is $t->app->minion->jobs({states => ['failed']})->total, 0, 'no failed jobs';
  ok $t->app->packages->has_spdx_report(1), 'package has SPDX report';

  # gzip-capable client (Mojo's UA sends "Accept-Encoding: gzip" and transparently decompresses)
  $t->get_ok('/spdx/1')->status_is(200)->content_type_is('application/json')->json_has('/@graph');

  # Client that does not accept gzip gets the report decompressed on the fly, without a gzip encoding
  $t->get_ok('/spdx/1' => {'Accept-Encoding' => 'identity'})
    ->status_is(200)
    ->content_type_is('application/json')
    ->header_is('Content-Encoding' => undef)
    ->json_has('/@graph');

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

my $path = $t->app->packages->spdx_report_path(1);
my $doc  = read_report($path);
my $g    = graph_index($doc);

subtest 'Report is stored gzip-compressed on disk' => sub {
  ok !-e "$path.tmp", 'SPDX temp file has been cleaned up';
  is $path->basename,            '.report.spdx.json.gz', 'report is a gzip-compressed JSON file';
  is substr($path->slurp, 0, 2), "\x1f\x8b",             'on-disk report has the gzip magic bytes';
};

subtest 'Legacy reports are cleaned up' => sub {
  my $dir = $t->app->packages->pkg_checkout_dir(1);

  # Reports left behind by older Cavil versions: pre-3.0.1 tag-value, and interim uncompressed JSON
  my @legacy = qw(.report.spdx .report.processed.spdx .report.spdx.json .report.processed.spdx.json);
  $dir->child($_)->spew('legacy') for @legacy;
  ok -e $dir->child($_), "legacy report $_ exists" for @legacy;
  ok $t->app->packages->has_spdx_report(1), 'the current report exists';

  $t->app->packages->remove_spdx_report(1);

  ok !-e $dir->child($_),                    "legacy report $_ removed" for @legacy;
  ok !$t->app->packages->has_spdx_report(1), 'current report removed';
};

subtest 'Valid SPDX 3.0.1 JSON document' => sub {
  is $doc->{'@context'}, 'https://spdx.org/rdf/3.0.1/spdx-context.jsonld', 'has SPDX 3.0.1 context';
  ok ref $doc->{'@graph'} eq 'ARRAY', 'has an element graph';
  schema_ok($doc, 'document validates against the official SPDX 3.0.1 JSON schema');
};

subtest 'Graph is internally consistent' => sub {

  # Every element has a type and an identifier, and identifiers are unique (aggregated to avoid per-element noise)
  my (%ids, @untyped, @unidentified, %seen, @duplicates);
  for my $node (@{$doc->{'@graph'}}) {
    push @untyped, $node unless $node->{type};
    my $id = $node->{spdxId} // $node->{'@id'};
    if   (!defined $id) { push @unidentified, $node->{type} }
    else                { push @duplicates,   $id if $seen{$id}++; $ids{$id} = 1 }
  }
  is_deeply \@untyped,      [], 'every element has a type';
  is_deeply \@unidentified, [], 'every element has an identifier';
  is_deeply \@duplicates,   [], 'all identifiers are unique';

  # Every reference (creationInfo, relationships, root elements, agents) resolves to an element in the graph
  my @dangling;
  for my $node (@{$doc->{'@graph'}}) {
    my @refs = grep {defined} $node->{creationInfo}, $node->{from}, $node->{subject}, $node->{software_snippetFromFile};
    push @refs,     @{$node->{$_} // []} for qw(createdBy createdUsing rootElement originatedBy to);
    push @dangling, $_                   for grep { !$ids{$_} } @refs;
  }
  is_deeply \@dangling, [], 'no dangling references in the graph';
};

subtest 'Creation information (BSI: creator and timestamp)' => sub {
  my $ci = of_type($doc, 'CreationInfo')->[0];
  is $ci->{specVersion}, '3.0.1', 'SPDX 3.0.1';
  like $ci->{created}, qr/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$/, 'ISO-8601 UTC timestamp';

  my $creator = $g->{$ci->{createdBy}[0]};
  is $creator->{type}, 'Organization', 'creator is an organization';
  is $creator->{name}, 'SUSE LLC',     'creator name';
  is_deeply $creator->{externalIdentifier},
    [{type => 'ExternalIdentifier', externalIdentifierType => 'email', identifier => 'security@suse.de'}],
    'creator has an email identifier';

  my $tool = $g->{$ci->{createdUsing}[0]};
  is $tool->{type}, 'Tool',  'created using a tool';
  is $tool->{name}, 'Cavil', 'the tool is Cavil';
};

subtest 'SBOM document (BSI: SBOM-URI)' => sub {
  my $sbom = of_type($doc, 'software_Sbom')->[0];
  is $sbom->{spdxId}, 'http://legaldb.suse.de/spdx/1', 'SBOM-URI';
  is_deeply $sbom->{software_sbomType}, ['source'], 'source SBOM';

  my $primary = $g->{$sbom->{rootElement}[0]};
  is $primary->{type}, 'software_Package', 'root element is the primary component';
  is $primary->{name}, 'perl-Mojolicious', 'primary component name';

  my $document = of_type($doc, 'SpdxDocument')->[0];
  is_deeply $document->{rootElement}, [$sbom->{spdxId}], 'document root element is the SBOM';
};

subtest 'Primary component (BSI: required and additional fields)' => sub {
  my ($primary) = grep { $_->{name} eq 'perl-Mojolicious' } @{of_type($doc, 'software_Package')};

  is $primary->{software_packageVersion}, '7.25',                                     'component version';
  is $primary->{software_homePage},       'http://search.cpan.org/dist/Mojolicious/', 'home page';
  like $primary->{software_downloadLocation}, qr{api\.opensuse\.org/source/devel:languages:perl/perl-Mojolicious},
    'download location from OBS coordinates';

  # The deployable component hash is on the delivered source archive, not the package itself, and not
  # on every unpacked file
  ok !$primary->{verifiedUsing}, 'the package carries no synthetic digest-of-hashes';
  my @artifacts
    = map { $g->{$_->{to}[0]} }
    grep  { $_->{from} eq $primary->{spdxId} && $_->{relationshipType} eq 'hasDistributionArtifact' }
    @{of_type($doc, 'Relationship')};
  is scalar(@artifacts),  1,                               'exactly one distribution artifact (the source archive)';
  is $artifacts[0]{name}, './Mojolicious-7.25.tar.gz',     'the source archive is the deployable artifact';
  is $artifacts[0]{verifiedUsing}[0]{algorithm}, 'sha512', 'deployable component hashed with SHA-512';
  my $tarball = $t->app->packages->pkg_checkout_dir(1)->child('Mojolicious-7.25.tar.gz');
  is $artifacts[0]{verifiedUsing}[0]{hashValue}, Digest::SHA->new('512')->addfile("$tarball")->hexdigest,
    'artifact hash matches the actual archive on disk';

  # BSI executable/archive/structured properties on the deployable form (archive + structured, non-executable)
  is_deeply $artifacts[0]{software_additionalPurpose}, ['archive', 'container'],
    'deployable form carries the BSI archive and structured properties';

  is_deeply $primary->{externalIdentifier},
    [
    {
      type                   => 'ExternalIdentifier',
      externalIdentifierType => 'packageUrl',
      identifier             => 'pkg:generic/perl-Mojolicious@7.25'
    }
    ],
    'package URL identifier';

  my $origin = $g->{$primary->{originatedBy}[0]};
  is $origin->{type}, 'Organization', 'component originator';

  # Declared (original) and concluded (distribution) licenses
  my %rel_by_type;
  for my $rel (@{of_type($doc, 'Relationship')}) {
    next unless $rel->{from} eq $primary->{spdxId};
    push @{$rel_by_type{$rel->{relationshipType}}}, $rel;
  }
  for my $type (qw(hasConcludedLicense hasDeclaredLicense)) {
    my $rel = $rel_by_type{$type}[0];
    ok $rel, "primary component has $type";
    is $rel->{completeness},                                   'complete',     "$type completeness is indicated";
    is $g->{$rel->{to}[0]}{simplelicensing_licenseExpression}, 'Artistic-2.0', "$type is Artistic-2.0";
  }
};

subtest 'Subcomponent derived from an unpacked archive' => sub {
  my ($sub) = grep { $_->{name} eq 'Mojolicious' } @{of_type($doc, 'software_Package')};
  ok $sub, 'has a Mojolicious subcomponent';
  is $sub->{software_packageVersion}, '7.25', 'version parsed from the directory name';

  my ($primary) = grep { $_->{name} eq 'perl-Mojolicious' } @{of_type($doc, 'software_Package')};
  my $contained
    = grep { $_->{from} eq $primary->{spdxId} && $_->{relationshipType} eq 'contains' && $_->{to}[0] eq $sub->{spdxId} }
    @{of_type($doc, 'Relationship')};
  ok $contained, 'primary component contains the subcomponent';
};

subtest 'Files (BSI: filename, hash, dependencies)' => sub {
  my $files = of_type($doc, 'software_File');
  ok @$files > 1, 'has file components';

  my ($license) = grep { $_->{name} eq './Mojolicious-7.25/LICENSE' } @$files;
  ok $license,                   'has the LICENSE file';
  ok !$license->{verifiedUsing}, 'unpacked files are not individually hashed';
  like $license->{software_copyrightText}, qr/Copyright.*2006.*The Perl Foundation/, 'file copyright text';

  # Copyrights are scanned from whole files, not just license-match regions, so several files carry them
  my $with_copyright = grep { defined $_->{software_copyrightText} } @$files;
  ok $with_copyright > 1, 'copyright statements are unearthed from multiple files';

  # A minified file whose copyright lives in a short comment header: the header copyright is captured,
  # and the long-line guard (against minified blobs) does not drop it
  my ($prettify) = grep { $_->{name} =~ m{run_prettify\.js$} } @$files;
  ok $prettify, 'has the minified run_prettify.js file';
  like $prettify->{software_copyrightText}, qr/Copyright.*Google/, 'header copyright captured even in a minified file';

  # Every file is contained by some component (dependency enumeration)
  my %contained;
  for my $rel (@{of_type($doc, 'Relationship')}) {
    $contained{$rel->{to}[0]} = 1 if $rel->{relationshipType} eq 'contains';
  }
  ok $contained{$license->{spdxId}}, 'LICENSE file is contained by a component';
};

subtest 'License identifiers (BSI section 6.1)' => sub {
  my %expr = map { $_ => 1 } @{license_exprs($doc)};

  ok $expr{'Artistic-2.0'},                   'uses SPDX identifiers when available';
  ok $expr{'LicenseRef-scancode-apache-2.0'}, 'falls back to a ScanCode identifier for non-SPDX licenses';
  ok((grep {/^LicenseRef-cavil-/} keys %expr), 'falls back to a LicenseRef-<entity> identifier when unknown');
};

subtest 'License risk annotations (Cavil legal assessment)' => sub {
  my @annotations = @{of_type($doc, 'Annotation')};
  ok @annotations,                                                     'has license annotations';
  ok !(grep { ($_->{annotationType} // '') ne 'other' } @annotations), 'all annotations are of type "other"';

  # Map annotated license expression -> statement
  my %statement = map { $g->{$_->{subject}}{simplelicensing_licenseExpression} => $_->{statement} } @annotations;
  like $statement{'Artistic-2.0'}, qr/risk: 5/, 'primary component license carries its Cavil risk level';
  like $statement{'LicenseRef-scancode-apache-2.0'}, qr/Cavil legal assessment.*risk: \d/,
    'detected licenses carry their Cavil risk level';
};

subtest 'License match evidence (snippets)' => sub {
  my $snippets = of_type($doc, 'software_Snippet');
  ok @$snippets, 'has snippet evidence for license matches';

  my %snippet_has_license;
  for my $rel (@{of_type($doc, 'Relationship')}) {
    $snippet_has_license{$rel->{from}} = 1 if $rel->{relationshipType} eq 'hasConcludedLicense';
  }

  my ($bad_file, $bad_range, $bad_license) = (0, 0, 0);
  for my $snippet (@$snippets) {
    $bad_file++ unless $g->{$snippet->{software_snippetFromFile}};
    my $range = $snippet->{software_lineRange};
    $bad_range++
      unless $range
      && $range->{type} eq 'PositiveIntegerRange'
      && $range->{beginIntegerRange} >= 1
      && $range->{endIntegerRange} >= $range->{beginIntegerRange};
    $bad_license++ unless $snippet_has_license{$snippet->{spdxId}};
  }
  is $bad_file,    0, 'every snippet points at a file in the graph';
  is $bad_range,   0, 'every snippet has a valid line range';
  is $bad_license, 0, 'every snippet has a concluded license';
};

# The remaining subtests regenerate the report with different configuration/data, restoring state afterwards
my $spdx_config = $t->app->config->{spdx};

subtest 'Creator identity is configurable (URL fallback and defaults)' => sub {

  # A creator with a URL but no email must use a "urlScheme" identifier
  $t->app->config->{spdx} = {%$spdx_config, creator => {name => 'ACME Corp', url => 'https://acme.example/'}};
  my $url_doc = gen_doc();
  my $ci      = of_type($url_doc, 'CreationInfo')->[0];
  my %by_id   = map { ($_->{spdxId} // $_->{'@id'}) => $_ } @{$url_doc->{'@graph'}};
  my $creator = $by_id{$ci->{createdBy}[0]};
  is $creator->{name}, 'ACME Corp', 'configured creator name';
  is_deeply $creator->{externalIdentifier},
    [{type => 'ExternalIdentifier', externalIdentifierType => 'urlScheme', identifier => 'https://acme.example/'}],
    'creator without an email uses a URL identifier';
  schema_ok($url_doc, 'URL-creator document still validates');

  # Without any SPDX configuration at all, sensible defaults are used
  $t->app->config->{spdx} = undef;
  my $default_doc = gen_doc();
  my $dci         = of_type($default_doc, 'CreationInfo')->[0];
  my %dby_id      = map { ($_->{spdxId} // $_->{'@id'}) => $_ } @{$default_doc->{'@graph'}};
  is $dby_id{$dci->{createdBy}[0]}{name},    'Cavil', 'defaults to Cavil as the creator';
  is $dby_id{$dci->{createdUsing}[0]}{name}, 'Cavil', 'defaults to Cavil as the tool';

  $t->app->config->{spdx} = $spdx_config;
};

subtest 'LicenseRef namespace is configurable' => sub {
  $t->app->config->{spdx} = {%$spdx_config, license_ref_namespace => 'acme'};
  my %expr = map { $_ => 1 } @{license_exprs(gen_doc())};
  ok((grep {/^LicenseRef-acme-/} keys %expr),   'unknown licenses use the configured LicenseRef namespace');
  ok((!grep {/^LicenseRef-cavil-/} keys %expr), 'the default namespace is no longer used');
  $t->app->config->{spdx} = $spdx_config;
};

subtest 'Legal flags are annotated' => sub {
  my $db = $t->app->pg->db;
  $db->query('UPDATE license_patterns SET patent = true, export_restricted = true WHERE license = ?', 'Apache-2.0');

  my $flag_doc  = gen_doc();
  my $fg        = graph_index($flag_doc);
  my %statement = map { $fg->{$_->{subject}}{simplelicensing_licenseExpression} => $_->{statement} }
    @{of_type($flag_doc, 'Annotation')};
  like $statement{'LicenseRef-scancode-apache-2.0'}, qr/flags: .*patent/, 'patent flag is surfaced';
  like $statement{'LicenseRef-scancode-apache-2.0'}, qr/flags: .*export_restricted/,
    'export-restricted flag is surfaced';

  $db->query('UPDATE license_patterns SET patent = false, export_restricted = false WHERE license = ?', 'Apache-2.0');
};

subtest 'Packages without Open Build Service coordinates (e.g. uploads)' => sub {
  my $db        = $t->app->pg->db;
  my $source_id = $db->query('SELECT source FROM bot_packages WHERE id = 1')->hash->{source};
  my $original  = $db->query('SELECT api_url, project FROM bot_sources WHERE id = ?', $source_id)->hash;
  $db->query('UPDATE bot_sources SET api_url = ?, project = ? WHERE id = ?', '', '', $source_id);

  my $upload_doc = gen_doc();
  my ($primary) = grep { $_->{name} eq 'perl-Mojolicious' } @{of_type($upload_doc, 'software_Package')};
  ok !exists $primary->{software_downloadLocation}, 'no download location without OBS coordinates';
  ok !exists $primary->{originatedBy},              'no originator without OBS coordinates';
  is $primary->{software_packageVersion}, '7.25', 'version is still present';
  schema_ok($upload_doc, 'upload-style document still validates');

  $db->query('UPDATE bot_sources SET api_url = ?, project = ? WHERE id = ?',
    $original->{api_url}, $original->{project}, $source_id);
};

subtest 'SPDX report is obsolete' => sub {
  $t->get_ok('/login')->status_is(302)->header_is(Location => '/');

  is $t->app->pg->db->query('UPDATE bot_packages SET obsolete = true WHERE id = any(?)', [1])->rows, 1,
    'one package obsoleted';
  $t->get_ok('/spdx/1')->status_is(410)->content_like(qr/package is obsolete/);

  $t->get_ok('/logout')->status_is(302)->header_is(Location => '/');
};

done_testing;
