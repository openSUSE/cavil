# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package Cavil::SPDX;
use Mojo::Base -base, -signatures;

use Cavil::Checkout;
use Cavil::Licenses qw(lic scancode_suggestion);
use Cavil::Util     qw(read_lines);
use Digest::SHA;
use Mojo::File qw(path);
use Mojo::JSON qw(encode_json);
use Mojo::Date;
use Mojo::Util qw(decode scope_guard);

# BSI TR-03183-2 requires SPDX 3.0.1 (or higher) in JSON format (see section 4)
use constant SPEC_VERSION => '3.0.1';
use constant CONTEXT      => 'https://spdx.org/rdf/3.0.1/spdx-context.jsonld';
use constant HASH_ALGO    => 'sha512';

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
  my $handle   = path($tmp_file)->open('>');
  my $cleanup  = scope_guard sub { -e $tmp_file && path($tmp_file)->remove };

  $handle->syswrite('{"@context":"' . CONTEXT . '","@graph":[');
  my $graph = _Graph->new(handle => $handle, first => 1);

  # Scan all unpacked files first (needed for the package verification hash and to group subcomponents)
  my (%info, %paths, %original_files, @checksums);
  for my $unpacked (@{$checkout->unpacked_files}) {
    my ($ufile, $mime) = @$unpacked;
    $ufile = decode('UTF-8', $ufile) // $ufile;

    # The indexer pre-processes certain files to allow for them to be scanned (we want the original checksum)
    my $checksum_path = $dir->child('.unpacked', $ufile)->to_string;
    if ($ufile =~ /^(.+)\.processed(?:\.(\w+)|$)/) {
      my $original      = defined $2 ? "$1.$2" : $1;
      my $original_path = $dir->child('.unpacked', $original)->to_string;
      if (-e $original_path) {
        $paths{$ufile}          = $checksum_path;
        $checksum_path          = $original_path;
        $original_files{$ufile} = $original;
      }
    }
    $paths{$ufile} //= $checksum_path;

    if (-e $checksum_path) {
      my $sha = Digest::SHA->new('512')->addfile($checksum_path)->hexdigest;
      push @checksums, $sha;
      $info{$ufile} = {sha => $sha, mime => $mime};
    }
    else {
      $log->error("Non-existing path in SPDX report $id: $checksum_path");
    }
  }
  my $verification = Digest::SHA->new('512')->add(join('', sort @checksums))->hexdigest;

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

  # Document and SBOM (the SBOM spdxId doubles as the SBOM-URI)
  $graph->add(
    {
      type               => 'SpdxDocument',
      spdxId             => $iri->('document'),
      creationInfo       => $creation,
      name               => $pkg->{name},
      profileConformance => ['core', 'software', 'simpleLicensing'],
      dataLicense        => 'https://spdx.org/licenses/CC0-1.0',
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

  # Shared helpers for licenses and relationships
  my (%license_pool, $license_num, $rel_num);
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
    software_additionalPurpose => ['archive'],
    verifiedUsing              => [{type => 'Hash', algorithm => HASH_ALGO, hashValue => $verification}]
  };
  $package->{software_packageVersion} = $version       if defined $version && length $version;
  $package->{software_homePage}       = $main->{url}   if $main->{url};
  $package->{originatedBy}            = $originated_by if $originated_by;

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
  }

  # Files (and subcomponents derived from the top-level directories of unpacked archives). This is
  # the single seam where a future OBS-provided subcomponent list would plug in.
  my $matched_files = {};
  for my $matched ($db->query('SELECT id, filename FROM matched_files WHERE package = ?', $id)->hashes->each) {
    $matched_files->{$matched->{filename}} = $matched->{id};
  }

  my (%subcomponents, $file_num);
  for my $ufile (sort keys %info) {
    $file_num++;
    my $real_name = $original_files{$ufile} // $ufile;
    my $fid       = $iri->("file-$file_num");

    # A file inside a top-level directory belongs to that directory's (unpacked archive) subcomponent,
    # a file at the root belongs directly to the primary component.
    my $parent = $pkgid;
    if (my ($top) = $real_name =~ m{^([^/]+)/}) {
      $parent = $subcomponents{$top} //= $iri->('component-' . (keys(%subcomponents) + 1));
    }

    my ($licenses, $copyright) = _file_licenses($db, $matched_files->{$ufile}, $paths{$ufile}, $resolve_license);

    my $node = {
      type                    => 'software_File',
      spdxId                  => $fid,
      creationInfo            => $creation,
      name                    => "./$real_name",
      software_primaryPurpose => _file_purpose($info{$ufile}{mime}),
      verifiedUsing           => [{type => 'Hash', algorithm => HASH_ALGO, hashValue => $info{$ufile}{sha}}]
    };
    $node->{software_copyrightText} = join "\n", @$copyright if @$copyright;
    $graph->add($node);

    $relationship->($parent, 'contains', [$fid], 'complete');
    if (@$licenses) {
      my %seen;
      my $expr = join ' AND ', grep { !$seen{$_}++ } @$licenses;
      $relationship->($fid, 'hasConcludedLicense', [$license_ref->($expr)]);
    }
  }

  # Emit the subcomponents and relate them to the primary component
  for my $top (sort keys %subcomponents) {
    my ($name, $sub_version) = $top =~ /^(.*?)-(v?[0-9][0-9A-Za-z.+~]*)$/ ? ($1, $2) : ($top, undef);
    my $component = {
      type                       => 'software_Package',
      spdxId                     => $subcomponents{$top},
      creationInfo               => $creation,
      name                       => $name,
      software_primaryPurpose    => 'source',
      software_additionalPurpose => ['archive']
    };
    $component->{software_packageVersion} = "$sub_version" if defined $sub_version;
    $graph->add($component);
    $relationship->($pkgid, 'contains', [$subcomponents{$top}], 'complete');
  }

  $handle->syswrite(']}');
  undef $handle;
  path($tmp_file)->move_to($file);
}

# Collect resolved license identifiers and copyright lines for a single file, reusing the same
# snippet/keyword resolution the report uses.
sub _file_licenses ($db, $file_id, $path, $resolve_license) {
  return ([], []) unless $file_id;

  my (@licenses, @copyright, @folded, %duplicates, %matched_lines, %ignored_lines, %similarity);

  my $snippet_sql = qq{
    SELECT f.sline, f.eline, f.resolution, s.license, s.like_pattern, s.likelyness,
           p.spdx AS pspdx, p.license AS plicense
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
    SELECT m.*, p.spdx, p.license
    FROM pattern_matches m LEFT JOIN license_patterns p ON m.pattern = p.id
    WHERE file = ? AND ignored = false ORDER BY p.license, p.id DESC
  };
  for my $match ($db->query($match_sql, $file_id)->hashes->each) {
    if ($match->{license} eq '') {
      next if $ignored_lines{$match->{sline}} && $ignored_lines{$match->{eline}};
      next if $matched_lines{$match->{sline}};
    }
    _matched_lines(\%matched_lines, $match->{sline}, $match->{eline}, 1);

    my $snippet = read_lines($path, $match->{sline}, $match->{eline});
    push @copyright, grep { /copyright.*\d+/i && !$duplicates{$_}++ } split "\n", $snippet;

    if (my $license = $resolve_license->($match->{spdx}, $match->{license})) { push @licenses, $license }
  }

  # Folded snippets contribute their inferred license, just like a real match would
  for my $snippet (@folded) {
    if (my $license = $resolve_license->($snippet->{pspdx}, $snippet->{plicense})) { push @licenses, $license }
  }

  return (\@licenses, \@copyright);
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
  $self->{handle}->syswrite($self->{first} ? '' : ',');
  $self->{first} = 0;
  $self->{handle}->syswrite(encode_json($node));
}

1;
