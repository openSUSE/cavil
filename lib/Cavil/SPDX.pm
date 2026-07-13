# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package Cavil::SPDX;
use Mojo::Base -base, -signatures;

use Cavil::Checkout;
use Cavil::Licenses qw(lic scancode_suggestion);
use Cavil::Util     qw(slurp_and_decode);
use Digest::SHA;
use IO::Compress::Gzip qw($GzipError);
use Mojo::File         qw(path);
use Mojo::JSON         qw(encode_json);
use Mojo::Date;
use Mojo::Util qw(decode scope_guard);

# BSI TR-03183-2 requires SPDX 3.0.1 (or higher) in JSON format (see section 4)
use constant SPEC_VERSION => '3.0.1';
use constant CONTEXT      => 'https://spdx.org/rdf/3.0.1/spdx-context.jsonld';
use constant HASH_ALGO    => 'sha512';

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

  my $pkg = $db->query('SELECT * FROM bot_packages WHERE id = ?', $id)->hash;
  my $src = $db->query(
    'SELECT api_url, project, package, srcmd5 FROM bot_packages bp JOIN bot_sources bs ON bp.source = bs.id
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

  # Enumerate the unpacked files (for the file components, copyright/license scanning and subcomponent
  # grouping). Individual files are not hashed - only the delivered archive is (see below).
  my (%info, %paths, %original_files);
  for my $unpacked (@{$checkout->unpacked_files}) {
    my ($ufile, $mime) = @$unpacked;
    $ufile = decode('UTF-8', $ufile) // $ufile;

    # The indexer pre-processes certain files so they can be scanned; report the original file name
    my $scan_path = $dir->child('.unpacked', $ufile)->to_string;
    if ($ufile =~ /^(.+)\.processed(?:\.(\w+)|$)/) {
      my $original = defined $2 ? "$1.$2" : $1;
      $original_files{$ufile} = $original if -e $dir->child('.unpacked', $original);
    }

    if (-e $scan_path) {
      $paths{$ufile} = $scan_path;
      $info{$ufile}  = {mime => $mime};
    }
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

  my $creator       = $config->{creator} || {};
  my $creator_name  = $creator->{name}   || 'Cavil';
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
  $graph->add({type => 'Tool', spdxId => $iri->('tool-cavil'), creationInfo => $creation, name => 'Cavil'});

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
      profileConformance => ['core', 'software', 'simpleLicensing'],
      dataLicense        => $license_ref->('CC0-1.0'),
      rootElement        => [$base]
    }
  );
  $graph->add(
    {
      type              => 'software_Sbom',
      spdxId            => $base,
      creationInfo      => $creation,
      rootElement       => [$iri->('package')],
      software_sbomType => ['source']
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

  # Resolve a declared license *expression* (specfile or component metadata): a valid SPDX expression is
  # used as-is, otherwise the section 6.1 ScanCode/LicenseRef fallback applies
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
  my $package = {
    type                       => 'software_Package',
    spdxId                     => $pkgid,
    creationInfo               => $creation,
    name                       => $pkg->{name},
    software_primaryPurpose    => 'source',
    software_additionalPurpose => ['archive']
  };
  $package->{software_packageVersion} = $version       if defined $version && length $version;
  $package->{software_homePage}       = $main->{url}   if $main->{url};
  $package->{originatedBy}            = $originated_by if $originated_by;

  # Content checksum of the delivered artifact(s), so the primary component carries a verifiable digest
  $package->{verifiedUsing} = [map { $_->{hash} } @archives] if @archives;

  if ($src && $src->{api_url} && $src->{project}) {
    $package->{software_downloadLocation}
      = "$src->{api_url}/source/$src->{project}/$src->{package}" . ($src->{srcmd5} ? "?rev=$src->{srcmd5}" : '');
  }
  if (defined $version && length $version) {
    $package->{externalIdentifier} = [
      {
        type                   => 'ExternalIdentifier',
        externalIdentifierType => 'packageUrl',
        identifier             => "pkg:generic/$pkg->{name}\@$version"
      }
    ];
  }
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
  my $matched_files = {};
  for my $matched ($db->query('SELECT id, filename FROM matched_files WHERE package = ?', $id)->hashes->each) {
    $matched_files->{$matched->{filename}} = $matched->{id};
  }

  my $file_num;
  for my $ufile (sort keys %info) {
    $file_num++;
    my $real_name = $original_files{$ufile} // $ufile;
    my $fid       = $iri->("file-$file_num");

    my $findings  = _file_licenses($db, $matched_files->{$ufile}, $resolve_license);
    my $copyright = _copyrights($paths{$ufile});

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

      my $sid = $iri->('snippet-' . ++$snippet_num);
      $graph->add(
        {
          type                     => 'software_Snippet',
          spdxId                   => $sid,
          creationInfo             => $creation,
          software_snippetFromFile => $fid,
          software_lineRange       => {
            type              => 'PositiveIntegerRange',
            beginIntegerRange => $finding->{sline},
            endIntegerRange   => $finding->{eline}
          }
        }
      );
      $relationship->($sid, 'hasConcludedLicense', [$lid]);
    }
  }

  # Vendored subcomponents detected during indexing (name/version/license/purl from their embedded
  # metadata), related to the primary component as dependencies
  for my $c ($db->query('SELECT * FROM package_components WHERE package = ? ORDER BY purl', $id)->hashes->each) {
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
    $graph->add($node);

    # Distribution licence (BSI required, hasConcludedLicense) and original licence (additional,
    # hasDeclaredLicense); for a vendored component both are its own declared license
    if (my $expr = $resolve_expr->($c->{license})) {
      my $lid = $license_ref->($expr);
      $relationship->($cid, 'hasConcludedLicense', [$lid], 'complete');
      $relationship->($cid, 'hasDeclaredLicense',  [$lid], 'complete');
    }
    $relationship->($pkgid, 'dependsOn', [$cid], $c->{complete} ? 'complete' : 'incomplete');
  }

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

# Collect license findings for a single file, reusing the same snippet/keyword resolution the report
# uses. Each finding carries the resolved license identifier, Cavil's risk and legal flags, and the
# line range it was found on (for snippet evidence).
sub _file_licenses ($db, $file_id, $resolve_license) {
  return [] unless $file_id;

  my (@findings, @folded, %matched_lines, %ignored_lines, %similarity);

  my $snippet_sql = qq{
    SELECT f.sline, f.eline, f.resolution, s.license, s.like_pattern, s.likelyness,
           p.spdx AS pspdx, p.license AS plicense, p.risk AS prisk,
           p.trademark AS ptrademark, p.patent AS ppatent, p.export_restricted AS pexport_restricted,
           p.cla AS pcla, p.eula AS peula
    FROM file_snippets f LEFT JOIN snippets s ON f.snippet = s.id LEFT JOIN license_patterns p ON s.like_pattern = p.id
    WHERE file = ? AND classified = true
  };
  for my $snippet ($db->query($snippet_sql, $file_id)->hashes->each) {
    my $resolution = $snippet->{resolution} // '';
    _matched_lines(\%ignored_lines, $snippet->{sline}, $snippet->{eline}, 1) unless $snippet->{license};
    _matched_lines(\%similarity, $snippet->{sline}, $snippet->{eline},
      [$snippet->{like_pattern}, $snippet->{likelyness}])
      if $snippet->{like_pattern};
    if    ($resolution eq 'fold') { push @folded, $snippet }
    elsif ($resolution eq 'clear' || $resolution eq 'overlap') {
      _matched_lines(\%ignored_lines, $snippet->{sline}, $snippet->{eline}, 1);
    }
  }

  my $match_sql = qq{
    SELECT m.*, p.spdx, p.license, p.risk, p.trademark, p.patent, p.export_restricted, p.cla, p.eula
    FROM pattern_matches m LEFT JOIN license_patterns p ON m.pattern = p.id
    WHERE file = ? AND ignored = false ORDER BY p.license, p.id DESC
  };
  for my $match ($db->query($match_sql, $file_id)->hashes->each) {
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

# Extract the set flags from a match/snippet row (the fold path uses "p"-prefixed column aliases)
sub _flags ($row, $prefix) {
  return [grep { $row->{"$prefix$_"} } @FLAGS];
}

# Extract distinct copyright statements from a file. Scans the file header (bounded by slurp_and_decode
# to ~30kB) rather than only license-match regions, so copyright notices in files without a license
# match are still found; copyright notices virtually always live near the top of a file.
sub _copyrights ($path) {
  return [] unless defined $path && -f $path;
  my $text = slurp_and_decode($path) // return [];

  # Fast path: the overwhelming majority of files contain no copyright notice at all, so skip the
  # line-by-line work entirely unless there is something to find
  return [] unless $text =~ /copyright|\x{00a9}/i;

  my (%seen, @copyrights);
  for my $line (split /\n/, $text) {

    # Skip minified/one-line blobs that merely happen to mention "copyright" somewhere
    next if length $line > 300;
    next unless $line =~ /copyright|\x{00a9}/i;

    # Strip comment/markup leaders and collapse whitespace
    $line =~ s/^[\s*#;>|!\/-]+//;
    $line =~ s/\s+/ /g;
    $line =~ s/^\s+|\s+$//g;

    # Require a year or a copyright symbol to keep out unrelated prose and license-template placeholders
    next unless length $line && $line =~ /\d{4}|\x{00a9}/i;
    next if $seen{$line}++;
    push @copyrights, $line;
    last if @copyrights >= 100;
  }

  return \@copyrights;
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

use Mojo::JSON qw(encode_json);

# Stream elements into the "@graph" array one at a time to keep memory bounded for large packages
sub add ($self, $node) {
  $self->{handle}->print(',') unless $self->{first};
  $self->{first} = 0;
  $self->{handle}->print(encode_json($node));
}

1;
