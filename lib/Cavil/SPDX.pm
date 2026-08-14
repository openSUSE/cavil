# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package Cavil::SPDX;
use Mojo::Base -base, -signatures;

use Cavil::Checkout;
use Cavil::Licenses qw(lic scancode_suggestion);
use Cavil::PostProcess;
use Digest::SHA;
use IO::Compress::Gzip qw($GzipError);
use Mojo::File         qw(path);
use Mojo::JSON         qw(encode_json);
use Mojo::Date;
use Mojo::URL;
use Mojo::Util qw(decode scope_guard);

# BSI TR-03183-2 requires SPDX 3.0.1 (or higher) in JSON format (see section 4)
use constant SPEC_VERSION => '3.0.1';
use constant CONTEXT      => 'https://spdx.org/rdf/3.0.1/spdx-context.jsonld';
use constant HASH_ALGO    => 'sha512';

# SPDX 3.0.1 individuals for "the author asserts nothing here". The CISA minimum elements want unavailable
# data stated rather than left out, so a recipient can tell "we do not know" from "we did not look". The
# agent one has to be spelled as a full IRI: the short "NoAssertionElement" token is only accepted where the
# schema lists it literally, and the agent range used for a component producer does not.
use constant NO_ASSERTION_AGENT   => 'https://spdx.org/rdf/3.0.1/terms/Core/NoAssertionElement';
use constant NO_ASSERTION_LICENSE => 'expandedlicensing_NoAssertionLicense';

# "There is nothing here", as opposed to "we did not check". Used to state that a package genuinely ships no
# vendored subcomponents, which is what carries the completeness of the dependency list for such a package.
use constant NONE_ELEMENT => 'https://spdx.org/rdf/3.0.1/terms/Core/NoneElement';

# Stated once on the SBOM rather than repeated on every element it applies to. The elements this covers
# (version, hash) are plain strings and objects in SPDX 3.0.1 with no "unknown" form to put in them, and
# CISA treats identifying unknowns as a practice rather than a data field, so one statement is the right
# shape - a per-component note would repeat itself thousands of times in a heavily vendored package.
use constant UNKNOWNS_STATEMENT => join(' ',
  'Unknown information is stated rather than omitted.',
  'A component with no identifiable producer carries a NoAssertion producer, and a component whose license',
  'could not be determined carries a NoAssertion license.',
  'This is a source SBOM: the cryptographic hashes cover the delivered source archives, while vendored',
  'subcomponents have no archive of their own to hash and so carry none.',
  'A vendored subcomponent whose own metadata states no version is listed without one.',
  'Nothing is withheld from this document.');

# Legal flags Cavil curates per license pattern, surfaced as additive SPDX annotations
my @FLAGS = qw(trademark patent export_restricted cla eula);

# Filename extensions of deployable source archives; their hash is the "deployable component" hash
# BSI requires, and hashing just these is far cheaper than re-reading the whole unpacked tree
my $ARCHIVE_RE = qr/\.(?:
    tar | tgz | tbz | tbz2 | txz | tzst           # tarballs
  | tar\.(?: gz | bz2 | xz | zst | lz | lzma )    # compressed tarballs
  | zip | 7z | rpm | cpio | gem | jar             # other archives
)$/xi;

has 'app';

sub generate_to_file ($self, $id, $file) {
  path($file)->remove if -e $file;

  my $app             = $self->app;
  my $log             = $app->log;
  my $config          = $app->config->{spdx} || {};
  my $namespace       = $config->{namespace} || 'http://legaldb.suse.de/spdx/';
  my $dir             = $app->packages->pkg_checkout_dir($id);
  my $checkout        = Cavil::Checkout->new($dir);
  my $reports         = $app->reports;
  my $specfile_report = $reports->specfile_report($id);
  my $db              = $app->pg->db;

  my $pkg
    = $db->query('SELECT *, EXTRACT(EPOCH FROM created)::bigint AS created_epoch FROM bot_packages WHERE id = ?', $id)
    ->hash;
  my $src = $db->query(
    'SELECT api_url, project, package, srcmd5, type FROM bot_packages bp JOIN bot_sources bs ON bp.source = bs.id
     WHERE bp.id = ?', $id
  )->hash;

  # Every element in the graph shares one CreationInfo. Identifiers are IRIs built from the SBOM URI.
  my $base = "$namespace$id";
  my $iri  = sub ($fragment) {"$base#$fragment"};

  my $tmp_file = "$file.tmp";
  my $cleanup  = scope_guard sub { -e $tmp_file && path($tmp_file)->remove };

  # The report is stored gzip-compressed on disk (it is highly repetitive JSON, so this saves a lot of
  # space); it is served untouched to clients that accept gzip, and decompressed on the fly for the rest
  my $handle = IO::Compress::Gzip->new($tmp_file) or die qq{Can't create SPDX report "$tmp_file": $GzipError};

  $handle->print('{"@context":"' . CONTEXT . '","@graph":[');
  my $graph = _Graph->new(handle => $handle, first => 1);

  # Hash only delivered archives; hashing every unpacked file is prohibitively expensive.
  my (%info, %original_files);
  for my $unpacked (@{$checkout->unpacked_files}) {
    my ($ufile, $mime) = @$unpacked;
    $ufile = decode('UTF-8', $ufile) // $ufile;

    # The indexer pre-processes certain files so they can be scanned; report the original file name
    my $scan_path = $dir->child('.unpacked', $ufile)->to_string;
    if ($ufile =~ /^(.+)\.processed(?:\.(\w+)|$)/) {
      my $original = defined $2 ? "$1.$2" : $1;
      $original_files{$ufile} = $original if -e $dir->child('.unpacked', $original);
    }

    if (-e $scan_path) { $info{$ufile} = {mime => $mime} }
    else {
      $log->error("Non-existing path in SPDX report $id: $scan_path");
    }
  }

  # Creation information (the entity that created the SBOM is a required BSI data field)
  my $creation = '_:creationInfo';
  $graph->add(
    {
      type         => 'CreationInfo',
      '@id'        => $creation,
      specVersion  => SPEC_VERSION,
      created      => Mojo::Date->new->to_datetime,
      createdBy    => [$iri->('creator')],
      createdUsing => [$iri->('tool-cavil')]
    }
  );

  my $creator = $config->{creator} || {};

  # The entity that operates Cavil, which is not Cavil itself - the tool is a separate field further down.
  # An instance that has not been told who runs it is identified by the host it publishes its SBOMs under,
  # which at least names a real party, rather than by the name of the software that wrote the file.
  my $creator_name  = $creator->{name} || Mojo::URL->new($namespace)->host || $namespace;
  my $creator_email = $creator->{email};
  my $creator_url   = $creator->{url} || $namespace;
  my $creator_org
    = {type => 'Organization', spdxId => $iri->('creator'), creationInfo => $creation, name => $creator_name};
  $creator_org->{externalIdentifier}
    = [$creator_email
    ? {type => 'ExternalIdentifier', externalIdentifierType => 'email',     identifier => $creator_email}
    : {type => 'ExternalIdentifier', externalIdentifierType => 'urlScheme', identifier => $creator_url}
    ];
  $graph->add($creator_org);

  # The name of the tool and its version are two separate data fields, and SPDX 3.0.1 gives a Tool no version
  # property of its own, so the version travels as a package URL alongside the plain name
  $graph->add(
    {
      type               => 'Tool',
      spdxId             => $iri->('tool-cavil'),
      creationInfo       => $creation,
      name               => 'Cavil',
      externalIdentifier => [
        {
          type                   => 'ExternalIdentifier',
          externalIdentifierType => 'packageUrl',
          identifier             => 'pkg:generic/cavil@' . Cavil->VERSION
        }
      ]
    }
  );

  # Shared helpers for licenses and relationships
  my (%license_pool, %license_meta, $license_num, $rel_num, $snippet_num, $annotation_num);
  my $license_ref = sub ($expr) {
    return $license_pool{$expr} if $license_pool{$expr};
    my $lid = $iri->('license-' . ++$license_num);
    $license_pool{$expr} = $lid;
    $graph->add(
      {
        type                              => 'simplelicensing_LicenseExpression',
        spdxId                            => $lid,
        creationInfo                      => $creation,
        simplelicensing_licenseExpression => $expr
      }
    );
    return $lid;
  };
  my $relationship = sub ($from, $type, $to, $completeness = undef) {
    my $rel = {
      type             => 'Relationship',
      spdxId           => $iri->('rel-' . ++$rel_num),
      creationInfo     => $creation,
      from             => $from,
      relationshipType => $type,
      to               => $to
    };
    $rel->{completeness} = $completeness if $completeness;
    $graph->add($rel);
  };

  # Accumulate Cavil's risk level and legal flags per license (aggregated, emitted as annotations later)
  my $note_license = sub ($lid, $risk, $flags) {
    return unless defined $risk || @$flags;
    my $meta = $license_meta{$lid} //= {flags => {}};
    $meta->{risk} = $risk if defined $risk && (!defined $meta->{risk} || $risk > $meta->{risk});
    $meta->{flags}{$_} = 1 for @$flags;
  };

  # Document and SBOM (the SBOM spdxId doubles as the SBOM-URI). The data license is CC0-1.0, referenced
  # as an in-graph license element (not a bare URL): SPDX 3.0 types dataLicense as an AnyLicenseInfo
  # object reference, so a raw listed-license URL fails validation.
  $graph->add(
    {
      type               => 'SpdxDocument',
      spdxId             => $iri->('document'),
      creationInfo       => $creation,
      name               => $pkg->{name},
      profileConformance => ['core', 'software', 'simpleLicensing', 'expandedLicensing'],
      dataLicense        => $license_ref->('CC0-1.0'),
      rootElement        => [$base]
    }
  );

  # The SBOM URI is derived from the package id and so is the same for every rebuild of this package. The
  # iteration number is what distinguishes one rebuild from the next; the major version is 1 because this
  # document follows the published minimum elements.
  my $sbom_version = $app->packages->next_sbom_version($id);
  $graph->add(
    {
      type               => 'software_Sbom',
      spdxId             => $base,
      creationInfo       => $creation,
      rootElement        => [$iri->('package')],
      software_sbomType  => ['source'],
      comment            => UNKNOWNS_STATEMENT,
      externalIdentifier => [
        {
          type                   => 'ExternalIdentifier',
          externalIdentifierType => 'other',
          identifier             => "1.$sbom_version",
          comment                => 'SBOM version'
        }
      ]
    }
  );

  # BSI section 6.1: refer to licenses by SPDX identifier, else ScanCode ("LicenseRef-scancode-*"),
  # else a "LicenseRef-<inventorising-entity>-*" identifier. License text is never a substitute.
  my $ref_entity      = $config->{license_ref_namespace} || 'cavil';
  my $resolve_license = sub ($spdx, $name) {
    return $spdx if defined $spdx && length $spdx;
    if (defined $name && length $name) {
      if (my $scancode = scancode_suggestion($name)) { return $scancode }
      my $ref = "LicenseRef-$ref_entity-$name";
      $ref =~ s/[^A-Za-z0-9.]+/-/g;
      $ref =~ s/-+$//;
      return $ref;
    }
    return undef;
  };

  my $resolve_expr = sub ($string) {
    return undef unless defined $string && length $string;
    my $license = lic($string);
    return "$license" if !$license->error && length "$license";
    return $resolve_license->(undef, $string);
  };

  # Component origin (supplier) from the Open Build Service coordinates
  my $pkgid = $iri->('package');
  my $originated_by;
  if ($src && ($src->{project} || $src->{api_url})) {
    my $origin_id = $iri->('origin');
    my $origin    = {
      type         => 'Organization',
      spdxId       => $origin_id,
      creationInfo => $creation,
      name         => ($src->{project} || $src->{api_url})
    };
    $origin->{externalIdentifier}
      = [{type => 'ExternalIdentifier', externalIdentifierType => 'urlScheme', identifier => $src->{api_url}}]
      if $src->{api_url};
    $graph->add($origin);
    $originated_by = [$origin_id];
  }

  # Deployable component hashes (BSI required): hash the delivered source archive(s) once - the actual
  # deployable artifact - rather than re-reading every file in the unpacked tree. Packaging metadata
  # (spec files, changelogs) is already represented among the file components, so it is not repeated here.
  # The same digest is reused for the primary component (a real content checksum, importer-agnostic, that
  # SBOM quality scorers reward) and for the archive file elements below (the BSI deployable-component
  # mapping).
  my @archives;
  for my $delivered (sort { $a->basename cmp $b->basename }
    grep { -f $_ && $_->basename =~ $ARCHIVE_RE } $dir->list->each)
  {
    push @archives,
      {
      file => $delivered,
      hash => {
        type      => 'Hash',
        algorithm => HASH_ALGO,
        hashValue => Digest::SHA->new('512')->addfile("$delivered")->hexdigest
      }
      };
  }

  # Primary component (the package itself)
  my $main    = $specfile_report->{main} || {};
  my $version = $main->{version};
  $version = "$version" if defined $version;

  # A timestamp fallback is not a meaningful purl version.
  my $purl_version = (defined $version && length $version) ? $version : undef;

  # BSI TR-03183-2 section 5.2.2 requires a component version; when the creator assigns none, the mandated
  # fallback is the source modification date-time (RFC 3339). bot_packages.created carries the source-control
  # timestamp, so it is the correct value here.
  $version = Mojo::Date->new($pkg->{created_epoch})->to_datetime
    if !defined $purl_version && defined $pkg->{created_epoch};
  my $package = {
    type                       => 'software_Package',
    spdxId                     => $pkgid,
    creationInfo               => $creation,
    name                       => $pkg->{name},
    software_primaryPurpose    => 'source',
    software_additionalPurpose => ['archive']
  };
  $package->{software_packageVersion} = $version     if defined $version && length $version;
  $package->{software_homePage}       = $main->{url} if $main->{url};

  $package->{originatedBy} = $originated_by // [NO_ASSERTION_AGENT];

  # Content checksum of the delivered artifact(s), so the primary component carries a verifiable digest
  $package->{verifiedUsing} = [map { $_->{hash} } @archives] if @archives;

  if ($src && $src->{api_url} && $src->{project}) {
    $package->{software_downloadLocation}
      = "$src->{api_url}/source/$src->{project}/$src->{package}" . ($src->{srcmd5} ? "?rev=$src->{srcmd5}" : '');
  }

  # Timestamp fallbacks use a versionless, still-resolvable purl.
  my $purl = "pkg:generic/$pkg->{name}";
  $purl .= "\@$purl_version" if defined $purl_version;
  $package->{externalIdentifier}
    = [{type => 'ExternalIdentifier', externalIdentifierType => 'packageUrl', identifier => $purl}];

  # BSI TR-03183-2 section 5.2.4 "Source code URI": the *utilised* (distribution) source, version-pinned -
  # for a distribution the source we actually built from, not upstream (section 8.1.8: a maintainer who
  # clones/patches becomes the component creator). Emitted as a VCS external reference; only OBS and git
  # importers carry source coordinates, other sources are left off.
  my $source_uri;
  if ($src && $src->{api_url}) {
    if ($src->{type} eq 'obs' && $src->{project}) {
      $source_uri
        = "$src->{api_url}/source/$src->{project}/$src->{package}" . ($src->{srcmd5} ? "?rev=$src->{srcmd5}" : '');
    }
    elsif ($src->{type} eq 'git') {
      $source_uri = "git+$src->{api_url}" . ($src->{srcmd5} ? "\@$src->{srcmd5}" : '');
    }
  }
  $package->{externalRef} = [{type => 'ExternalRef', externalRefType => 'vcs', locator => [$source_uri]}]
    if $source_uri;

  $graph->add($package);

  # Distribution (concluded) and original (declared) licenses of the primary component
  my $declared = lic($main->{license} // '');
  if (!$declared->error && length "$declared") {
    my $lid = $license_ref->("$declared");
    $relationship->($pkgid, 'hasConcludedLicense', [$lid], 'complete');
    $relationship->($pkgid, 'hasDeclaredLicense',  [$lid], 'complete');

    # Surface Cavil's curated risk/flags for the declared license too (looked up by identifier)
    my $meta = $db->query(
      'SELECT MAX(risk) AS risk, bool_or(patent) AS patent, bool_or(trademark) AS trademark,
              bool_or(export_restricted) AS export_restricted, bool_or(cla) AS cla, bool_or(eula) AS eula
       FROM license_patterns WHERE spdx = ? OR license = ?', "$declared", "$declared"
    )->hash;
    $note_license->($lid, $meta->{risk}, [grep { $meta->{$_} } @FLAGS]) if $meta;
  }

  # Distinguish "nothing found" from an omitted license field.
  else { $relationship->($pkgid, 'hasConcludedLicense', [NO_ASSERTION_LICENSE]) }

  # The delivered source archive(s) as deployable component file elements, reusing the digests computed
  # above (see the @archives comment for why only these files are hashed)
  my $artifact_num = 0;
  for my $archive (@archives) {
    my $delivered = $archive->{file};
    my $aid       = $iri->('artifact-' . ++$artifact_num);
    $graph->add(
      {
        type         => 'software_File',
        spdxId       => $aid,
        creationInfo => $creation,
        name         => './' . $delivered->basename,

        # BSI required properties of the deployable component, per the TR-03183-2 SPDX mapping: it is an
        # "archive", and a "structured" file (a decomposable archive maps to "container"); a source
        # archive is non-executable, so "executable" is deliberately not added
        software_additionalPurpose => ['archive', 'container'],
        comment       => 'software_additionalPurpose field is used to indicate the properties of BSI TR-03183-2',
        verifiedUsing => [$archive->{hash}]
      }
    );
    $relationship->($pkgid, 'hasDistributionArtifact', [$aid], 'complete');
  }

  # Files contained in the primary component
  # The live report only (generation 0): a reindex building alongside it has its own row per filename,
  # and letting both into this filename-keyed map would silently pick one at random per file
  my $matched_files = {};
  for my $matched (
    $db->query('SELECT id, filename FROM matched_files WHERE package = ? AND generation = 0', $id)->hashes->each)
  {
    $matched_files->{$matched->{filename}} = $matched->{id};
  }

  # Stored one row per notice with the files it covers, which is the direction a NOTICE file is built
  # in. SPDX attributes a notice to a file, so the mapping is inverted once here rather than per file.
  my %copyrights_by_file;
  for my $row (@{$reports->copyrights($id)}) {
    push @{$copyrights_by_file{$_}}, $row->{copyright} for @{$row->{files}};
  }

  # Emit the file components in chunks: license findings for a whole chunk are fetched in two batched
  # queries (see _license_rows_by_file) instead of two per file, while the graph is still streamed one
  # element at a time and only one chunk of rows is held in memory
  my $file_num;
  my $postprocess = Cavil::PostProcess->new;
  my @ordered     = sort keys %info;
  while (my @chunk = splice @ordered, 0, 1000) {
    my @file_ids = grep {defined} map { $matched_files->{$_} } @chunk;
    my ($snippets_by_file, $matches_by_file) = _license_rows_by_file($db, \@file_ids);

    for my $ufile (@chunk) {
      $file_num++;
      my $real_name = $original_files{$ufile} // $ufile;
      my $fid       = $iri->("file-$file_num");

      my $mfid = $matched_files->{$ufile};
      my $findings
        = $mfid
        ? _file_licenses($snippets_by_file->{$mfid} // [], $matches_by_file->{$mfid} // [], $resolve_license)
        : [];

      my $copyright = $copyrights_by_file{$real_name} // [];

      # Findings are line numbers in the ".processed" copy the indexer scanned, but the file is
      # reported under its original name, and post-processing shifts lines around (long lines are
      # wrapped, markup is stripped to its text). Translate them back, or the ranges point at
      # whatever happens to sit there in the file the report actually names. Only the lines the
      # findings need are resolved, so a file with no findings costs nothing.
      my $lines;
      if ($original_files{$ufile} && @$findings) {
        my @wanted = map { $_->{sline}, $_->{eline} } grep { $_->{sline} && $_->{eline} } @$findings;
        $lines = $postprocess->original_lines($dir->child('.unpacked', $real_name)->to_string, \@wanted);
      }

      my $node = {
        type                    => 'software_File',
        spdxId                  => $fid,
        creationInfo            => $creation,
        name                    => "./$real_name",
        software_primaryPurpose => _file_purpose($info{$ufile}{mime})
      };
      $node->{software_copyrightText} = join "\n", @$copyright if @$copyright;
      $graph->add($node);
      $relationship->($pkgid, 'contains', [$fid], 'complete');

      # Concluded license for the whole file (all distinct licenses found in it)
      my %seen;
      my @ids = grep { !$seen{$_}++ } map { $_->{license} } @$findings;
      $relationship->($fid, 'hasConcludedLicense', [$license_ref->(join ' AND ', @ids)]) if @ids;

      # Per-match evidence: a snippet element pinpointing the exact lines each license was found on,
      # plus Cavil's risk/flag assessment attached to the license
      for my $finding (@$findings) {
        my $lid = $license_ref->($finding->{license});
        $note_license->($lid, $finding->{risk}, $finding->{flags});
        next unless $finding->{sline} && $finding->{eline};

        # An endpoint that will not translate (the original file changed underneath the report) gets
        # no snippet rather than a range pointing somewhere else; the license itself is still on the
        # file's concluded license above, so nothing is lost from the report but the exact location
        my ($sline, $eline) = ($finding->{sline}, $finding->{eline});
        if ($lines) {
          ($sline, $eline) = ($lines->{$sline}, $lines->{$eline});
          next unless $sline && $eline;
        }

        my $sid = $iri->('snippet-' . ++$snippet_num);
        $graph->add(
          {
            type         => 'software_Snippet',
            spdxId       => $sid,
            creationInfo => $creation,

            # A human-readable location name (file plus line range), so the snippet is a self-describing
            # element rather than an anonymous evidence node
            name                     => "./$real_name#L$sline-L$eline",
            software_snippetFromFile => $fid,
            software_lineRange       =>
              {type => 'PositiveIntegerRange', beginIntegerRange => $sline, endIntegerRange => $eline}
          }
        );
        $relationship->($sid, 'hasConcludedLicense', [$lid]);
      }
    }
  }

  # Vendored subcomponents detected during indexing (name/version/license/purl from their embedded
  # metadata), related to the primary component as dependencies
  my $components
    = $db->query('SELECT * FROM package_components WHERE package = ? AND generation = 0 ORDER BY purl', $id)->hashes;
  for my $c ($components->each) {
    my $cid  = $iri->("component-$c->{id}");
    my $node = {
      type               => 'software_Package',
      spdxId             => $cid,
      creationInfo       => $creation,
      name               => $c->{name},
      externalIdentifier =>
        [{type => 'ExternalIdentifier', externalIdentifierType => 'packageUrl', identifier => $c->{purl}}]
    };
    $node->{software_packageVersion} = $c->{version} if defined $c->{version} && length $c->{version};

    # Vendored code carries no reliable statement of who published it - the embedded metadata names the
    # component, not its producer. That is said out loud, so a reader can tell an unknown producer from a
    # producer nobody bothered to record.
    $node->{originatedBy} = [NO_ASSERTION_AGENT];
    $graph->add($node);

    # Distribution licence (BSI required, hasConcludedLicense) and original licence (additional,
    # hasDeclaredLicense); for a vendored component both are its own declared license
    if (my $expr = $resolve_expr->($c->{license})) {
      my $lid = $license_ref->($expr);
      $relationship->($cid, 'hasConcludedLicense', [$lid], 'complete');
      $relationship->($cid, 'hasDeclaredLicense',  [$lid], 'complete');
    }

    # Neither the component's own metadata nor the file scan produced anything usable
    else { $relationship->($cid, 'hasConcludedLicense', [NO_ASSERTION_LICENSE]) }
    $relationship->($pkgid, 'dependsOn', [$cid], $c->{complete} ? 'complete' : 'incomplete');
  }

  # A package that ships no vendored code would otherwise say nothing at all about its dependencies, which
  # reads the same as never having looked. Both BSI and CISA want the completeness of the dependency list
  # spelled out, so an empty list is stated as an empty list.
  $relationship->($pkgid, 'dependsOn', [NONE_ELEMENT], 'complete') unless $components->size;

  # Cavil's curated legal risk and flags per license, as additive annotations (removable without
  # affecting BSI conformance)
  for my $lid (sort keys %license_meta) {
    my $meta  = $license_meta{$lid};
    my @flags = sort keys %{$meta->{flags}};
    my @parts;
    push @parts, "risk: $meta->{risk}"          if defined $meta->{risk};
    push @parts, 'flags: ' . join(', ', @flags) if @flags;
    next unless @parts;
    $graph->add(
      {
        type           => 'Annotation',
        spdxId         => $iri->('annotation-' . ++$annotation_num),
        creationInfo   => $creation,
        annotationType => 'other',
        subject        => $lid,
        statement      => 'Cavil legal assessment - ' . join('; ', @parts)
      }
    );
  }

  $handle->print(']}');
  $handle->close;
  path($tmp_file)->move_to($file);
}

# Collect license findings for a single file from its pre-fetched snippet and match rows (fetched in
# batches by the caller, see _license_rows_by_file), reusing the same snippet/keyword resolution the
# report uses. Each finding carries the resolved license identifier, Cavil's risk and legal flags, and
# the line range it was found on (for snippet evidence).
sub _file_licenses ($snippet_rows, $match_rows, $resolve_license) {
  my (@findings, @folded, %matched_lines, %ignored_lines, %similarity);

  for my $snippet (@$snippet_rows) {
    my $resolution = $snippet->{resolution} // '';
    _matched_lines(\%ignored_lines, $snippet->{sline}, $snippet->{eline}, 1) unless $snippet->{license};
    _matched_lines(\%similarity, $snippet->{sline}, $snippet->{eline},
      [$snippet->{like_pattern}, $snippet->{likelyness}])
      if $snippet->{like_pattern};
    if    ($resolution eq 'fold') { push @folded, $snippet }
    elsif ($resolution eq 'clear' || $resolution eq 'overlap' || $resolution eq 'covered') {
      _matched_lines(\%ignored_lines, $snippet->{sline}, $snippet->{eline}, 1);
    }
  }

  for my $match (@$match_rows) {
    if ($match->{license} eq '') {
      next if $ignored_lines{$match->{sline}} && $ignored_lines{$match->{eline}};
      next if $matched_lines{$match->{sline}};
    }
    _matched_lines(\%matched_lines, $match->{sline}, $match->{eline}, 1);

    next unless my $license = $resolve_license->($match->{spdx}, $match->{license});
    push @findings,
      {
      license => $license,
      risk    => $match->{risk},
      flags   => _flags($match, ''),
      sline   => $match->{sline},
      eline   => $match->{eline}
      };
  }

  # Folded snippets contribute their inferred license, just like a real match would
  for my $snippet (@folded) {
    next unless my $license = $resolve_license->($snippet->{pspdx}, $snippet->{plicense});
    push @findings,
      {
      license => $license,
      risk    => $snippet->{prisk},
      flags   => _flags($snippet, 'p'),
      sline   => $snippet->{sline},
      eline   => $snippet->{eline}
      };
  }

  return \@findings;
}

# Fetch the classified snippet rows and non-ignored pattern-match rows for a batch of matched_files ids,
# grouped by file id. Batching (WHERE file = ANY) turns the two queries-per-file into two queries per
# chunk, which is the dominant cost of report generation on large packages.
sub _license_rows_by_file ($db, $file_ids) {
  my (%snippets, %matches);
  return (\%snippets, \%matches) unless @$file_ids;

  my $snippet_sql = qq{
    SELECT f.file, f.sline, f.eline, f.resolution, s.license, s.like_pattern, s.likelyness,
           p.spdx AS pspdx, p.license AS plicense, p.risk AS prisk,
           p.trademark AS ptrademark, p.patent AS ppatent, p.export_restricted AS pexport_restricted,
           p.cla AS pcla, p.eula AS peula
    FROM file_snippets f LEFT JOIN snippets s ON f.snippet = s.id LEFT JOIN license_patterns p ON s.like_pattern = p.id
    WHERE f.file = ANY(?) AND classified = true
  };
  push @{$snippets{$_->{file}}}, $_ for $db->query($snippet_sql, $file_ids)->hashes->each;

  my $match_sql = qq{
    SELECT m.*, p.spdx, p.license, p.risk, p.trademark, p.patent, p.export_restricted, p.cla, p.eula
    FROM pattern_matches m LEFT JOIN license_patterns p ON m.pattern = p.id
    WHERE m.file = ANY(?) AND ignored = false ORDER BY p.license, p.id DESC
  };
  push @{$matches{$_->{file}}}, $_ for $db->query($match_sql, $file_ids)->hashes->each;

  return (\%snippets, \%matches);
}

# Extract the set flags from a match/snippet row (the fold path uses "p"-prefixed column aliases)
sub _flags ($row, $prefix) {
  return [grep { $row->{"$prefix$_"} } @FLAGS];
}

# Map a MIME type to an SPDX SoftwarePurpose, approximating the BSI executable/archive/structured
# properties as closely as the available metadata allows.
sub _file_purpose ($mime) {
  $mime //= '';
  return 'archive' if $mime =~ /(?:zip|tar|gzip|compress|x-xz|bzip|7z|x-rpm)/;
  return 'executable'
    if $mime =~ m{^application/x-(?:executable|sharedlib|pie-executable|elf)}
    || $mime =~ m{^(?:text|application)/x-(?:perl|python|shellscript|sh)};
  return 'documentation' if $mime =~ m{^text/html} || $mime =~ /pdf/;
  return 'source'        if $mime =~ m{^text/}     || $mime =~ m{^application/(?:javascript|json|xml)};
  return 'file';
}

sub _matched_lines ($matched_lines, $start, $end, $value) {
  for (my $i = $start; $i <= $end; $i++) {
    $matched_lines->{$i} ||= $value;
  }
}

package _Graph;
use Mojo::Base -base, -signatures;

use Cavil::Util qw(encode_json_fast);

# Stream elements into the "@graph" array one at a time to keep memory bounded for large packages. Each
# element is written in a single print (comma prepended) to halve the writes into the gzip layer.
sub add ($self, $node) {
  my $json = encode_json_fast($node);
  $self->{handle}->print($self->{first} ? $json : ",$json");
  $self->{first} = 0;
}

1;
