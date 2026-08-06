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
  qw(license_compatibility license_obligations license_obligation_ids minimal_snippet),
  qw(new_license_names new_unresolved_files overlapping_licenses ranked_incompatibilities report_checksum report_shortname),
  qw(should_clear_boilerplate should_cover_snippet should_fold_snippet should_overlap_clear smart_edit_snippet),
  qw(spdx_edit_snippet summary_delta summary_delta_score)
);

use constant PAD_WORDS => 5;

# The OSADL license compatibility matrix (CC-BY-4.0, see the NOTICE file), bundled and refreshed via
# tools/update_licenses.pl. It is a directed grid keyed outbound -> inbound; a cell records OSADL's
# verdict ("No" / "Check dependency" / "Unknown") and verbatim explanation for using inbound-licensed
# material in an outbound-licensed work. Plainly compatible ("Yes"/"Same") cells are omitted, so a
# missing cell means "compatible". Cached on first use.
sub _compatibility_matrix () {
  state $matrix = from_json(path(__FILE__)->dirname->child('resources', 'license_compatibility.json')->slurp)->{matrix};
  return $matrix;
}

# The OSADL obligation dataset (CC-BY-4.0, see the NOTICE file), bundled and refreshed via
# tools/update_licenses.pl alongside the compatibility matrix. Per-license obligation checklists
# grouped by delivery use case, plus copyleft and source-code-disclosure classifications, keyed by
# SPDX identifier. The file's "source" key records provenance (see the NOTICE file); only the
# "licenses" map is consumed here. The file contains non-ASCII text (e.g. the copyright sign), so it
# is read with decode_json. Cached on first use.
sub _obligations_data () {
  state $data = decode_json(path(__FILE__)->dirname->child('resources', 'license_obligations.json')->slurp);
  return $data;
}

# The SPDX license classification flags (CC0), bundled and refreshed via tools/update_licenses.pl,
# keyed by SPDX identifier. Each entry carries "osi" (OSI approval, always present) and "fsf" (FSF
# "libre" status) - the latter only for the licenses the FSF has actually ruled on, so a missing key
# means "no ruling", not "not free". Cached on first use.
sub _license_flags_data () {
  state $data = decode_json(path(__FILE__)->dirname->child('resources', 'license_flags.json')->slurp);
  return $data;
}

# Strip "GPL... WITH Classpath-exception-2.0" fragments from an SPDX string before its identifiers are
# extracted. The Classpath exception exists specifically to permit combining GPL code with otherwise-
# incompatible licenses (typically Apache-2.0 Java libraries), so it must not contribute a bare GPL
# identifier to the compatibility check. Used by _present_licenses; obligations deliberately do NOT strip
# it - an exception relaxes duties rather than removing the base license, so license_obligation_ids keeps
# the base license and the UI flags the exception instead.
sub _strip_classpath_exception ($string) {
  $string =~ s/\b(?:A|L)?GPL-[\d.]+(?:-only|-or-later|\+)?\s+WITH\s+Classpath-exception-2\.0\b//gi;
  return $string;
}

# The ordered, de-duplicated OSADL-known SPDX identifiers named in one license-list entry, which may be a
# compound expression ("MIT OR BSD-3-Clause") and/or carry a "WITH <exception>". extract_spdx_identifiers
# pulls out the individual license identifiers (exceptions are not licenses, so they drop out here); OR
# and AND are treated alike. Unlike the compatibility matrix, exceptions are NOT stripped: an exception
# relaxes rather than removes the base license's duties, so the base obligations are shown and the UI
# flags the exception (OSADL's checklists cover the base license only). Unknown identifiers are dropped.
sub license_obligation_ids ($name, $data = undef) {
  $data //= _obligations_data();
  return [] unless defined $name;
  my $licenses = $data->{licenses} // {};
  return [uniq grep { $licenses->{$_} } @{extract_spdx_identifiers($name)}];
}

# The OSADL obligation entries (verbatim) for the identifiers in one license-list entry, in expression
# order. Each element is {license, patent_hints, copyleft, source_disclosure, use_cases} (only the keys
# OSADL provides for that license). Returns an empty list when OSADL covers none of the identifiers, so
# the report can omit the panel entirely. Obligations are purely informational: like the compatibility
# matrix they never feed report_checksum, report_shortname or summary_delta.
sub license_obligations ($name, $data = undef) {
  $data //= _obligations_data();
  my $licenses = $data->{licenses} // {};
  return [map { {license => $_, %{$licenses->{$_}}} } @{license_obligation_ids($name, $data)}];
}

# Everything the external datasets say about the identifiers in one license-list entry, merged into a
# single entry per identifier so the report can present all of it in one place. OSADL contributes the
# obligation checklist plus its copyleft / source-disclosure / patent classifications, SPDX the OSI and
# FSF flags; the two share no keys. Identifiers are extracted (and exceptions kept) exactly as for
# obligations, and an identifier is included when EITHER source knows it - SPDX covers a good deal more
# licenses than OSADL publishes checklists for, and for those the flags are all there is to show. An
# empty list means neither source knows anything, so the report omits the panel entirely. Purely
# informational: like obligations and the compatibility matrix, this never feeds report_checksum,
# report_shortname or summary_delta.
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

# Shared, precision-first decision for whether an unresolved snippet is confident enough to be
# treated as resolved to its closest license ("folded"). Used by both the report and the file
# browser so the two views agree. $cfg is the snippet_fold config; $snippet carries the scorer
# metadata (license = "is legal text", likelyness, second_match, score_version); $pattern is the
# closest license's pattern (license + risk). See docs/Architecture.md for the rationale.
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

# Decide whether an unresolved snippet is recognizable known-license *body text* ("boilerplate")
# that can be cleared from the backlog WITHOUT asserting a license. Unlike folding, there is no
# margin or risk gate and no license is recorded: most backlog snippets are middle-of-license
# boilerplate shared across sibling licenses (high similarity, no margin) whose real license is
# already on the report from its title match, so clearing them is safe and we deliberately do not
# guess which sibling it is. Novel licenses score low and stay below clear_threshold.
sub should_clear_boilerplate ($cfg, $snippet, $pattern) {
  return 0 unless $cfg && $cfg->{enabled};
  return 0 unless my $threshold = $cfg->{clear_threshold};                                # 0/undef disables clearing
  return 0 unless $snippet->{license};                                                    # classifier says legal text
  return 0 unless ($snippet->{score_version} // 0) == SNIPPET_SCORE_VERSION;              # scored by current model
  return 0 unless $pattern && defined $pattern->{license} && $pattern->{license} ne '';

  return ($snippet->{likelyness} // 0) >= $threshold ? 1 : 0;
}

# Licenses (deduped) of the non-ignored licensed pattern matches whose line range intersects a
# snippet. $spans is an arrayref of [sline, eline, license] for one file. The FileIndexer expands a
# snippet around keyword matches and often swallows a real license match (e.g. an SPDX line); this
# finds those overlaps so the snippet can be recognized as already-resolved noise.
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

# Decide whether a snippet is redundant because its region overlaps a real, curated license match:
# that license is already on the report via the match, and the rest of the snippet is keyword-tripping
# code/doc-comment noise, so the snippet is cleared (assert nothing). Independent of the classifier's
# legal/non-legal score version - the overlap is authoritative. The guard keeps snippets whose own
# content strongly resembles a license *outside* the overlap set (a possible missed/foldable license),
# which is the safe direction; stale or absent scores can only push toward keeping. $overlap_licenses
# comes from overlapping_licenses(); $snippet->{plicense} is the snippet's closest license (if any).
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

# Decide whether a snippet is redundant because the file (or, at directory scope, a sibling file) is
# already known to carry a real license at least as risky - so this awkward license fragment adds
# nothing the report does not already have and is cleared (assert nothing). Unlike overlap-clear, the
# covering match need not intersect the snippet's own lines; unlike folding, it asserts no license.
# $cover_risk is the highest risk among the *concrete* (non-catch_all) license matches in scope,
# computed by resolve_snippets per the configured cover_scope ('file' or 'dir'); undef means nothing
# concrete covers this scope. Three guards make this safe: (1) only concrete licenses count as
# coverage (a real license hiding behind a weak "Any ..."/"All Rights Reserved" marker is never
# mistaken for one), enforced upstream when $cover_risk is built; (2) risk-monotonicity - a snippet
# resembling a *higher*-risk license than the coverage is kept, since it might be a genuinely new,
# riskier license. The snippet's own risk is its closest license's risk ($prisk), or 0 when it
# resembles no specific license (pure keyword noise in an already-licensed scope); and (3) when that
# closest license is a grab-bag catch_all marker, its risk read is unreliable (the bucket spans many
# risks - "Any CLA" alone runs 0..5), so risk-monotonicity cannot be trusted for it: such a fragment
# is only cleared when its similarity is high enough that it genuinely IS that boilerplate. A weak,
# ambiguous grab-bag match is kept for review - this is the open-webui LICENSE case, where novel
# non-commercial terms scored only 0.63 against "Any CLA" while the file carried a real BSD-3-Clause,
# and risk-monotonicity against the incidental risk-1 CLA member would otherwise clear them. Genuine
# filler (a real disclaimer, an "All Rights Reserved" line) scores high against its marker and still
# clears, so this does not regress the bulk auto-clearing of license-file boilerplate.
sub should_cover_snippet ($cfg, $snippet, $cover_risk) {
  return 0 unless $cfg && $cfg->{enabled} && (($cfg->{cover_scope} // 'off') ne 'off');
  return 0 unless $snippet->{license};                                                    # classifier says legal text
  return 0 unless ($snippet->{score_version} // 0) == SNIPPET_SCORE_VERSION;              # trust the risk read
  return 0 unless defined $cover_risk;    # a concrete license covers this scope

  # Grab-bag closest match in a license-declaration file: only clear if the fragment really is that
  # boilerplate (high similarity). This is scoped to license files on purpose - a weak grab-bag match in
  # a LICENSE/COPYING file is the "novel license bolted onto a retained standard one" case (open-webui,
  # redis), whereas the same weak match in a code/doc file is the stray disclaimer/notice this feature
  # exists to clear. Measurement showed the license-file case is ~10% of grab-bag-closest coverage, so
  # scoping keeps the guard's precision high without resurfacing the bulk of genuine filler.
  return 0
    if $snippet->{is_license_file}
    && $snippet->{pcatch_all}
    && ($snippet->{likelyness} // 0) < ($cfg->{cover_guard} // 0.9);

  my $snippet_risk = (defined $snippet->{plicense} && $snippet->{plicense} ne '') ? ($snippet->{prisk} // 0) : 0;
  return $snippet_risk <= $cover_risk ? 1 : 0;
}

# Does this path look like a license-declaration file (LICENSE, COPYING, LICENSE.txt, ...) rather than a
# source/doc file that merely mentions a license? Used to scope the grab-bag coverage guard above: the
# basename must START with a license-declaration word so that license-list *reference data* named after a
# license id (e.g. .../licenses/OGDL-Taiwan-1.0) is not mistaken for the package's own license file.
sub is_license_filename ($path) {
  return $path =~ m{(?:^|/)(?:LICEN[CS]E|COPYING|COPYRIGHT|NOTICE|EULA|LEGAL|UNLICENSE)(?:[.\-]|$)}i ? 1 : 0;
}

# The set of individual SPDX license identifiers present in a package's digest report, gathered from the
# licensed matches (real + folded) and the keyword-matched files. Compound expressions are reduced to their
# individual identifiers, with the Classpath exception stripped first (see _strip_classpath_exception).
#
# Keyword/unresolved matches (missed_files) ARE included: a legal reviewer must see every possible
# incompatibility, so a low-confidence guess is surfaced rather than hidden. proximity then carries the
# confidence (real match > fold > unresolved guess) and the UI labels weak evidence as such - the matrix
# shows everything and lets the human judge, it never silently drops a pair.
sub _present_licenses ($dig_report) {
  my @spdx;
  push @spdx, map { $_->{spdx} } grep { $_->{spdx} } values %{$dig_report->{licenses}  || {}};
  push @spdx, map { $_->[3] } grep    { $_->[3] } values %{$dig_report->{missed_files} || {}};
  @spdx = map { _strip_classpath_exception($_) } @spdx;

  my %present;
  $present{$_}++ for map { @{extract_spdx_identifiers($_)} } @spdx;
  return \%present;
}

# OSADL's compatibility matrix restricted to the licenses present in this package - i.e. OSADL's own
# sub-matrix for exactly these licenses, presented verbatim. Returns
# {licenses => [...], matrix => {outbound => {inbound => {compatibility, explanation}}}} where
# "licenses" are the present licenses that take part in at least one flagged (No/Check dependency)
# relationship, and "matrix" holds every non-compatible OSADL cell (No/Check dependency/Unknown) among
# the present licenses. Missing cells mean OSADL considers that direction compatible. Nothing is
# collapsed, curated or reinterpreted; the directional structure and explanations are OSADL's.
sub license_compatibility ($dig_report, $matrix = undef) {
  $matrix //= _compatibility_matrix();
  my $present = _present_licenses($dig_report);

  # Every non-compatible OSADL cell between two present licenses, and which licenses take part in an
  # actionable (No/Check dependency) relationship - "Unknown" alone does not put a license on the axes.
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

  # Drop Unknown-only licenses from the axes and from the returned matrix, so the grid stays focused on
  # licenses that actually have an actionable relationship.
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

  # Rank the flagged pairs by how closely their licenses actually co-locate in the file tree: two
  # incompatible licenses sitting in the same directory are far more likely to be a real combination
  # than two that only share the package root (typically vendored/aggregated, never linked). Purely a
  # ranking annotation - nothing is hidden or reinterpreted.
  $result->{proximity} = _pair_proximity($dig_report, \@licenses, \%kept_matrix);

  return $result;
}

# The individual SPDX identifiers present in each file of a digest report, each with a confidence rank, as
# {filename => {id => confidence}}. Confidence is 3 for a real pattern match, 2 for a folded snippet (both
# come from {risks}{risk}{name}{pid} => [file ids], told apart by {file_confidence}{file id}{name}, which
# _register_license stamps), and 1 for the guessed closest license of an UNRESOLVED snippet ({missed_files}
# - often weak, e.g. a file whose only real license is GPL-2.0-or-later but whose unresolved header scores
# 0.23 against GPL-3.0-or-later). Reconstructed from the already-assembled report structures (no extra
# query); compound expressions are reduced to identifiers with the Classpath exception stripped, exactly as
# _present_licenses does. Proximity uses the rank to pick a pair's representative co-location from the
# strongest available evidence (real files for both licenses beat a fold, which beats an unresolved guess).
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

          # file_confidence is only ever absent in synthetic/test reports; treat those as a real match.
          $bump->($path, $ids, $conf->{$fid}{$name} // 3);
        }
      }
    }
  }

  # Unresolved snippets contribute their guessed closest license at the lowest confidence (1). missed_files
  # is keyed by file id here (the raw report), so resolve it to a path via {files} - the key is not a
  # filename. The guess is weak, but proximity ranks it last and the UI labels it "via an unresolved match"
  # rather than hiding it, so a reviewer still sees the possible incompatibility.
  my $missed = $dig_report->{missed_files} || {};
  for my $fid (keys %$missed) {
    my $path = $files->{$fid} // next;
    my $spdx = $missed->{$fid}[3];
    next unless defined $spdx && $spdx ne '';
    $bump->($path, extract_spdx_identifiers(_strip_classpath_exception($spdx)), 1);
  }

  return \%file_ids;
}

# The directory path of every ancestor of a file, deepest last, always including the package root ('').
sub _ancestor_dirs ($path) {
  my @segs = split m{/}, $path;
  pop @segs;    # drop the filename itself
  my @dirs = ('');
  my $acc  = '';
  for my $seg (@segs) {
    $acc = $acc eq '' ? $seg : "$acc/$seg";
    push @dirs, $acc;
  }
  return @dirs;
}

# Depth of a directory path: the root ('') is 0, 'src' is 1, 'src/foo' is 2.
sub _dir_depth ($dir) { return $dir eq '' ? 0 : (($dir =~ tr{/}{}) + 1) }

# Path segments that mark a file as peripheral rather than shipped/linked source: tests, documentation,
# bundled examples, vendored third-party trees, and license-text collections. Two incompatible licenses
# that meet only in such files are almost never a real combination (a test fixture, a doc that enumerates
# license identifiers, a vendored sample), so proximity ranks them below any genuine source co-location.
my %PERIPHERAL_SEGMENT = map { $_ => 1 } qw(
  doc docs documentation
  test tests testing
  example examples sample samples
  vendor vendored _vendor third_party third-party 3rdparty contrib node_modules
  licenses
);

# Does this file live under a peripheral directory? Classified by directory only - the basename is left
# alone, so a source file merely named like a license (e.g. gpl.c) is not demoted.
sub _path_is_peripheral ($path) {
  my @segs = split m{/}, $path;
  pop @segs;
  for my $seg (@segs) { return 1 if $PERIPHERAL_SEGMENT{lc $seg} }
  return 0;
}

# For each flagged (incompatible) pair, where the two licenses most convincingly co-locate. Returns
# {a => {b => {confidence, same_file, lca_depth, peripheral, files => [fa, fb]}}} keyed a lt b. For each pair
# it picks the evidence a reviewer should actually open, best first:
#   1. core (shipped source) over peripheral - tests/docs/vendored, and license-catalog dirs like LICENSES/
#      where unrelated license *texts* sit side by side, which is not a code combination;
#   2. higher confidence - a real match (3) over a fold (2) over an unresolved-snippet guess (1);
#   3. same file over a shared directory;
#   4. the deepest shared directory.
# Core outranks confidence deliberately: a peripheral real match is worse for research than any co-location
# in the shipped code.
#
# One walk of the file tree. Directory co-location uses only resolved licenses (confidence >= 2: real matches
# and folds); unresolved guesses (confidence 1) can number in the tens of thousands in a big package, far too
# many to walk trees for, so they contribute through same-file co-occurrence only. Per directory we keep, per
# license bit, the max confidence and a representative file - once for all files, once for core files - so the
# preferences above are a cheap comparison. Cost is O(resolved files x path depth) for the walk plus
# O(files + dirs-with-2+-licenses x flagged pairs) for the evaluation; only files carrying a flagged license
# are ever touched.
sub _pair_proximity ($dig_report, $licenses, $matrix) {
  return {} unless @$licenses;

  # The unordered participating pairs that have at least one non-compatible cell in either direction, as
  # [a, b, bit_a, bit_b] for fast bit-AND membership tests.
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

  # Single walk. dir_aconf/dir_arep track, per directory and license bit, the max confidence and a
  # representative file across all files; dir_cconf/dir_crep the same restricted to core (non-peripheral)
  # files; dir_amask/dir_cmask are the license bitmasks for O(1) "2+ licenses here" and pair-membership
  # tests. @same_file collects files carrying 2+ flagged licenses (any confidence, unresolved included).
  my (%dir_amask, %dir_cmask, %dir_aconf, %dir_arep, %dir_cconf, %dir_crep, @same_file, %lic_rep, %lic_resolved);
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

      # One representative file per license (any), and whether it has any resolved match. Cheap - a hash
      # write, no directory walk - and used to point a "not co-located" pair at its unresolved match's file.
      $lic_rep{$b} //= $path;
      $lic_resolved{$b} = 1 if $c >= 2;
    }
    push @same_file, [$path, $amask, ($path =~ tr{/}{}), _path_is_peripheral($path) ? 1 : 0] if $amask & ($amask - 1);
    next unless %bconf;

    my $core  = _path_is_peripheral($path) ? 0 : 1;
    my $rmask = 0;
    $rmask |= (1 << $_) for keys %bconf;
    for my $dir (_ancestor_dirs($path)) {
      $dir_amask{$dir} |= $rmask;
      $dir_cmask{$dir} |= $rmask if $core;
      while (my ($b, $c) = each %bconf) {
        if ($c > ($dir_aconf{$dir}{$b} // 0)) { $dir_aconf{$dir}{$b} = $c; $dir_arep{$dir}{$b} = $path }
        next unless $core;
        if ($c > ($dir_cconf{$dir}{$b} // 0)) { $dir_cconf{$dir}{$b} = $c; $dir_crep{$dir}{$b} = $path }
      }
    }
  }

  # Rank a candidate co-location as core (1e6) > confidence (1e4) > same-file (1e2) > directory depth, so the
  # single best per pair is a running max.
  my %best;
  my $consider = sub ($la, $lb, $cand) {
    $cand->{_score} = $cand->{peripheral} ? 0 : 1_000_000;
    $cand->{_score} += $cand->{confidence} * 10_000 + $cand->{same_file} * 100 + $cand->{lca_depth};
    my $cur = $best{$la}{$lb};
    $best{$la}{$lb} = $cand if !$cur || $cand->{_score} > $cur->{_score};
  };

  # Directory candidates (resolved licenses): core and full, for every dir holding 2+ of them.
  for my $dir (keys %dir_amask) {
    my $am = $dir_amask{$dir};
    next unless $am & ($am - 1);
    my $cm    = $dir_cmask{$dir} // 0;
    my $depth = _dir_depth($dir);
    for my $fp (@flagged_pairs) {
      my ($la, $lb, $ba, $bb) = @$fp;
      my ($mba, $mbb) = (1 << $ba, 1 << $bb);
      next unless ($am & $mba) && ($am & $mbb);
      if (($cm & $mba) && ($cm & $mbb)) {
        my $conf = $dir_cconf{$dir}{$ba} < $dir_cconf{$dir}{$bb} ? $dir_cconf{$dir}{$ba} : $dir_cconf{$dir}{$bb};
        $consider->(
          $la, $lb,
          {
            confidence => $conf,
            same_file  => 0,
            lca_depth  => $depth,
            peripheral => 0,
            files      => [$dir_crep{$dir}{$ba}, $dir_crep{$dir}{$bb}]
          }
        );
      }
      my $conf = $dir_aconf{$dir}{$ba} < $dir_aconf{$dir}{$bb} ? $dir_aconf{$dir}{$ba} : $dir_aconf{$dir}{$bb};
      $consider->(
        $la, $lb,
        {
          confidence => $conf,
          same_file  => 0,
          lca_depth  => $depth,
          peripheral => 1,
          files      => [$dir_arep{$dir}{$ba}, $dir_arep{$dir}{$bb}]
        }
      );
    }
  }

  # Same-file candidates (any confidence, unresolved guesses included).
  for my $sf (@same_file) {
    my ($path, $mask, $depth, $periph) = @$sf;
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
          peripheral => $periph,
          files      => [$path, $path]
        }
      );
    }
  }

  # Flagged pairs that never co-locate (a side present only via an unresolved guess that shares no file with
  # the other) still get an entry, pointing at that unresolved match's file so the reviewer can open and
  # judge it instead of hitting a dead end. no_colocation ranks these last; the UI links the file.
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
      peripheral    =>  0,
      files         => [map { $lic_rep{$_} } @weak]
    };
  }

  # Drop the internal score before returning.
  delete $_->{_score} for map { values %$_ } values %best;
  return \%best;
}

# The unordered pairs of present licenses that OSADL marks "No" in BOTH directions - i.e. combinations
# that cannot be shipped whichever license is treated as the outbound one. These are the hard
# incompatibilities that elevate risk and drive the compact text/MCP summary and the report checksum.
# Returns a sorted list of [a, b] (a lt b).
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

# A single ranked view of a package's flagged incompatibilities, shared by the web report data, the text
# report and the MCP report so the ordering and annotations never diverge. Takes the license_compatibility
# structure (licenses / matrix / proximity) and returns an arrayref of unordered pairs (a lt b), each
# {a, b, mutual, no_colocation, confidence, same_file, lca_depth, peripheral, files => [fa, fb]}, most
# interesting first: co-located pairs before not-co-located ones, then core (shipped) over peripheral, then
# confidence (real match > fold > unresolved guess), then same-file, then deepest shared directory, then
# mutual-No over one-directional, then alphabetical. This is the same order the reports and UI heat use.
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
        // {no_colocation => 1, confidence => 0, same_file => 0, lca_depth => -1, peripheral => 0, files => []};
      push @rows,
        {
        a             => $a,
        b             => $b,
        mutual        => $hard{"$a\x00$b"}   ? 1 : 0,
        no_colocation => $p->{no_colocation} ? 1 : 0,
        confidence    => $p->{confidence} // 0,
        same_file     => $p->{same_file},
        lca_depth     => $p->{lca_depth},
        peripheral    => $p->{peripheral},
        files         => $p->{files} // []
        };
    }
  }

  return [
    sort {
      $a->{no_colocation}   <=> $b->{no_colocation}    # co-located pairs first, not-co-located last
        || $a->{peripheral} <=> $b->{peripheral}
        || $b->{confidence} <=> $a->{confidence}
        || $b->{same_file}  <=> $a->{same_file}
        || $b->{lca_depth}  <=> $a->{lca_depth}
        || $b->{mutual}     <=> $a->{mutual}
        || $a->{a}          cmp $b->{a}
        || $a->{b}          cmp $b->{b}
    } @rows
  ];
}

# A short markdown description of where a flagged pair's two licenses co-locate, for the text and MCP
# reports (which both mark file paths with backticks). Returns a string only for the co-locations that
# actually warrant a look - one file carrying both, or both in the same directory - and undef otherwise
# (they meet only across different directories or at the package root), so callers can use definedness to
# separate the pairs worth investigating from the aggregation tail.
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

# Anchor for the start of a copyright line. Matches optional leading whitespace
# and common comment markers (#, *, //, ;), then one of: Copyright [optional
# (c)/(C)/©], a bare (c)/(C)/©, or an SPDX-FileCopyrightText: /
# SPDX-SnippetCopyrightText: prefix.
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

# Collapse the variable part of a copyright line (holders, years, emails, URLs)
# to $SKIP10. Returns the original line unchanged if it does not look like a
# copyright declaration. Operates on a single line (no embedded newlines).
sub _collapse_copyright_line ($line) {
  return $line unless $line =~ $COPYRIGHT_ANCHOR;
  return "$1 \$SKIP10";
}

# Auto-trim a snippet down to its legally meaningful core: strip license-match
# lines at the boundaries (via minimal_snippet), then trim word-by-word outside
# the keyword span, keeping at most PAD_WORDS words of padding on each side.
# Finally, collapse the variable portion of any copyright lines in the result
# to $SKIP10. The text is no longer a strict substring of the original, but
# still matches the original via Cavil::Util::pattern_matches because $SKIP10
# is a wildcard. Line count is preserved so frontend line decorations remain
# valid.
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

  # Rebase keyword line indices into the trimmed text
  my $offset   = $minimal_sline - $original_sline;
  my @kw_lines = sort { $a <=> $b } grep { $_ >= 0 } map { $_ - $offset } keys %$keywords;
  return $finalize->($text, $minimal_sline) unless @kw_lines;

  my @lines    = split /\n/, $text, -1;
  my $first_kw = $kw_lines[0];
  my $last_kw  = $kw_lines[-1];
  return $finalize->($text, $minimal_sline) if $last_kw >= @lines;

  # Byte offsets for the start of the first keyword line and the end of the
  # last keyword line (without the trailing newline)
  my $span_start = 0;
  $span_start += length($lines[$_]) + 1 for 0 .. $first_kw - 1;
  my $span_end = $span_start;
  $span_end += length($lines[$_]) + 1 for $first_kw .. $last_kw - 1;
  $span_end += length($lines[$last_kw]);

  # Leading trim: keep at most PAD_WORDS tokens of the prefix
  my $new_start = 0;
  if ($span_start > 0) {
    my $prefix = substr($text, 0, $span_start);
    my @starts;
    while ($prefix =~ /\S+/g) { push @starts, $-[0] }
    if (@starts > PAD_WORDS) { $new_start = $starts[-PAD_WORDS] }
  }

  # Trailing trim: keep at most PAD_WORDS tokens of the suffix
  my $new_end = length($text);
  if ($span_end < $new_end) {
    my $suffix = substr($text, $span_end);
    my @ends;
    while ($suffix =~ /\S+/g) { push @ends, $+[0] }
    if (@ends > PAD_WORDS) { $new_end = $span_end + $ends[PAD_WORDS - 1] }
  }

  my $trimmed = substr($text, $new_start, $new_end - $new_start);

  # Adjust start_line by the number of complete lines dropped from the front
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

  # Specfile license
  my $canon_license = lic($specfile_report->{main}{license})->canonicalize->to_string;
  $canon_license ||= "Unknown";
  my $text = "RPM-License $canon_license\n";

  # Licenses
  for my $license (sort { $a cmp $b } keys %{$dig_report->{licenses}}) {
    next if $dig_report->{licenses}{$license}{risk} == 0;
    $text .= "LIC:$license";
    for my $flag (@{$dig_report->{licenses}{$license}{flags}}) {
      $text .= ":$flag";
    }
    $text .= "\n";
  }

  # Unique snippets of unresolved keyword matches. Walk missed_snippets (the
  # full set of winning files) rather than snippets (the expansion-truncated
  # subset), and sort the resulting hashes so two content-equivalent
  # packages produce the same checksum regardless of file_id ordering.
  if (my $snippets = $dig_report->{missed_snippets}) {
    my @all;
    for my $file (keys %$snippets) {
      push @all, $_->[3] for @{$snippets->{$file}};
    }
    $text .= "SNIPPET:$_\n" for sort +uniq @all;
  }

  # The license compatibility matrix is deliberately NOT part of the checksum: it is informational
  # context derived from the present license set (which is already hashed above), and incompatibilities
  # are now common enough that they should not, on their own, drive re-reviews.

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

  # License incompatibilities are informational only and no longer elevate the risk: with the full
  # OSADL matrix they are common (usually vendored/aggregated, not real combinations), so escalating
  # every one to risk 9 floods the review queue and destroys the signal.

  my $l = lic($specfile_report->{main}{license})->example;
  $l ||= 'Unknown';

  return "$l-$max_risk:$chksum";
}

sub summary_delta ($old, $new) {
  my @blocks;

  # Specfile license change
  if ($new->{specfile} ne $old->{specfile}) {
    push @blocks, "  Spec file license  $old->{specfile} -> $new->{specfile}";
  }

  # New snippet matches (a count only; the individual files are flagged "new" in
  # the Risk 9 unresolved-matches section from the structured diff report).
  my $new_snippets = _new_snippets($old, $new);
  if (my $num = uniq values %$new_snippets) {
    push @blocks, $num == 1 ? '  New unresolved matches' : "  New unresolved matches in $num files";
  }

  # New licenses, sorted by risk desc then SPDX alphabetical
  my $new_licenses = _new_licenses($old, $new);
  if (my @lics = keys %$new_licenses) {
    my @sorted = sort { $new_licenses->{$b} <=> $new_licenses->{$a} || $a cmp $b } @lics;
    my @lines  = ('  New licenses (by risk)');
    push @lines,  map {"    $new_licenses->{$_}  $_"} @sorted;
    push @blocks, join("\n", @lines);
  }

  # License incompatibilities are deliberately NOT part of the diff: they are informational OSADL
  # context (see license_compatibility), common across packages, and must not drive review priority.

  return '' unless @blocks;
  return "Diff to closest match $old->{id}\n\n" . join("\n\n", @blocks) . "\n";
}

sub summary_delta_score ($old, $new) {
  my $score = 0;

  # Specfile license change
  $score += 1000 if $new->{specfile} ne $old->{specfile};

  # New snippet matches
  my $new_snippets = _new_snippets($old, $new);
  $score += 10 * keys %$new_snippets;

  # New licenses
  my $new_licenses = _new_licenses($old, $new);
  $score += 10 * $new_licenses->{$_} for keys %$new_licenses;

  return $score;
}

# New licenses between two summaries, keyed by bare license name => risk. The
# report UI has one row per license (flags are labels, not separate rows), so
# "new" is by name: the summary keys the licenses as "name:flag:flag" and we
# compare the name only (license names never contain ":", which is why the
# summary can use it as the flag separator in the first place).
sub _new_licenses ($old, $new) {
  my %old_licenses = map { (split /:/, $_)[0] => 1 } keys %{$old->{licenses} || {}};

  my %new_licenses;
  for my $lic (keys %{$new->{licenses}}) {
    my $name = (split /:/, $lic)[0];
    $new_licenses{$name} //= $new->{licenses}{$lic} unless $old_licenses{$name};
  }
  return \%new_licenses;
}

# The names of the new licenses between two summaries, sorted; used to flag them
# in the report UI (parallel to new_unresolved_files).
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

# The complete set of files with new unresolved matches between the closest
# previous report ($old) and the current one ($new), as [{name}] sorted by name.
# Keyed by filename only: matched_files ids are regenerated on every reindex, so
# the stored diff report must join back to the live report by name, not id (see
# the badge logic in Cavil::Plugin::Helpers). This is the same set of names the
# notice count in summary_delta reports, so the two never disagree.
sub new_unresolved_files ($old, $new) {
  my $new_snippets = _new_snippets($old, $new);
  return [map { {name => $_} } sort +uniq values %$new_snippets];
}

1;
