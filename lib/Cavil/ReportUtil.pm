
# Copyright (C) 2024 SUSE LLC
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, see <http://www.gnu.org/licenses/>.

package Cavil::ReportUtil;
use Mojo::Base -strict, -signatures;

use Exporter 'import';
use List::Util qw(uniq);
use Mojo::File qw(path);
use Mojo::JSON qw(from_json);
use Mojo::Util;
use Cavil::Licenses 'lic';
use Cavil::Util qw(SNIPPET_SCORE_VERSION extract_spdx_identifiers);

our @EXPORT_OK = (
  qw(estimated_risk hard_incompatibilities is_license_filename license_compatibility minimal_snippet),
  qw(new_license_names new_unresolved_files overlapping_licenses report_checksum report_shortname),
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

# The set of individual SPDX license identifiers actually present in a package's digest report,
# gathered from the licensed matches and the keyword-matched files. Compound expressions are reduced
# to their individual identifiers. The Classpath exception was created specifically to permit combining
# GPL code with otherwise-incompatible licenses (typically Apache-2.0 Java libraries), so
# "GPL... WITH Classpath-exception-2.0" fragments are stripped before extraction.
sub _present_licenses ($dig_report) {
  my @spdx;
  push @spdx, map { $_->{spdx} } grep { $_->{spdx} } values %{$dig_report->{licenses}  || {}};
  push @spdx, map { $_->[3] } grep    { $_->[3] } values %{$dig_report->{missed_files} || {}};
  s/\b(?:A|L)?GPL-[\d.]+(?:-only|-or-later|\+)?\s+WITH\s+Classpath-exception-2\.0\b//gi for @spdx;

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

  return {licenses => \@licenses, matrix => \%kept_matrix};
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
