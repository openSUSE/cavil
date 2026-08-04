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
use Mojo::File qw(path tempfile);
use Mojo::JSON qw(decode_json);
use Mojo::Date;
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

# Relationships of one type, optionally only those originating from a given element
sub rels ($doc, $type, $from = undef) {
  return [grep { $_->{relationshipType} eq $type && (!defined $from || $_->{from} eq $from) }
      @{of_type($doc, 'Relationship')}];
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

# Generate a fresh SPDX report (with whatever config/data is currently set) and parse it
sub gen_doc ($id = 1) {
  my $tmp = tempfile;
  $t->app->spdx->generate_to_file($id, "$tmp");
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

  # gzip-capable client (Mojo's UA sends "Accept-Encoding: gzip" and transparently decompresses). Gzip is
  # only the transfer encoding, so the file the browser saves is the JSON the disposition names.
  $t->get_ok('/spdx/1')
    ->status_is(200)
    ->content_type_is('application/json')
    ->header_is('Content-Disposition' => 'attachment; filename="1.spdx.json"')
    ->json_has('/@graph');

  # Client that does not accept gzip gets the report decompressed on the fly, without a gzip encoding
  $t->get_ok('/spdx/1' => {'Accept-Encoding' => 'identity'})
    ->status_is(200)
    ->content_type_is('application/json')
    ->header_is('Content-Encoding'    => undef)
    ->header_is('Content-Disposition' => 'attachment; filename="1.spdx.json"')
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

# A build that dies on the way to its report must not leave the package unable to ever get one again. The
# job that would have written it waits in the queue behind its failed parent, where an admin can see it and
# retry - and nothing outside the queue is holding a claim on the work that could outlive the build.
subtest 'A build whose analyzed job fails still gets its report from a retry' => sub {
  my $minion = $t->app->minion;
  my $pkgs   = $t->app->packages;
  $pkgs->remove_spdx_report(1);

  my $analyzed = $minion->tasks->{analyzed};
  $minion->add_task(analyzed => sub ($job, @args) { die "Auto review went wrong\n" });
  is $pkgs->reindex(1), 'now', 'reindex queued';
  $minion->perform_jobs;
  $minion->add_task(analyzed => $analyzed);

  ok !$pkgs->has_spdx_report(1), 'package has no SPDX report';
  is $minion->jobs({tasks => ['analyzed'],    states => ['failed']})->total,   1, 'the analyzed job failed';
  is $minion->jobs({tasks => ['spdx_report'], states => ['inactive']})->total, 1, 'the report job is still queued';
  is $t->app->pg->db->query('SELECT COUNT(*) FROM minion_locks')->array->[0], 0, 'nothing is locked';

  # What an admin does from the Minion dashboard
  my $failed = $minion->jobs({tasks => ['analyzed'], states => ['failed']})->next;
  ok $minion->job($failed->{id})->retry, 'analyzed job retried';
  $minion->perform_jobs;

  is $minion->jobs({states => ['failed']})->total, 0, 'no failed jobs';
  ok $pkgs->has_spdx_report(1), 'package has SPDX report';
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

  # Every reference (creationInfo, relationships, root elements, agents) resolves to an element in the graph,
  # or to one of the individuals SPDX itself defines for "nothing is asserted here" and "there is nothing here"
  my %individual = map { $_ => 1 } 'expandedlicensing_NoAssertionLicense',
    'https://spdx.org/rdf/3.0.1/terms/Core/NoAssertionElement', 'https://spdx.org/rdf/3.0.1/terms/Core/NoneElement';
  my @dangling;
  for my $node (@{$doc->{'@graph'}}) {
    my @refs = grep {defined} $node->{creationInfo}, $node->{from}, $node->{subject},
      $node->{software_snippetFromFile}, $node->{dataLicense};
    push @refs,     @{$node->{$_} // []} for qw(createdBy createdUsing rootElement originatedBy to);
    push @dangling, $_                   for grep { !$ids{$_} && !$individual{$_} } @refs;
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

  # The tool name and the tool version are two separate things a consumer is entitled to, and the name
  # has to stay a bare "Cavil", so the version travels alongside it as a package URL
  is_deeply $tool->{externalIdentifier},
    [
    {
      type                   => 'ExternalIdentifier',
      externalIdentifierType => 'packageUrl',
      identifier             => 'pkg:generic/cavil@' . Cavil->VERSION
    }
    ],
    'the tool carries its own version';
};

subtest 'SBOM document (BSI: SBOM-URI)' => sub {
  my $sbom = of_type($doc, 'software_Sbom')->[0];
  is $sbom->{spdxId}, 'http://legaldb.suse.de/spdx/1', 'SBOM-URI';
  is_deeply $sbom->{software_sbomType}, ['source'], 'source SBOM';

  # The URI is the same for every rebuild of this package, so the iteration counter is the only thing
  # telling a recipient which of two documents with that URI is the newer one
  my ($version) = grep { ($_->{comment} // '') eq 'SBOM version' } @{$sbom->{externalIdentifier}};
  like $version->{identifier}, qr/^1\.\d+$/, 'the SBOM carries an iteration number';

  # What is unknown is stated once for the document, rather than repeated on thousands of components
  like $sbom->{comment}, qr/Unknown information is stated rather than omitted/,
    'the document says how it handles unknowns';
  like $sbom->{comment}, qr/Nothing is withheld/, 'and that nothing is being held back';

  my $primary = $g->{$sbom->{rootElement}[0]};
  is $primary->{type}, 'software_Package', 'root element is the primary component';
  is $primary->{name}, 'perl-Mojolicious', 'primary component name';

  my $document = of_type($doc, 'SpdxDocument')->[0];
  is_deeply $document->{rootElement}, [$sbom->{spdxId}], 'document root element is the SBOM';

  # The data license is referenced as an in-graph license element (an AnyLicenseInfo), not a bare URL,
  # so it validates under SPDX 3.0 (dataLicense is an object reference, not a string)
  my $data_license = $g->{$document->{dataLicense}};
  is $data_license->{type}, 'simplelicensing_LicenseExpression',    'data license is a license element';
  is $data_license->{simplelicensing_licenseExpression}, 'CC0-1.0', 'data license is CC0-1.0';
};

subtest 'Primary component (BSI: required and additional fields)' => sub {
  my ($primary) = grep { $_->{name} eq 'perl-Mojolicious' } @{of_type($doc, 'software_Package')};

  is $primary->{software_packageVersion}, '7.25',                                     'component version';
  is $primary->{software_homePage},       'http://search.cpan.org/dist/Mojolicious/', 'home page';
  like $primary->{software_downloadLocation}, qr{api\.opensuse\.org/source/devel:languages:perl/perl-Mojolicious},
    'download location from OBS coordinates';

  # BSI 5.2.4 "Source code URI": the utilised (distribution) source, version-pinned, as a VCS reference
  is_deeply $primary->{externalRef},
    [
    {
      type            => 'ExternalRef',
      externalRefType => 'vcs',
      locator         =>
        ['https://api.opensuse.org/source/devel:languages:perl/perl-Mojolicious?rev=bd91c36647a5d3dd883d490da2140401']
    }
    ],
    'source code URI is the version-pinned OBS source, as a VCS reference';

  my @artifacts = map { $g->{$_->{to}[0]} } @{rels($doc, 'hasDistributionArtifact', $primary->{spdxId})};
  is scalar(@artifacts),  1,                               'exactly one distribution artifact (the source archive)';
  is $artifacts[0]{name}, './Mojolicious-7.25.tar.gz',     'the source archive is the deployable artifact';
  is $artifacts[0]{verifiedUsing}[0]{algorithm}, 'sha512', 'deployable component hashed with SHA-512';
  my $tarball = $t->app->packages->pkg_checkout_dir(1)->child('Mojolicious-7.25.tar.gz');
  is $artifacts[0]{verifiedUsing}[0]{hashValue}, Digest::SHA->new('512')->addfile("$tarball")->hexdigest,
    'artifact hash matches the actual archive on disk';

  # The primary component carries the same content digest as its delivered artifact, so it has a
  # verifiable checksum of its own (not a synthetic digest-of-hashes of the unpacked tree)
  is $primary->{verifiedUsing}[0]{algorithm}, 'sha512', 'primary component hashed with SHA-512';
  is $primary->{verifiedUsing}[0]{hashValue}, $artifacts[0]{verifiedUsing}[0]{hashValue},
    'primary component digest matches the delivered archive';

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

  my ($bad_file, $bad_range, $bad_license, $bad_name) = (0, 0, 0, 0);
  for my $snippet (@$snippets) {
    $bad_file++ unless $g->{$snippet->{software_snippetFromFile}};
    my $range = $snippet->{software_lineRange};
    $bad_range++
      unless $range
      && $range->{type} eq 'PositiveIntegerRange'
      && $range->{beginIntegerRange} >= 1
      && $range->{endIntegerRange} >= $range->{beginIntegerRange};
    $bad_license++ unless $snippet_has_license{$snippet->{spdxId}};

    # A location-based name (file plus line range) so the snippet is a self-describing element and not
    # an anonymous node (SBOM quality tools flag components without a name)
    $bad_name++
      unless defined $snippet->{name}
      && $snippet->{name} eq
      "$g->{$snippet->{software_snippetFromFile}}{name}#L$range->{beginIntegerRange}-L$range->{endIntegerRange}";
  }
  is $bad_file,    0, 'every snippet points at a file in the graph';
  is $bad_range,   0, 'every snippet has a valid line range';
  is $bad_license, 0, 'every snippet has a concluded license';
  is $bad_name,    0, 'every snippet has a location-based name';
};

# Ranges are stored against the ".processed" copy the indexer scanned, and reported against the
# original file. run_prettify.js is post-processed (its minified body is line-wrapped) but every
# match sits in the comment header above the first wrap, so the translation must be a no-op here -
# a translator that invented a shift would show up as ranges pointing into the minified blob
subtest 'Line ranges are the original file\'s, not the scanned copy\'s' => sub {
  my ($prettify) = grep { $_->{name} =~ m{run_prettify\.js$} } @{of_type($doc, 'software_File')};
  unlike $prettify->{name}, qr/\.processed\./, 'the file is reported under its original name';

  my @ranges = map { $_->{software_lineRange} }
    grep { $_->{software_snippetFromFile} eq $prettify->{spdxId} } @{of_type($doc, 'software_Snippet')};
  is_deeply [sort { $a <=> $b } map { $_->{beginIntegerRange} } @ranges], [5, 7, 19, 21],
    'the Apache header matches keep the lines the indexer found them on';

  # And those lines really are the license text in the file the report names
  my $original = $cavil_test->checkout_dir->child(
    'perl-Mojolicious', 'c7cfdab0e71b0bebfdf8b2dc3badfecd',
    '.unpacked',        'Mojolicious-7.25/lib/Mojolicious/resources/public/mojo/prettify/run_prettify.js'
  );
  my @lines = split /\n/, $original->slurp;
  like $lines[4],  qr/Licensed under the Apache License/,       'line 5 in the original';
  like $lines[6],  qr/You may obtain a copy of the License at/, 'line 7 in the original';
  like $lines[18], qr/Licensed under the Apache License/,       'line 19 in the original';
  like $lines[20], qr/You may obtain a copy of the License at/, 'line 21 in the original';
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
  is $dby_id{$dci->{createdBy}[0]}{name}, 'legaldb.suse.de',
    'an unconfigured creator falls back to the deployment, not to the tool';
  is $dby_id{$dci->{createdUsing}[0]}{name}, 'Cavil', 'defaults to Cavil as the tool';

  $t->app->config->{spdx} = $spdx_config;
};

subtest 'Every rebuild is a new iteration of the same SBOM' => sub {

  # Reindexing, a reclassified snippet or an edited pattern all change what the report says without
  # changing the URI it is published under, so the iteration number has to move on its own
  my $version = sub ($sbom_doc) {
    my $sbom = of_type($sbom_doc, 'software_Sbom')->[0];
    my ($id) = grep { ($_->{comment} // '') eq 'SBOM version' } @{$sbom->{externalIdentifier}};
    return $id->{identifier};
  };

  my ($first, $second) = map { $version->(gen_doc()) } 1, 2;
  my ($a, $b) = map { (split /\./)[1] } $first, $second;
  is $b, $a + 1, "consecutive reports for the same package are different iterations ($first, $second)";
  like $first, qr/^1\./, 'the major version is the minimum-elements revision the document follows';
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
  is_deeply $primary->{originatedBy}, ['https://spdx.org/rdf/3.0.1/terms/Core/NoAssertionElement'],
    'an unknown producer is stated rather than omitted';
  is $primary->{software_packageVersion}, '7.25', 'version is still present';
  schema_ok($upload_doc, 'upload-style document still validates');

  $db->query('UPDATE bot_sources SET api_url = ?, project = ? WHERE id = ?',
    $original->{api_url}, $original->{project}, $source_id);
};

subtest 'Component version falls back to the source-control timestamp (BSI 5.2.2)' => sub {

  # Package 2 has no creator-assigned version (remove it from the spec before unpacking, so the unpacked
  # copy and the cached report both reflect a version-less package): BSI TR-03183-2 section 5.2.2 then
  # mandates the source modification date-time (RFC 3339), which Cavil takes from the package creation time
  # (copied from the source-control side by the bot API).
  my $spec = $t->app->packages->pkg_checkout_dir(2)->child('perl-Mojolicious.spec');
  $spec->spew($spec->slurp =~ s/^Version:.*\n//mr);

  $t->app->minion->enqueue(unpack => [2]);
  $t->app->minion->perform_jobs;
  is $t->app->minion->jobs({states => ['failed']})->total, 0, 'no failed jobs';

  my $nover_doc = gen_doc(2);
  my ($primary) = grep { $_->{name} eq 'perl-Mojolicious' } @{of_type($nover_doc, 'software_Package')};

  my $epoch = $t->app->pg->db->query('SELECT EXTRACT(EPOCH FROM created)::bigint AS e FROM bot_packages WHERE id = 2')
    ->hash->{e};
  is $primary->{software_packageVersion}, Mojo::Date->new($epoch)->to_datetime,
    'version falls back to the source-control timestamp';
  like $primary->{software_packageVersion}, qr/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$/,
    'fallback version is an RFC 3339 date-time';
  is_deeply $primary->{externalIdentifier},
    [
    {
      type                   => 'ExternalIdentifier',
      externalIdentifierType => 'packageUrl',
      identifier             => 'pkg:generic/perl-Mojolicious'
    }
    ],
    'the package URL is versionless rather than absent, and does not carry the timestamp';
  schema_ok($nover_doc, 'version-fallback document still validates');
};

subtest 'Source code URI for git sources (BSI 5.2.4)' => sub {

  # Repoint package 2 (already unpacked above) at a git source: BSI's utilised-source URI is then the
  # distribution repository pinned to the commit, expressed as a git VCS locator.
  my $source_id = $t->app->pg->db->query('SELECT source FROM bot_packages WHERE id = ?', 2)->hash->{source};
  $t->app->pg->db->query(
    'UPDATE bot_sources SET type = ?, api_url = ?, project = ?, srcmd5 = ? WHERE id = ?',
    'git', 'https://src.example.com/pool/perl-Mojolicious',
    '',    'a1b2c3d4e5f60718293a4b5c6d7e8f9012345678', $source_id
  );

  my $git_doc = gen_doc(2);
  my ($primary) = grep { $_->{name} eq 'perl-Mojolicious' } @{of_type($git_doc, 'software_Package')};

  is_deeply $primary->{externalRef},
    [
    {
      type            => 'ExternalRef',
      externalRefType => 'vcs',
      locator         => ['git+https://src.example.com/pool/perl-Mojolicious@a1b2c3d4e5f60718293a4b5c6d7e8f9012345678']
    }
    ],
    'source code URI is the git repository pinned to the commit';
  schema_ok($git_doc, 'git-source document still validates');
};

# The case the translation exists for: both files are shifted by post-processing, so the numbers
# the indexer stored point at the wrong lines of the files the report names
# The line-shift checkout has no spec file, which later subtests reuse as a package that declares nothing
my $shift_id;

subtest 'Line ranges are translated back out of the post-processed copy' => sub {
  my $id = $shift_id = $cavil_test->spdx_line_shift_fixtures($t->app);
  $t->app->minion->enqueue(unpack => [$id]);
  $t->app->minion->perform_jobs;
  is $t->app->minion->jobs({states => ['failed']})->total, 0, 'no failed jobs';

  my $shift_doc = gen_doc($id);
  my %files     = map { $_->{name} => $_ } @{of_type($shift_doc, 'software_File')};
  ok $files{'./bundle.js'},                 'the wrapped file is reported under its original name';
  ok $files{'./page.html'},                 'the stripped file is reported under its original name';
  ok !(grep {/\.processed\./} keys %files), 'no scanned copy leaks into the report';

  my %ranges;
  for my $snippet (@{of_type($shift_doc, 'software_Snippet')}) {
    my $file = $files{'./bundle.js'}{spdxId} eq $snippet->{software_snippetFromFile} ? 'bundle.js' : 'page.html';
    push @{$ranges{$file}}, $snippet->{software_lineRange};
  }

  # The declaration is on line 4 of bundle.js, but line 5 of bundle.processed.js (line 3 wrapped)
  is_deeply $ranges{'bundle.js'}, [{type => 'PositiveIntegerRange', beginIntegerRange => 4, endIntegerRange => 4}],
    'the line-wrapped file reports the declaration on line 4';

  # And on line 6 of page.html, but line 2 of page.processed.html (everything else was markup)
  is_deeply $ranges{'page.html'}, [{type => 'PositiveIntegerRange', beginIntegerRange => 6, endIntegerRange => 6}],
    'the markup-stripped file reports the declaration on line 6';

  my ($sid)
    = grep { $_->{software_snippetFromFile} eq $files{'./page.html'}{spdxId} }
    @{of_type($shift_doc, 'software_Snippet')};
  is $sid->{name}, './page.html#L6-L6', 'the snippet name uses the translated range too';

  # The lines the report points at are the ones holding the license, in the files it names
  my $dir = $cavil_test->checkout_dir->child('line-shift', 'f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0', '.unpacked');
  like +(split /\n/, $dir->child('bundle.js')->slurp)[3], qr/Cavil Fixture License/, 'bundle.js line 4';
  like +(split /\n/, $dir->child('page.html')->slurp)[5], qr/Cavil Fixture License/, 'page.html line 6';

  schema_ok($shift_doc, 'translated document validates');
};

# A consumer has to be able to tell "we do not know" from "we did not look". Vendored code is where that
# distinction bites: its embedded metadata names the component but almost never says who published it.
# The go-vendor checkout is the counterpart to the line-shift one below: a package that does ship vendored code
my $vendor_id;

subtest 'Vendored subcomponents say what is unknown about them' => sub {
  my $id = $vendor_id = $cavil_test->go_vendor_fixtures($t->app);
  $t->app->minion->enqueue(unpack => [$id]);
  $t->app->minion->perform_jobs;
  is $t->app->minion->jobs({states => ['failed']})->total, 0, 'no failed jobs';

  my $vendor_doc = gen_doc($id);
  my ($mux) = grep { $_->{name} eq 'github.com/gorilla/mux' } @{of_type($vendor_doc, 'software_Package')};
  ok $mux, 'the vendored module is in the report';
  is_deeply $mux->{originatedBy}, ['https://spdx.org/rdf/3.0.1/terms/Core/NoAssertionElement'],
    'a vendored module with no identifiable producer says so';

  # A Go vendor listing carries no licenses at all, so this component has none to state either
  my ($concluded) = @{rels($vendor_doc, 'hasConcludedLicense', $mux->{spdxId})};
  ok $concluded, 'it still has a concluded license relationship';
  is $concluded->{to}[0], 'expandedlicensing_NoAssertionLicense', 'which states that the license is unknown';
  ok !exists $concluded->{completeness}, 'an unknown license is not claimed to be a complete answer';

  schema_ok($vendor_doc, 'a document full of NoAssertions still validates');

  # A primary component nothing declares a license for is treated the same way (the line-shift checkout
  # ships no spec file at all)
  my $shift_doc           = gen_doc($shift_id);
  my ($primary)           = grep { $_->{name} eq 'line-shift' } @{of_type($shift_doc, 'software_Package')};
  my ($primary_concluded) = @{rels($shift_doc, 'hasConcludedLicense', $primary->{spdxId})};
  is $primary_concluded->{to}[0], 'expandedlicensing_NoAssertionLicense',
    'a package with no declared license says the license is unknown';
};

# Both standards want the dependency list to say whether it is the whole list. A package with vendored code
# says so on every dependency edge; one without has no edge to say it on, so the empty list is stated as such
subtest 'The dependency list says whether it is complete' => sub {
  my $vendor_deps = rels(gen_doc($vendor_id), 'dependsOn');
  ok @$vendor_deps > 1, 'the vendored package depends on its subcomponents';
  is_deeply [map { $_->{completeness} } @$vendor_deps], [('complete') x @$vendor_deps],
    'and each of those dependencies is a complete answer';
  ok !grep({ grep {/NoneElement/} @{$_->{to}} } @$vendor_deps), 'none of them claims there are no dependencies';

  my $shift_doc  = gen_doc($shift_id);
  my $shift_deps = rels($shift_doc, 'dependsOn');
  is scalar @$shift_deps, 1, 'a package with no vendored code still says something about its dependencies';
  is_deeply $shift_deps->[0]{to}, ['https://spdx.org/rdf/3.0.1/terms/Core/NoneElement'], 'namely that there are none';
  is $shift_deps->[0]{completeness}, 'complete', 'and that this is the whole list, not a partial scan';

  schema_ok($shift_doc, 'an empty dependency list validates');
};

# What the download button on the report page sees. It renders from the state the report metadata carries
# and, once a report is on its way, from the same cheap poll the rebuild progress bar uses.
subtest 'SPDX state drives the report page download button' => sub {
  my $pkgs   = $t->app->packages;
  my $minion = $t->app->minion;
  $pkgs->remove_spdx_report(1);
  $t->get_ok('/login')->status_is(302)->header_is(Location => '/');

  # Earlier subtests left finished report jobs behind; a job that is done is not a job in flight
  $t->get_ok('/reviews/report_state/1')->status_is(200)->json_is('/spdx/state', 'none');
  $t->get_ok('/reviews/meta/1')->status_is(200)->json_is('/spdx/state', 'none');

  $t->post_ok('/spdx/1')->status_is(200)->json_is('/state', 'building');
  $t->get_ok('/reviews/report_state/1')->status_is(200)->json_is('/spdx/state', 'building');

  # Clicking twice (or two reviewers on the same report) costs one job between them
  $t->post_ok('/spdx/1')->status_is(200)->json_is('/state', 'building');
  is $minion->jobs({tasks => ['spdx_report'], states => ['inactive', 'active'], notes => ['pkg_1']})->total, 1,
    'exactly one report job is queued';

  $minion->perform_jobs;
  is $minion->jobs({states => ['failed']})->total, 0, 'no failed jobs';
  ok $pkgs->has_spdx_report(1), 'package has SPDX report';

  $t->get_ok('/reviews/report_state/1')->status_is(200)->json_is('/spdx/state', 'ready');
  $t->get_ok('/reviews/meta/1')->status_is(200)->json_is('/spdx/state', 'ready');

  # The size is the one the download produces, which is the uncompressed report, not the file on disk
  my $state = $t->tx->res->json('/spdx');
  my $path  = $pkgs->spdx_report_path(1);
  gunzip("$path" => \my $buffer) or die "gunzip failed: $GunzipError";
  is $pkgs->spdx_report_size(1), length($buffer), 'the reported size is the uncompressed one';
  ok length($buffer) > -s $path, 'and it is bigger than the file on disk';
  like $state->{size}, qr/^[\d.]+\s?\w+$/, 'the button gets a human readable size';

  $t->get_ok('/logout')->status_is(302)->header_is(Location => '/');
};

# A report asked for while the package is busy has to wait for it rather than quietly produce nothing: the
# reviewer who clicked is watching an animation that would otherwise never resolve.
subtest 'A report job waits for whoever is holding the package' => sub {
  my $pkgs   = $t->app->packages;
  my $minion = $t->app->minion;
  $pkgs->remove_spdx_report(1);

  my $guard = $pkgs->claim_guard(1, 99999);
  ok $guard, 'package claimed by somebody else';

  my $id = $minion->enqueue('spdx_report' => [1] => {notes => {pkg_1 => 1}});

  # Perform exactly one attempt: perform_jobs would drain the queue, and on a slow runner a single loop
  # iteration outlasts the few-second first-retry delay, so the freshly delayed job becomes ready again
  # and spins the retry count up until the delay settles to a minute.
  my $worker = $minion->worker->register;
  $worker->dequeue(0, {id => $id})->perform;
  $worker->unregister;
  ok !$pkgs->has_spdx_report(1), 'no report was written';

  my $info = $minion->job($id)->info;
  is $info->{state},                               'inactive', 'the job went back into the queue instead of finishing';
  is $info->{retries},                             1,          'and counts its attempt';
  is $minion->jobs({states => ['failed']})->total, 0,          'no failed jobs';

  # Somebody is watching the button, so the first attempts come back in seconds rather than minutes
  my $waited = $info->{delayed} - $info->{retried};
  ok $waited <= 5, "the first retry waits seconds, not minutes ($waited)";

  # Which is what keeps the button spinning while the wait lasts
  $t->get_ok('/login')->status_is(302)->header_is(Location => '/');
  $t->get_ok('/reviews/report_state/1')->status_is(200)->json_is('/spdx/state', 'building');
  $t->get_ok('/logout')->status_is(302)->header_is(Location => '/');

  # Once the holder lets go, the retry finds the package free and writes the report
  undef $guard;
  $minion->job($id)->retry;
  $minion->perform_jobs;
  is $minion->jobs({states => ['failed']})->total, 0, 'no failed jobs';
  ok $pkgs->has_spdx_report(1), 'package has SPDX report';
};

subtest 'SPDX report is obsolete' => sub {
  $t->get_ok('/login')->status_is(302)->header_is(Location => '/');

  is $t->app->pg->db->query('UPDATE bot_packages SET obsolete = true WHERE id = any(?)', [1])->rows, 1,
    'one package obsoleted';
  $t->get_ok('/spdx/1')->status_is(410)->content_like(qr/package is obsolete/);

  # And the button says so rather than offering a report that can never be built
  $t->post_ok('/spdx/1')->status_is(410)->json_is('/state', 'unavailable');
  $t->get_ok('/reviews/report_state/1')->status_is(200)->json_is('/spdx/state', 'unavailable');

  $t->get_ok('/logout')->status_is(302)->header_is(Location => '/');
};

done_testing;
