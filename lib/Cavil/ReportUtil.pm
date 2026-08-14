# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package Cavil::ReportUtil;
use Mojo::Base -strict, -signatures;

use Exporter 'import';
use List::Util qw(uniq);
use Mojo::File qw(path);
use Mojo::JSON qw(decode_json from_json);
use Mojo::Util;
use Cavil::Licenses 'lic';
use Cavil::Util qw(SNIPPET_SCORE_VERSION extract_spdx_identifiers);

our @EXPORT_OK = (
  qw(estimated_risk hard_incompatibilities incompatibility_location is_license_filename license_classification),
  qw(license_compatibility license_document_candidates license_obligations license_obligation_ids minimal_snippet),
  qw(peripheral_scope),
  qw(new_license_names new_unresolved_files overlapping_licenses ranked_incompatibilities report_checksum report_shortname),
  qw(should_clear_boilerplate should_cover_snippet should_fold_snippet should_overlap_clear smart_edit_snippet),
  qw(spdx_edit_snippet summary_delta summary_delta_score unexplained_lines)
);

use constant PAD_WORDS => 5;

# OSADL's directed compatibility matrix (CC-BY-4.0); missing cells are compatible.
sub _compatibility_matrix () {
  state $matrix = from_json(path(__FILE__)->dirname->child('resources', 'license_compatibility.json')->slurp)->{matrix};
  return $matrix;
}

# decode_json preserves the non-ASCII text in OSADL's CC-BY-4.0 obligation data.
sub _obligations_data () {
  state $data = decode_json(path(__FILE__)->dirname->child('resources', 'license_obligations.json')->slurp);
  return $data;
}

# A missing FSF flag means "no ruling", not "not free".
sub _license_flags_data () {
  state $data = decode_json(path(__FILE__)->dirname->child('resources', 'license_flags.json')->slurp);
  return $data;
}

# The Classpath exception permits otherwise incompatible combinations, so its GPL
# identifier must not create a false compatibility warning.
sub _strip_classpath_exception ($string) {
  $string =~ s/\b(?:A|L)?GPL-[\d.]+(?:-only|-or-later|\+)?\s+WITH\s+Classpath-exception-2\.0\b//gi;
  return $string;
}

# Exceptions relax rather than remove base-license obligations.
sub license_obligation_ids ($name, $data = undef) {
  $data //= _obligations_data();
  return [] unless defined $name;
  my $licenses = $data->{licenses} // {};
  return [uniq grep { $licenses->{$_} } @{extract_spdx_identifiers($name)}];
}

sub license_obligations ($name, $data = undef) {
  $data //= _obligations_data();
  my $licenses = $data->{licenses} // {};
  return [map { {license => $_, %{$licenses->{$_}}} } @{license_obligation_ids($name, $data)}];
}

# Keep SPDX-only entries because SPDX classifies more licenses than OSADL covers.
sub license_classification ($name, $obligations = undef, $flags = undef) {
  $obligations //= _obligations_data()->{licenses}   // {};
  $flags       //= _license_flags_data()->{licenses} // {};

  my @entries;
  for my $id (uniq @{extract_spdx_identifiers($name)}) {
    my $osadl = $obligations->{$id};
    my $spdx  = $flags->{$id};
    next unless $osadl || $spdx;
    push @entries, {license => $id, %{$spdx // {}}, %{$osadl // {}}};
  }

  return \@entries;
}

sub estimated_risk ($risk, $match) {
  my $estimated = int(($risk * $match + 9 * (1 - $match)) + 0.5);
  return $match < 0.9 && $estimated <= 4 ? 5 : $estimated;
}

# Keep folding precision-first because it asserts a specific license.
sub should_fold_snippet ($cfg, $snippet, $pattern) {
  return 0 unless $cfg && $cfg->{enabled};
  return 0 unless $snippet->{license};                                                    # classifier says legal text
  return 0 unless ($snippet->{score_version} // 0) == SNIPPET_SCORE_VERSION;              # scored by current model
  return 0 unless $pattern && defined $pattern->{license} && $pattern->{license} ne '';

  my $match = $snippet->{likelyness} // 0;
  return 0 unless $match >= ($cfg->{threshold} // 1);
  return 0 unless ($match - ($snippet->{second_match} // 0)) >= ($cfg->{min_margin} // 0);
  return 0 if defined $cfg->{max_risk} && $pattern->{risk} > $cfg->{max_risk};

  return 1;
}

# Clearing shared boilerplate asserts no license, so it needs no fold margin or risk gate.
sub should_clear_boilerplate ($cfg, $snippet, $pattern) {
  return 0 unless $cfg && $cfg->{enabled};
  return 0 unless my $threshold = $cfg->{clear_threshold};                                # 0/undef disables clearing
  return 0 unless $snippet->{license};                                                    # classifier says legal text
  return 0 unless ($snippet->{score_version} // 0) == SNIPPET_SCORE_VERSION;              # scored by current model
  return 0 unless $pattern && defined $pattern->{license} && $pattern->{license} ne '';

  return ($snippet->{likelyness} // 0) >= $threshold ? 1 : 0;
}

# FileIndexer expansion can swallow resolved matches into unresolved snippets.
sub overlapping_licenses ($sline, $eline, $spans) {
  my %licenses;
  for my $span (@{$spans || []}) {
    my ($ss, $se, $license) = @$span;
    next unless defined $license && $license ne '';
    next if $se < $sline || $ss > $eline;    # no overlap
    $licenses{$license} = 1;
  }
  return [sort keys %licenses];
}

# A curated overlap is authoritative, but a strong match to another license needs review.
sub should_overlap_clear ($cfg, $snippet, $overlap_licenses) {
  return 0 unless $cfg && $cfg->{enabled} && $cfg->{overlap_clear};
  return 0 unless $snippet->{license};                                # classifier says legal text
  return 0 unless $overlap_licenses && @$overlap_licenses;            # overlaps a licensed match

  my $like = $snippet->{plicense};
  if (defined $like && $like ne '' && ($snippet->{likelyness} // 0) >= ($cfg->{overlap_guard} // 0.9)) {
    my %overlap = map { $_ => 1 } @$overlap_licenses;
    return 0 unless $overlap{$like};    # resembles a *different* license -> keep for review
  }

  return 1;
}

# Coverage may clear only snippets no riskier than a concrete license already in scope.
# Catch-all risk is unreliable, so weak matches in license files remain reviewable.
sub should_cover_snippet ($cfg, $snippet, $cover_risk) {
  return 0 unless $cfg && $cfg->{enabled} && (($cfg->{cover_scope} // 'off') ne 'off');
  return 0 unless $snippet->{license};                                                    # classifier says legal text
  return 0 unless ($snippet->{score_version} // 0) == SNIPPET_SCORE_VERSION;              # trust the risk read
  return 0 unless defined $cover_risk;    # a concrete license covers this scope

  return 0
    if $snippet->{is_license_file}
    && $snippet->{pcatch_all}
    && ($snippet->{likelyness} // 0) < ($cfg->{cover_guard} // 0.9);

  my $snippet_risk = (defined $snippet->{plicense} && $snippet->{plicense} ne '') ? ($snippet->{prisk} // 0) : 0;
  return $snippet_risk <= $cover_risk ? 1 : 0;
}

# A blocklist avoids misclassifying open-ended names such as LICENSE.docs.
# Keep it testable as data rather than embedding it in the regex.
our @SOURCE_EXTENSIONS = qw(
  asm awk bash c cc cjs cpp cs cxx dart el go gradle groovy h hh hpp java jl js jsx kt lua mjs mm
  php pl pm py rb rs scala sh sql swift tcl ts tsx vim
);
my $SOURCE_EXTENSION = do { my $alternation = join '|', @SOURCE_EXTENSIONS; qr/[.](?:$alternation)$/i };

# Match the basename so license-named directories do not classify every child as legal text.
sub is_license_filename ($path) {
  my ($basename) = $path =~ m{([^/]*)$};
  return 0 if $basename =~ $SOURCE_EXTENSION;
  return $basename =~ m{^(?:LICEN[CS]E|COPYING|COPYRIGHT|NOTICE|EULA|LEGAL|UNLICENSE|THIRD[_-]?PARTY)(?:[.\-]|$)}i
    ? 1
    : 0;
}

# Include unresolved guesses so compatibility review errs toward visibility; proximity conveys confidence.
sub _present_licenses ($dig_report) {
  my @spdx;
  push @spdx, map { $_->{spdx} } grep { $_->{spdx} } values %{$dig_report->{licenses}  || {}};
  push @spdx, map { $_->[3] } grep    { $_->[3] } values %{$dig_report->{missed_files} || {}};
  @spdx = map { _strip_classpath_exception($_) } @spdx;

  my %present;
  $present{$_}++ for map { @{extract_spdx_identifiers($_)} } @spdx;
  return \%present;
}

# Preserve OSADL's direction and wording; omit compatible cells and Unknown-only axes.
sub license_compatibility ($dig_report, $matrix = undef) {
  $matrix //= _compatibility_matrix();
  my $present = _present_licenses($dig_report);

  my (%cells, %participates);
  for my $outbound (sort keys %$present) {
    my $row = $matrix->{$outbound} or next;
    for my $inbound (sort keys %$row) {
      next unless $present->{$inbound};
      my $cell = $row->{$inbound};
      $cells{$outbound}{$inbound} = {compatibility => $cell->{compatibility}, explanation => $cell->{explanation}};
      if ($cell->{compatibility} eq 'No' || $cell->{compatibility} eq 'Check dependency') {
        $participates{$outbound}++;
        $participates{$inbound}++;
      }
    }
  }

  my @licenses = sort keys %participates;
  my %keep     = map { $_ => 1 } @licenses;
  my %kept_matrix;
  for my $outbound (@licenses) {
    for my $inbound (sort keys %{$cells{$outbound} || {}}) {
      next unless $keep{$inbound};
      $kept_matrix{$outbound}{$inbound} = $cells{$outbound}{$inbound};
    }
  }

  my $result = {licenses => \@licenses, matrix => \%kept_matrix};

  # Co-location ranks likely combinations without hiding matrix entries.
  $result->{proximity} = _pair_proximity($dig_report, \@licenses, \%kept_matrix);

  return $result;
}

# Confidence ranks real matches (3), folds (2), and unresolved guesses (1).
sub _file_license_ids ($dig_report) {
  my $files = $dig_report->{files}           || {};
  my $lics  = $dig_report->{licenses}        || {};
  my $conf  = $dig_report->{file_confidence} || {};
  my %file_ids;

  my $bump = sub ($path, $ids, $rank) {
    for my $id (@$ids) { $file_ids{$path}{$id} = $rank if $rank > ($file_ids{$path}{$id} // 0) }
  };

  for my $by_name (values %{$dig_report->{risks} || {}}) {
    for my $name (keys %$by_name) {
      my $spdx = $lics->{$name}{spdx};
      next unless defined $spdx && $spdx ne '';
      my $ids = extract_spdx_identifiers(_strip_classpath_exception($spdx));
      next unless @$ids;
      for my $fids (values %{$by_name->{$name}}) {
        for my $fid (@$fids) {
          my $path = $files->{$fid} // next;

          # Synthetic reports predate file_confidence and represent real matches.
          $bump->($path, $ids, $conf->{$fid}{$name} // 3);
        }
      }
    }
  }

  my $missed = $dig_report->{missed_files} || {};
  for my $fid (keys %$missed) {
    my $path = $files->{$fid} // next;
    my $spdx = $missed->{$fid}[3];
    next unless defined $spdx && $spdx ne '';
    $bump->($path, extract_spdx_identifiers(_strip_classpath_exception($spdx)), 1);
  }

  return \%file_ids;
}

sub _ancestor_dirs ($path) {
  my @segs = split m{/}, $path;
  pop @segs;
  my @dirs = ('');
  my $acc  = '';
  for my $seg (@segs) {
    $acc = $acc eq '' ? $seg : "$acc/$seg";
    push @dirs, $acc;
  }
  return @dirs;
}

sub _dir_depth ($dir) { return $dir eq '' ? 0 : (($dir =~ tr{/}{}) + 1) }

# Peripheral co-location is weaker evidence than co-location in shipped source.
my %PERIPHERAL_SEGMENT = (
  (map { $_ => 'documentation' } qw(doc docs documentation)),
  (map { $_ => 'test' } qw(test tests testing testdata test-data test_data __tests__ fixtures)),
  (map { $_ => 'example' } qw(example examples sample samples)),
  (
    map { $_ => 'vendored' }
      qw(vendor vendored _vendor third_party third-party 3rdparty contrib node_modules gomodcache)
  ),
  licenses => 'license catalog'
);

# OBS cpio paths decorate vendored segments, for example vendor.obscpio._.
my $OBS_VENDORED_SEGMENT = qr/(?:^|_)(?:node_modules|vendor|vendored|third_party|3rdparty)\./;

# Basenames do not determine whether code is peripheral. A test, doc or example segment anywhere in the path
# beats a vendored one, because a vendored dependency's own tests are as ignorable as the package's own.
sub _path_peripheral_kind ($path) {
  my @segs = split m{/}, $path;
  pop @segs;
  my $vendored;
  for my $seg (@segs) {
    my $lc   = lc $seg;
    my $kind = $PERIPHERAL_SEGMENT{$lc};
    $kind = 'vendored' if !$kind && index($lc, '.') >= 0 && $lc =~ $OBS_VENDORED_SEGMENT;
    next         unless $kind;
    return $kind unless $kind eq 'vendored';
    $vendored = 1;
  }
  return $vendored ? 'vendored' : undef;
}

sub _path_is_peripheral ($path) { return _path_peripheral_kind($path) ? 1 : 0 }

# 0 shipped source, 1 vendored dependency code, 2 tests/docs/examples/license catalogs. Vendored code sits
# between the two because it can still be linked into the build, so it needs a look; the tier 2 kinds are
# ignorable wherever they sit, including inside a vendored tree.
sub _path_tier ($path) {
  my $kind = _path_peripheral_kind($path) // return 0;
  return $kind eq 'vendored' ? 1 : 2;
}

# Report peripheral location without prescribing action; the classification is heuristic.
sub peripheral_scope ($paths) {
  return undef unless @$paths;

  my %kinds;
  for my $path (@$paths) {
    my $kind = _path_peripheral_kind($path) // return undef;
    $kinds{$kind} = 1;
  }

  return [sort keys %kinds];
}

# Rank by tier (shipped source, then vendored, then tests/docs), then confidence, same-file evidence, depth.
# Unresolved guesses contribute only to same-file evidence to bound tree-walk cost.
sub _pair_proximity ($dig_report, $licenses, $matrix) {
  return {} unless @$licenses;

  my %bit;
  my $i = 0;
  $bit{$_} = $i++ for @$licenses;
  my @flagged_pairs;
  for my $a (@$licenses) {
    for my $b (@$licenses) {
      next if $a ge $b;
      next unless $matrix->{$a}{$b} || $matrix->{$b}{$a};
      push @flagged_pairs, [$a, $b, $bit{$a}, $bit{$b}];
    }
  }
  return {} unless @flagged_pairs;

  my $file_ids = _file_license_ids($dig_report);

  my (@dir_mask, @dir_conf, @dir_rep, @same_file, %lic_rep, %lic_resolved);
  for my $path (keys %$file_ids) {
    my $ids = $file_ids->{$path};
    my %bconf;    # resolved (confidence >= 2) bit => confidence, for the directory machinery
    my $amask = 0;
    for my $id (keys %$ids) {
      next unless exists $bit{$id};
      my $c = $ids->{$id};
      my $b = $bit{$id};
      $amask |= (1 << $b);
      $bconf{$b} = $c if $c >= 2;

      $lic_rep{$b} //= $path;
      $lic_resolved{$b} = 1 if $c >= 2;
    }

    my $tier = _path_tier($path);
    push @same_file, [$path, $amask, ($path =~ tr{/}{}), $tier] if $amask & ($amask - 1);
    next unless %bconf;

    my $rmask = 0;
    $rmask |= (1 << $_) for keys %bconf;
    for my $dir (_ancestor_dirs($path)) {

      # Each tier's masks include everything above it, so tier 1 means "core or vendored code".
      for my $t ($tier .. 2) {
        $dir_mask[$t]{$dir} |= $rmask;
        for my $b (keys %bconf) {
          next unless $bconf{$b} > ($dir_conf[$t]{$dir}{$b} // 0);
          $dir_conf[$t]{$dir}{$b} = $bconf{$b};
          $dir_rep[$t]{$dir}{$b}  = $path;
        }
      }
    }
  }

  # The weights enforce the documented lexicographic ranking.
  my %best;
  my $consider = sub ($la, $lb, $cand) {
    $cand->{_score} = (2 - $cand->{tier}) * 1_000_000;
    $cand->{_score} += $cand->{confidence} * 10_000 + $cand->{same_file} * 100 + $cand->{lca_depth};
    my $cur = $best{$la}{$lb};
    $best{$la}{$lb} = $cand if !$cur || $cand->{_score} > $cur->{_score};
  };

  for my $dir (keys %{$dir_mask[2] // {}}) {
    my $am = $dir_mask[2]{$dir};
    next unless $am & ($am - 1);
    my $depth = _dir_depth($dir);
    for my $fp (@flagged_pairs) {
      my ($la, $lb, $ba, $bb) = @$fp;
      my ($mba, $mbb) = (1 << $ba, 1 << $bb);
      next unless ($am & $mba) && ($am & $mbb);

      # The tier outweighs every other signal, so the lowest one carrying both licenses wins outright.
      for my $t (0 .. 2) {
        my $m = $dir_mask[$t]{$dir} // 0;
        next unless ($m & $mba) && ($m & $mbb);
        my ($ca, $cb) = ($dir_conf[$t]{$dir}{$ba}, $dir_conf[$t]{$dir}{$bb});
        $consider->(
          $la, $lb,
          {
            confidence => ($ca < $cb ? $ca : $cb),
            same_file  => 0,
            lca_depth  => $depth,
            tier       => $t,
            files      => [$dir_rep[$t]{$dir}{$ba}, $dir_rep[$t]{$dir}{$bb}]
          }
        );
        last;
      }
    }
  }

  for my $sf (@same_file) {
    my ($path, $mask, $depth, $tier) = @$sf;
    for my $fp (@flagged_pairs) {
      my ($la, $lb, $ba, $bb) = @$fp;
      next unless ($mask & (1 << $ba)) && ($mask & (1 << $bb));
      my ($ca, $cb) = ($file_ids->{$path}{$la}, $file_ids->{$path}{$lb});
      $consider->(
        $la, $lb,
        {
          confidence => ($ca < $cb ? $ca : $cb),
          same_file  => 1,
          lca_depth  => $depth,
          tier       => $tier,
          files      => [$path, $path]
        }
      );
    }
  }

  # Weak unmatched evidence still needs a reviewable file target.
  for my $fp (@flagged_pairs) {
    my ($la, $lb, $ba, $bb) = @$fp;
    next if $best{$la} && $best{$la}{$lb};    # guarded to avoid autovivifying an empty {la => {}}
    my @weak = grep { !$lic_resolved{$_} && defined $lic_rep{$_} } ($ba, $bb);
    next unless @weak;                        # no file evidence at all - nothing to point at
    $best{$la}{$lb} = {
      no_colocation =>  1,
      confidence    =>  1,
      same_file     =>  0,
      lca_depth     => -1,
      tier          =>  0,
      files         => [map { $lic_rep{$_} } @weak]
    };
  }

  delete $_->{_score} for map { values %$_ } values %best;
  return \%best;
}

# Only mutual "No" pairs are hard incompatibilities.
sub hard_incompatibilities ($compat) {
  my $matrix = $compat->{matrix} // {};
  my %seen;
  my @pairs;
  for my $a (@{$compat->{licenses} // []}) {
    for my $b (@{$compat->{licenses} // []}) {
      next if $a ge $b;
      next unless ($matrix->{$a}{$b} && $matrix->{$a}{$b}{compatibility} eq 'No');
      next unless ($matrix->{$b}{$a} && $matrix->{$b}{$a}{compatibility} eq 'No');
      push @pairs, [$a, $b];
    }
  }
  return \@pairs;
}

# Centralize ordering so web, text, and MCP reports cannot diverge.
sub ranked_incompatibilities ($compat) {
  my $matrix = $compat->{matrix}    // {};
  my $prox   = $compat->{proximity} // {};
  my %hard   = map { ; "$_->[0]\x00$_->[1]" => 1 } @{hard_incompatibilities($compat)};

  my @rows;
  my $licenses = $compat->{licenses} // [];
  for my $a (@$licenses) {
    for my $b (@$licenses) {
      next if $a ge $b;
      next unless $matrix->{$a}{$b} || $matrix->{$b}{$a};
      my $p = $prox->{$a}{$b}
        // {no_colocation => 1, confidence => 0, same_file => 0, lca_depth => -1, tier => 0, files => []};
      push @rows,
        {
        a             => $a,
        b             => $b,
        mutual        => $hard{"$a\x00$b"}   ? 1 : 0,
        no_colocation => $p->{no_colocation} ? 1 : 0,
        confidence    => $p->{confidence} // 0,
        same_file     => $p->{same_file},
        lca_depth     => $p->{lca_depth},
        tier          => $p->{tier},
        files         => $p->{files} // []
        };
    }
  }

  return [
    sort {
      $a->{no_colocation}   <=> $b->{no_colocation}    # co-located pairs first, not-co-located last
        || $a->{tier}       <=> $b->{tier}
        || $b->{confidence} <=> $a->{confidence}
        || $b->{same_file}  <=> $a->{same_file}
        || $b->{lca_depth}  <=> $a->{lca_depth}
        || $b->{mutual}     <=> $a->{mutual}
        || $a->{a}          cmp $b->{a}
        || $a->{b}          cmp $b->{b}
    } @rows
  ];
}

# Describe only same-file or same-directory evidence worth opening.
sub incompatibility_location ($row) {
  my ($fa, $fb) = @{$row->{files} || []};
  return undef unless defined $fa;
  return "same file `$fa`" if $row->{same_file} || (defined $fb && $fa eq $fb);
  return undef unless defined $fb;

  my $da = $fa =~ m{^(.*)/[^/]*$} ? $1 : '';
  my $db = $fb =~ m{^(.*)/[^/]*$} ? $1 : '';
  return "same directory `$da`: `$fa`, `$fb`" if $da ne '' && $da eq $db;
  return undef;
}

# Indexed files are more reliable than package metadata for finding legal documents.
# Exclude peripheral paths so dependency licenses do not bury package-level terms.
sub license_document_candidates ($dig_report, $limit = 25) {
  my $files = $dig_report->{files} || {};

  my @found;
  for my $id (keys %$files) {
    my $path = $files->{$id};
    next unless defined $path && is_license_filename($path) && !_path_is_peripheral($path);
    push @found, {id => $id, path => $path};
  }

  # Prefer package-level documents and keep output deterministic.
  @found = sort { ($a->{path} =~ tr{/}{}) <=> ($b->{path} =~ tr{/}{}) || $a->{path} cmp $b->{path} } @found;

  my $dropped = @found > $limit ? @found - $limit : 0;
  splice @found, $limit if $dropped;
  return {documents => \@found, dropped => $dropped};
}

# Use only real matches; snippet resolution can suppress an unrecognized clause.
sub unexplained_lines ($spans, $lines) {
  return 0 unless $lines && @$lines;

  my %covered;
  for my $span (@{$spans || []}) {
    my ($start, $end) = @$span;
    $start       = 1       if $start < 1;
    $end         = @$lines if $end > @$lines;
    $covered{$_} = 1 for $start .. $end;
  }

  my $unexplained = 0;
  for my $i (0 .. $#$lines) {
    next           if $covered{$i + 1};
    $unexplained++ if $lines->[$i] =~ /\S/;
  }

  return $unexplained;
}

sub minimal_snippet ($snippet) {
  my $start_line = $snippet->{sline}    // 1;
  my $keywords   = $snippet->{keywords} // {};
  my $matches    = $snippet->{matches}  // {};
  return {text => $snippet->{text}, start_line => $start_line} unless keys %$keywords;
  return {text => $snippet->{text}, start_line => $start_line} unless keys %$matches;

  my $lines = [split("\n", $snippet->{text}, -1)];

  my $start = 0;
  for (my $i = 0; $i < @$lines; $i++) {
    last            if $keywords->{$i};
    $start = $i + 1 if $matches->{$i};
  }

  my $end = $#$lines;
  for (my $i = $#$lines; $i >= 0; $i--) {
    last          if $keywords->{$i};
    $end = $i - 1 if $matches->{$i};
  }

  return {text => join("\n", @$lines[$start .. $end]), start_line => $start_line + $start};
}

my $COPYRIGHT_ANCHOR = qr{
  ^
  (                                                       # $1: prefix to preserve
    \s* (?: [\#*/;]+ \s* )?
    (?:
      SPDX-(?:File|Snippet)CopyrightText:
      | Copyright (?: \s* (?: \(c\) | \(C\) | © ) )?
      | (?: \(c\) | \(C\) | © ) (?: \s* Copyright )?
    )
  )
  \s+ \S .* $                                             # at least one word follows
}x;

sub _collapse_copyright_line ($line) {
  return $line unless $line =~ $COPYRIGHT_ANCHOR;
  return "$1 \$SKIP10";
}

# Preserve line count for frontend decorations and use $SKIP10 so edited text
# still matches the original.
sub smart_edit_snippet ($snippet) {
  my $original_text  = $snippet->{text}     // '';
  my $original_sline = $snippet->{sline}    // 1;
  my $keywords       = $snippet->{keywords} // {};

  my $minimal       = minimal_snippet($snippet);
  my $text          = $minimal->{text};
  my $minimal_sline = $minimal->{start_line};

  my $finalize = sub ($result_text, $start_line) {
    my $collapsed = join "\n", map { _collapse_copyright_line($_) } split /\n/, $result_text, -1;
    return {text => $collapsed, start_line => $start_line, changed => $collapsed eq $original_text ? 0 : 1};
  };

  return $finalize->($text, $minimal_sline) unless keys %$keywords;

  my $offset   = $minimal_sline - $original_sline;
  my @kw_lines = sort { $a <=> $b } grep { $_ >= 0 } map { $_ - $offset } keys %$keywords;
  return $finalize->($text, $minimal_sline) unless @kw_lines;

  my @lines    = split /\n/, $text, -1;
  my $first_kw = $kw_lines[0];
  my $last_kw  = $kw_lines[-1];
  return $finalize->($text, $minimal_sline) if $last_kw >= @lines;

  my $span_start = 0;
  $span_start += length($lines[$_]) + 1 for 0 .. $first_kw - 1;
  my $span_end = $span_start;
  $span_end += length($lines[$_]) + 1 for $first_kw .. $last_kw - 1;
  $span_end += length($lines[$last_kw]);

  my $new_start = 0;
  if ($span_start > 0) {
    my $prefix = substr($text, 0, $span_start);
    my @starts;
    while ($prefix =~ /\S+/g) { push @starts, $-[0] }
    if (@starts > PAD_WORDS) { $new_start = $starts[-PAD_WORDS] }
  }

  my $new_end = length($text);
  if ($span_end < $new_end) {
    my $suffix = substr($text, $span_end);
    my @ends;
    while ($suffix =~ /\S+/g) { push @ends, $+[0] }
    if (@ends > PAD_WORDS) { $new_end = $span_end + $ends[PAD_WORDS - 1] }
  }

  my $trimmed = substr($text, $new_start, $new_end - $new_start);

  my $dropped_lines = (substr($text, 0, $new_start) =~ tr/\n//);

  return $finalize->($trimmed, $minimal_sline + $dropped_lines);
}

sub spdx_edit_snippet ($snippet) {
  my $original_text = $snippet->{text} // '';
  my $identifiers   = extract_spdx_identifiers($original_text);
  my $identifier    = $identifiers->[0] // '';
  my $text          = "SPDX-License-Identifier: $identifier";

  return {text => $text, start_line => $snippet->{sline} // 1, changed => $text eq $original_text ? 0 : 1};
}

sub report_checksum ($specfile_report, $dig_report) {

  my $canon_license = lic($specfile_report->{main}{license})->canonicalize->to_string;
  $canon_license ||= "Unknown";
  my $text = "RPM-License $canon_license\n";

  for my $license (sort { $a cmp $b } keys %{$dig_report->{licenses}}) {
    next if $dig_report->{licenses}{$license}{risk} == 0;
    $text .= "LIC:$license";
    for my $flag (@{$dig_report->{licenses}{$license}{flags}}) {
      $text .= ":$flag";
    }
    $text .= "\n";
  }

  # Hash the complete set deterministically; snippets is expansion-truncated.
  if (my $snippets = $dig_report->{missed_snippets}) {
    my @all;
    for my $file (keys %$snippets) {
      push @all, $_->[3] for @{$snippets->{$file}};
    }
    $text .= "SNIPPET:$_\n" for sort +uniq @all;
  }

  # Compatibility is derived context and must not trigger re-review.

  return Mojo::Util::md5_sum $text;
}

sub report_shortname ($chksum, $specfile_report, $dig_report) {
  my $max_risk = 0;
  for my $risk (keys %{$dig_report->{risks}}) {
    $max_risk = $risk if $risk > $max_risk;
  }
  for my $file (keys %{$dig_report->{missed_files}}) {
    my $risk = $dig_report->{missed_files}{$file}[0];
    $max_risk = $risk if $risk > $max_risk;
  }

  # Common vendored incompatibilities must not flood the review queue.

  my $l = lic($specfile_report->{main}{license})->example;
  $l ||= 'Unknown';

  return "$l-$max_risk:$chksum";
}

sub summary_delta ($old, $new) {
  my @blocks;

  if ($new->{specfile} ne $old->{specfile}) {
    push @blocks, "  Spec file license  $old->{specfile} -> $new->{specfile}";
  }

  my $new_snippets = _new_snippets($old, $new);
  if (my $num = uniq values %$new_snippets) {
    push @blocks, $num == 1 ? '  New unresolved matches' : "  New unresolved matches in $num files";
  }

  my $new_licenses = _new_licenses($old, $new);
  if (my @lics = keys %$new_licenses) {
    my @sorted = sort { $new_licenses->{$b} <=> $new_licenses->{$a} || $a cmp $b } @lics;
    my @lines  = ('  New licenses (by risk)');
    push @lines,  map {"    $new_licenses->{$_}  $_"} @sorted;
    push @blocks, join("\n", @lines);
  }

  # Derived compatibility context must not affect review priority.

  return '' unless @blocks;
  return "Diff to closest match $old->{id}\n\n" . join("\n\n", @blocks) . "\n";
}

sub summary_delta_score ($old, $new) {
  my $score = 0;

  $score += 1000 if $new->{specfile} ne $old->{specfile};

  my $new_snippets = _new_snippets($old, $new);
  $score += 10 * keys %$new_snippets;

  my $new_licenses = _new_licenses($old, $new);
  $score += 10 * $new_licenses->{$_} for keys %$new_licenses;

  return $score;
}

# Flags label a license row, so novelty is determined by bare name.
sub _new_licenses ($old, $new) {
  my %old_licenses = map { (split /:/, $_)[0] => 1 } keys %{$old->{licenses} || {}};

  my %new_licenses;
  for my $lic (keys %{$new->{licenses}}) {
    my $name = (split /:/, $lic)[0];
    $new_licenses{$name} //= $new->{licenses}{$lic} unless $old_licenses{$name};
  }
  return \%new_licenses;
}

sub new_license_names ($old, $new) {
  return [sort keys %{_new_licenses($old, $new)}];
}

sub _new_snippets ($old, $new) {
  my $new_snippets = $new->{missed_snippets};
  my %old_snippets = map { $_ => 1 } map { @{$_} } values %{$old->{missed_snippets} || {}};

  my %files_with_new_snippets;
  for my $file (sort keys %$new_snippets) {
    for my $snippet (@{$new_snippets->{$file}}) {
      $files_with_new_snippets{$snippet} ||= $file unless $old_snippets{$snippet};
    }
  }
  return \%files_with_new_snippets;
}

# File IDs change on reindex, so persisted diffs join live reports by name.
sub new_unresolved_files ($old, $new) {
  my $new_snippets = _new_snippets($old, $new);
  return [map { {name => $_} } sort +uniq values %$new_snippets];
}

1;
