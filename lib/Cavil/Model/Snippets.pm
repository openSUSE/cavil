# Copyright (C) 2019 SUSE Linux GmbH
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

package Cavil::Model::Snippets;
use Mojo::Base -base, -signatures;

use Mojo::File  qw(path);
use Cavil::Util qw(file_and_checksum read_lines);
use Cavil::ReportUtil
  qw(is_license_filename overlapping_licenses should_clear_boilerplate should_cover_snippet should_fold_snippet should_overlap_clear);
use Spooky::Patterns::XS;

has [qw(checkout_dir pg snippet_fold)];

# The single place the fold/clear/overlap/covered decision is made: for every snippet occurrence in a
# package compute its resolution and store it on file_snippets.resolution ('fold' / 'clear' / 'overlap'
# / 'covered' / undef). Called from the analyze task (per reindex) and from `snippets --rescore`; every
# consumer (report, file browser, SPDX, Classify Snippets) then just reads the column. The gates live in
# Cavil::ReportUtil and are called only here.
sub resolve_snippets ($self, $package_id) {
  my $db  = $self->pg->db;
  my $cfg = $self->snippet_fold;

  # Snippets the reviewer has ignored for this package are never resolved (they drop out as ignored
  # noise), so the stored column reflects that without any consumer needing its own ignore check.
  my $packname = $db->select('bot_packages', 'name', {id => $package_id})->hash->{name};
  my %ignored  = map { $_->{hash} => 1 } $db->select('ignored_lines', 'hash', {packname => $packname})->hashes->each;

  # Per-file line spans of non-ignored concrete license matches, for overlap detection. Grab-bag markers
  # (lp.catch_all: "Any floating warranty", "Any CLA", "All Rights Reserved", ...) are excluded, exactly
  # as they are for the "covered" resolution below: overlap-clear's premise is that the snippet swallowed
  # a *genuine* license declaration already on the report, and a catch_all marker is not one. Counting it
  # would clear a snippet that captured a real (possibly novel, higher-risk) license sitting next to some
  # boilerplate disclaimer - the exact way a custom relicense hides behind a retained BSD/MIT tail.
  my %spans;
  for my $m (
    $db->query(
      "SELECT pm.file, pm.sline, pm.eline, lp.license
       FROM pattern_matches pm JOIN license_patterns lp ON lp.id = pm.pattern
      WHERE pm.package = ? AND pm.ignored = false AND lp.license <> '' AND lp.catch_all = false", $package_id
    )->hashes->each
    )
  {
    push @{$spans{$m->{file}}}, [$m->{sline}, $m->{eline}, $m->{license}];
  }

  # Concrete (non-catch_all) license coverage per file and per directory, for the "covered" resolution:
  # a snippet is redundant when its file - or, at directory scope, its directory - already carries a real
  # license at least as risky. Grab-bag markers (lp.catch_all) never count as coverage.
  my $cover_scope = ($cfg && $cfg->{enabled}) ? ($cfg->{cover_scope} // 'off') : 'off';
  my (%file_cover, %dir_cover, %file_dir);
  if ($cover_scope ne 'off') {
    for my $m (
      $db->query(
        "SELECT pm.file, lp.risk, mf.filename
           FROM pattern_matches pm
           JOIN license_patterns lp ON lp.id = pm.pattern
           JOIN matched_files mf ON mf.id = pm.file
          WHERE pm.package = ? AND pm.ignored = false AND lp.license <> '' AND lp.catch_all = false", $package_id
      )->hashes->each
      )
    {
      my $risk = $m->{risk};
      $file_cover{$m->{file}} = $risk if !defined $file_cover{$m->{file}} || $risk > $file_cover{$m->{file}};
      my $dir = $m->{filename} =~ s{/[^/]*$}{}r;
      $dir_cover{$dir} = $risk if !defined $dir_cover{$dir} || $risk > $dir_cover{$dir};
    }

    # Directory of every snippet-bearing file, so directory-scope lookups work per occurrence
    for my $f (
      $db->query(
        'SELECT DISTINCT mf.id, mf.filename FROM matched_files mf
           JOIN file_snippets fs ON fs.file = mf.id WHERE fs.package = ?', $package_id
      )->hashes->each
      )
    {
      $file_dir{$f->{id}} = $f->{filename} =~ s{/[^/]*$}{}r;
    }
  }

  # Each occurrence with its snippet's similarity metadata and closest-license details
  my $rows = $db->query(
    'SELECT fs.id, fs.file, fs.sline, fs.eline, fs.resolution AS current_resolution, s.hash, s.license,
            s.likelyness, s.second_match, s.score_version, s.like_pattern, lp.license AS plicense, lp.risk AS prisk,
            lp.catch_all AS pcatch_all, mf.filename
       FROM file_snippets fs
       JOIN snippets s ON s.id = fs.snippet
       JOIN matched_files mf ON mf.id = fs.file
       LEFT JOIN license_patterns lp ON lp.id = s.like_pattern
      WHERE fs.package = ?', $package_id
  );

  # Compute each occurrence's resolution and bucket the ids by the resulting value, skipping rows already
  # at that value. resolution has only a handful of distinct values, so the writes below collapse into a
  # few bulk UPDATEs instead of thousands of per-row SQL::Abstract updates (the analyze hotspot).
  my %ids_by_resolution;
  for my $row ($rows->hashes->each) {
    my $pattern = {license => $row->{plicense}, risk => $row->{prisk}};
    $row->{is_license_file} = is_license_filename($row->{filename});

    # Highest-risk concrete license already covering this occurrence, per the configured scope
    my $cover_risk;
    if    ($cover_scope eq 'file') { $cover_risk = $file_cover{$row->{file}} }
    elsif ($cover_scope eq 'dir')  { $cover_risk = $dir_cover{$file_dir{$row->{file}} // ''} }

    my $resolution;
    if    ($ignored{$row->{hash}})                         { $resolution = undef }     # ignored -> unresolved
    elsif (should_fold_snippet($cfg, $row, $pattern))      { $resolution = 'fold' }
    elsif (should_clear_boilerplate($cfg, $row, $pattern)) { $resolution = 'clear' }
    elsif (should_overlap_clear($cfg, $row, overlapping_licenses($row->{sline}, $row->{eline}, $spans{$row->{file}}))) {
      $resolution = 'overlap';
    }
    elsif (should_cover_snippet($cfg, $row, $cover_risk)) { $resolution = 'covered' }

    # Skip rows whose resolution does not change (the common case on reindex)
    my $current = $row->{current_resolution};
    next
      if (defined $current && defined $resolution && $current eq $resolution)
      || (!defined $current && !defined $resolution);
    push @{$ids_by_resolution{defined $resolution ? $resolution : ''}}, $row->{id};
  }

  # One UPDATE per distinct resolution, in a short transaction (computation above ran outside it)
  my $tx = $db->begin;
  for my $resolution (sort keys %ids_by_resolution) {
    $db->query(
      'UPDATE file_snippets SET resolution = ? WHERE id = ANY(?::bigint[])',
      ($resolution eq '' ? undef : $resolution),
      $ids_by_resolution{$resolution}
    );
  }
  $tx->commit;
}

# Per-line match/snippet info for the file browser (and the report's inline file view), keyed by line
# number. Real curated license matches win their own lines; every remaining snippet renders from its
# stored resolution (computed once by resolve_snippets): 'fold' as the inferred license, 'clear' /
# 'overlap' / 'covered' as resolved (cleared) noise, anything else as an unresolved snippet. Resolved
# rows also carry the detail the file browser shows in its hover tooltip - what the snippet resembles,
# how similar, how confident the classifier was - so a reviewer can see *how* a snippet was resolved at a
# glance. That detail comes straight off the snippet row; the resolution itself was already decided by
# resolve_snippets, so nothing here re-derives overlap or coverage.
sub file_line_info ($self, $package_id, $file_id) {
  my $db   = $self->pg->db;
  my $info = {};

  # Real curated license matches win their own lines.
  my %matched;
  my $matches = $db->query(
    'SELECT pm.sline, pm.eline, lp.id, lp.license, lp.spdx, lp.risk
       FROM pattern_matches pm JOIN license_patterns lp ON lp.id = pm.pattern
      WHERE pm.package = ? AND pm.file = ? AND pm.ignored = false AND lp.license <> ?', $package_id, $file_id, ''
  );
  for my $match ($matches->hashes->each) {
    for my $line ($match->{sline} .. $match->{eline}) {
      $matched{$line} = 1;
      my $current = $info->{$line} // {risk => 0};
      next if $current->{risk} > $match->{risk};
      $info->{$line} = {risk => $match->{risk}, name => $match->{license}, spdx => $match->{spdx}, pid => $match->{id}};
    }
  }

  my $snippets = $db->query(
    'SELECT fs.sline, fs.eline, fs.resolution, s.id, s.hash, s.classified, s.license, s.like_pattern,
            s.likelyness, s.confidence, lp.license AS plicense, lp.spdx AS pspdx, lp.risk AS prisk
       FROM file_snippets fs
       JOIN snippets s ON s.id = fs.snippet
       LEFT JOIN license_patterns lp ON lp.id = s.like_pattern
      WHERE fs.package = ? AND fs.file = ?', $package_id, $file_id
  );
  for my $snippet ($snippets->hashes->each) {
    next if $snippet->{classified} && !$snippet->{license};
    my $resolution = $snippet->{resolution} // '';

    # Fields shared by every snippet row: the handle that keeps the region correctable, plus the tooltip
    # detail - the closest license it resembles (what the scorer keyed on), its similarity (the 0..1 score
    # scaled to a percentage, as in snippet_search) and the classifier confidence.
    my $has_closest = defined $snippet->{plicense} && $snippet->{plicense} ne '';
    my %common      = (
      snippet    => $snippet->{id},
      hash       => $snippet->{hash},
      similarity => int(($snippet->{likelyness} // 0) * 100 + 0.5),
      confidence => $snippet->{confidence} // 0,
      $has_closest
      ? (closest => $snippet->{plicense}, closestSpdx => $snippet->{pspdx}, closestRisk => $snippet->{prisk})
      : ()
    );

    my $line_info;
    if ($resolution eq 'fold') {
      $line_info = {
        %common,
        risk   => $snippet->{prisk},
        name   => $snippet->{plicense},
        spdx   => $snippet->{pspdx},
        pid    => $snippet->{like_pattern},
        folded => 1
      };
    }

    # Boilerplate-clear and overlap-clear both assert no license but for different reasons, so the tooltip
    # tells them apart via clearReason: 'boilerplate' resembles license body text naming no single
    # license; 'overlap' repeats a real license declaration inside the snippet's own lines (already
    # painted on those lines, so no need to name it again here).
    elsif ($resolution eq 'clear' || $resolution eq 'overlap') {
      $line_info = {
        %common,
        risk        => 0,
        name        => 'Cleared boilerplate',
        cleared     => 1,
        clearReason => $resolution eq 'overlap' ? 'overlap' : 'boilerplate'
      };
    }

    # Covered: a concrete license already established in this file or directory covers this fragment, so it
    # adds nothing - that license is already on the report through its own match.
    elsif ($resolution eq 'covered') {
      $line_info = {%common, risk => 0, name => 'Covered by existing license match', covered => 1};
    }
    else {
      $line_info = {%common, risk => 9, name => 'Snippet of missing keywords'};
      $line_info->{pids} = [$snippet->{like_pattern}] if $snippet->{like_pattern};
    }

    # A resolved snippet (fold/clear/overlap/covered) describes the region, but a real licensed match is
    # authoritative for its own line - it must not repaint a line that has its own curated match (e.g. a
    # "Free Software Foundation" match on the first line of a folded GPL header). Unresolved snippets
    # still take over their region (matching the report's needed_lines precedence).
    my $defers_to_match = $resolution =~ /^(?:fold|clear|overlap|covered)$/;
    for my $line ($snippet->{sline} .. $snippet->{eline}) {
      next if $defers_to_match && $matched{$line};
      my $current = $info->{$line} // {risk => 0};
      next if $current->{risk} > $line_info->{risk};    # do not hide a higher-risk match
      $info->{$line} = $line_info;
    }
  }

  return $info;
}

sub approve ($self, $id, $license) {
  my $db = $self->pg->db;
  $db->update('snippets', {license => $license eq 'true' ? 1 : 0, approved => 1, classified => 1}, {id => $id});
}

sub find ($self, $id) {
  return $self->pg->db->select('snippets', '*', {id => $id})->hash;
}

sub find_or_create ($self, $new) {
  $new->{prefix} //= '';
  my $db = $self->pg->db;

  my $old = $db->query(
    'SELECT s.id, bp.embargoed FROM snippets s LEFT JOIN bot_packages bp ON (bp.id = s.package)
     WHERE hash = ?', $new->{hash}
  )->hash;

  # Inherit embargo status until there is no embargo anymore (the value will tell us which package lifted the embargo)
  if ($old) {
    $db->query('UPDATE snippets SET package = ? WHERE id = ?', $new->{package}, $old->{id}) if $old->{embargoed};
    return $old->{id};
  }

  my $hash = "$new->{prefix}$new->{hash}";
  $db->query('INSERT INTO snippets (hash, text, package) VALUES (?, ?, ?) ON CONFLICT DO NOTHING',
    $hash, $new->{text}, $new->{package});
  return $db->select('snippets', 'id', {hash => $hash})->hash->{id};
}

sub from_file ($self, $file_id, $first_line, $last_line) {
  my $db   = $self->pg->db;
  my $file = $db->select('matched_files', '*', {id => $file_id})->hash;
  return undef unless $file;

  my $package = $db->select('bot_packages', '*', {id => $file->{package}})->hash;
  my $path    = path($self->checkout_dir, $package->{name}, $package->{checkout_dir}, '.unpacked', $file->{filename});

  my ($text, $hash) = file_and_checksum($path, $first_line, $last_line);
  my $snippet_id
    = $self->find_or_create({hash => $hash, text => $text, package => $package->{id}, prefix => 'manual:'});

  # Avoid duplicate links when the same range is requested again (e.g. an agent retry)
  my $exists = $db->select('file_snippets', 'id',
    {file => $file_id, snippet => $snippet_id, sline => $first_line, eline => $last_line})->hash;
  $db->insert('file_snippets',
    {package => $package->{id}, snippet => $snippet_id, sline => $first_line, eline => $last_line, file => $file_id})
    unless $exists;

  return $snippet_id;
}

sub from_file_path ($self, $package_id, $filename, $first_line, $last_line) {
  return undef
    unless my $file
    = $self->pg->db->select('matched_files', 'id', {package => $package_id, filename => $filename})->hash;
  return $self->from_file($file->{id}, $first_line, $last_line);
}

sub id_for_checksum ($self, $checksum) {
  return undef unless my $hash = $self->pg->db->select('snippets', 'id', {hash => $checksum})->hash;
  return $hash->{id};
}

sub unclassified ($self, $options) {
  my $db = $self->pg->db;

  my $before = '';
  if (($options->{order} // 'recent') eq 'recent' && $options->{before} > 0) {
    my $quoted = $db->dbh->quote($options->{before});
    $before = "AND s.id < $quoted";
  }

  my $confidence = '';
  if ($options->{confidence} < 100) {
    $confidence = "AND confidence <= " . $options->{confidence};
  }

  my $timeframe = '';
  if ($options->{timeframe} ne 'any') {
    my $interval = "1 $options->{timeframe}";
    $timeframe = "AND s.created > NOW() - INTERVAL '$interval'";
  }

  my $is_approved   = 'approved = ' . uc($options->{is_approved});
  my $is_classified = 'classified = ' . uc($options->{is_classified});

  my $legal = '';
  if ($options->{is_legal} eq 'true' && $options->{not_legal} eq 'false') {
    $legal = 'AND license = TRUE';
  }
  elsif ($options->{is_legal} eq 'false' && $options->{not_legal} eq 'true') {
    $legal = 'AND license = FALSE';
  }

  # Resolution filter: read the stored decision (file_snippets.resolution) - no logic here, so it
  # cannot drift from resolve_snippets. "Cleared" covers both clearing mechanisms. The matching kinds
  # are reused below to pin the linked occurrence to one that actually has that resolution.
  my $resolution = '';
  my @binds;
  my @kinds;
  my $resolution_option = $options->{resolution} // 'any';
  my $match             = '';
  if ($resolution_option eq 'unresolved') {
    $resolution = 'AND EXISTS (SELECT 1 FROM file_snippets fs WHERE fs.snippet = s.id AND fs.resolution IS NULL)';
    $match      = 'AND fs.resolution IS NULL';
  }
  elsif ($resolution_option =~ /^(fold|clear|overlap|covered)$/) {
    @kinds = $1 eq 'clear' ? ('clear', 'overlap', 'covered') : ($1);
    my $placeholders = join ', ', ('?') x @kinds;
    $resolution
      = "AND EXISTS (SELECT 1 FROM file_snippets fs WHERE fs.snippet = s.id AND fs.resolution IN ($placeholders))";
    push @binds, @kinds;
    $match = "AND fs.resolution IN ($placeholders)";
  }

  # Full-text (lexeme) search over snippet bodies; expression matches the GIN index exactly.
  my $search = '';
  if (defined $options->{search} && $options->{search} ne '') {
    $search = "AND to_tsvector('english', s.text) @@ websearch_to_tsquery('english', ?)";
    push @binds, $options->{search};
  }

  # Keyset pagination with no exact total: fetch one extra row to learn whether a next page exists
  # (COUNT(*) OVER() scanned the whole filtered set on every page and does not scale to 1M snippets).
  my $count_match
    = $resolution_option eq 'unresolved' ? 'AND fs_count.resolution IS NULL'
    : @kinds                             ? 'AND fs_count.resolution IN (' . join(', ', ('?') x @kinds) . ')'
    :                                      '';
  my @count_binds = (@kinds, @kinds);
  my $order       = $options->{order} // 'recent';
  my $order_by
    = $order eq 'occurrences' ? 'occurrence_count DESC, package_count DESC, s.id DESC'
    : $order eq 'packages'    ? 'package_count DESC, occurrence_count DESC, s.id DESC'
    : $order eq 'risk'        ? 'lp.risk DESC NULLS LAST, occurrence_count DESC, s.id DESC'
    :                           's.id DESC';
  my $offset   = $order eq 'recent' ? '' : 'OFFSET ' . int($options->{offset} // 0);
  my $snippets = $db->query(
    "SELECT s.*, bp.embargoed,
            (SELECT count(*) FROM file_snippets fs_count WHERE fs_count.snippet = s.id $count_match) AS occurrence_count,
            (SELECT count(DISTINCT fs_count.package) FROM file_snippets fs_count WHERE fs_count.snippet = s.id $count_match)
              AS package_count
     FROM snippets s
       LEFT JOIN bot_packages bp ON (bp.id = s.package)
       LEFT JOIN license_patterns lp ON (lp.id = s.like_pattern)
     WHERE $is_approved AND $is_classified $before $legal $confidence $timeframe $resolution $search
     ORDER BY $order_by LIMIT 11 $offset", @count_binds, @binds
  )->hashes->to_array;

  my $has_more = @$snippets > 10 ? 1 : 0;
  splice @$snippets, 10 if $has_more;

  # When a resolution filter is active, restrict the occurrence we link to (and count) to occurrences
  # that actually carry that resolution - a shared snippet can be folded in one file and unresolved in
  # another, so the generic "most recent occurrence" could otherwise send reviewers to the wrong file.
  for my $snippet (@$snippets) {
    $snippet->{likelyness} = int($snippet->{likelyness} * 100);
    $snippet->{files}
      = $db->query("SELECT count(*) AS n FROM file_snippets fs WHERE fs.snippet = ? $match", $snippet->{id}, @kinds)
      ->hash->{n};
    my $file = $db->query(
      "SELECT fs.sline, mf.filename, mf.package AS filepackage
       FROM file_snippets fs JOIN matched_files mf ON (fs.file = mf.id)
       WHERE fs.snippet = ? $match ORDER BY fs.id DESC LIMIT 1", $snippet->{id}, @kinds
    )->hash // {};
    $snippet->{$_} = $file->{$_} for qw(filename sline filepackage);

    my $license = $db->query('SELECT license, risk FROM license_patterns WHERE id = ? AND license != ?',
      $snippet->{like_pattern} // 0, '')->hash // {};
    $snippet->{license_name} = $license->{license};
    $snippet->{risk}         = $license->{risk};
  }

  return {has_more => $has_more, snippets => $snippets};
}

# Query the snippet backlog generically for agents/UI (backs the cavil_search_snippets MCP tool).
# Filter by resolution ('unresolved' = resolution IS NULL / fold|clear|overlap|covered / 'any'),
# optional package scope, closest-license, and full-text search; then either aggregate identical
# snippets by impact (group => 'text') or list individual occurrences (group => 'none'). Snippets are
# content-hash-deduped (find_or_create), so grouping by s.id already aggregates fleet-wide. The
# unresolved path is served by the partial indexes file_snippets_unresolved_snippet_idx/_package_idx.
sub snippet_search ($self, $options) {
  my $db = $self->pg->db;

  my $limit  = $options->{limit}  || 20;
  my $offset = $options->{offset} || 0;
  my $group  = ($options->{group} // 'text') eq 'none' ? 'none' : 'text';

  # Shared filters (bind order matters)
  my @binds;
  my $res = $options->{resolution} // 'unresolved';
  my $res_clause
    = $res eq 'any'                              ? '1 = 1'
    : $res eq 'unresolved'                       ? 'fs.resolution IS NULL'
    : $res =~ /^(?:fold|clear|overlap|covered)$/ ? do { push @binds, $res; 'fs.resolution = ?' }
    :                                              'fs.resolution IS NULL';

  my $extra = '';
  if ($options->{package_id}) { $extra .= ' AND fs.package = ?'; push @binds, $options->{package_id}; }

  # Match the report's definition of an unresolved match (Cavil::Model::Reports missed_snippets
  # partition): drop snippets the classifier has decided are NOT license text (classified = true AND
  # license = false). Confirmed candidates (license = true) and snippets still pending classification
  # (classified = false) are kept. Without this the tool floods callers with classifier-rejected code
  # comments the report never shows, and its counts drift far above the package's unresolved_matches.
  $extra .= ' AND (s.license OR NOT s.classified)';
  if (defined $options->{license} && $options->{license} ne '') {
    $extra .= ' AND lp.license = ?';
    push @binds, $options->{license};
  }
  if (defined $options->{search} && $options->{search} ne '') {
    $extra .= " AND to_tsvector('english', s.text) @@ websearch_to_tsquery('english', ?)";
    push @binds, $options->{search};
  }

  # Package-state gates. sp (snippets.package) is the canonical text-level embargo: a snippet stays
  # embargoed until an unembargoed package re-links it (see find_or_create), so this keeps embargoed
  # license text out entirely; s.package is nullable (origin deleted), which we treat as unembargoed.
  # bp (file_snippets.package) is the occurrence gate: never reveal - or count - an occurrence living
  # in an embargoed OR obsolete package. Obsolete packages are superseded, so their unresolved
  # snippets are dead work; excluding them (as every other query does) keeps the impact ranking real.
  my $visible = 'bp.embargoed = false AND bp.obsolete = false AND COALESCE(sp.embargoed, false) = false';

  # Fetch one extra row to detect a next page without an exact total (COUNT(*) OVER does not scale).
  my $rows;
  if ($group eq 'none') {
    $rows = $db->query(
      "SELECT s.id AS snippet_id, mf.filename AS file, fs.sline AS line, fs.eline AS eline, fs.file AS file_id,
              fs.package, fs.resolution, s.text, s.likelyness AS similarity, s.second_match, s.score_version,
              lp.license AS closest_license, lp.risk AS closest_risk, lp.spdx AS closest_spdx
       FROM file_snippets fs
         JOIN snippets s ON s.id = fs.snippet
         JOIN matched_files mf ON mf.id = fs.file
         JOIN bot_packages bp ON bp.id = fs.package
         LEFT JOIN bot_packages sp ON sp.id = s.package
         LEFT JOIN license_patterns lp ON lp.id = s.like_pattern
       WHERE $visible AND $res_clause $extra
       ORDER BY mf.filename, fs.sline
       LIMIT ? OFFSET ?", @binds, $limit + 1, $offset
    )->hashes->to_array;
  }
  else {
    my $order
      = ($options->{order} // 'occurrences') eq 'packages' ? 'packages DESC, occurrences DESC'
      : ($options->{order} // '') eq 'risk'   ? 'closest_risk DESC NULLS LAST, occurrences DESC'
      : ($options->{order} // '') eq 'recent' ? 'snippet_id DESC'
      :                                         'occurrences DESC, packages DESC';
    $rows = $db->query(
      "SELECT s.id AS snippet_id, count(*) AS occurrences, count(DISTINCT fs.package) AS packages,
              s.likelyness AS similarity, s.text,
              lp.license AS closest_license, lp.risk AS closest_risk, lp.spdx AS closest_spdx
       FROM file_snippets fs
         JOIN snippets s ON s.id = fs.snippet
         JOIN bot_packages bp ON bp.id = fs.package
         LEFT JOIN bot_packages sp ON sp.id = s.package
         LEFT JOIN license_patterns lp ON lp.id = s.like_pattern
       WHERE $visible AND $res_clause $extra
       GROUP BY s.id, s.text, s.likelyness, lp.license, lp.risk, lp.spdx
       ORDER BY $order
       LIMIT ? OFFSET ?", @binds, $limit + 1, $offset
    )->hashes->to_array;
  }

  my $has_more = @$rows > $limit ? 1 : 0;
  splice @$rows, $limit if $has_more;

  for my $r (@$rows) { $r->{similarity} = int(($r->{similarity} // 0) * 100 + 0.5) }

  # Tier-2 detail (bounded by page size): overlaps / covered-by / keywords, for agent decisions.
  $self->_enrich_snippet_detail($db, $_) for $options->{detail} || $group eq 'none' ? @$rows : ();

  return {has_more => $has_more, offset => $offset, limit => $limit, group => $group, snippets => $rows};
}

# Tier-2 detail for one snippet_search row: the decision context the human report trims away via
# minimal_snippet. Adds `overlaps` (curated matches on/adjacent to the snippet's lines, with position),
# `keywords` (the literal keyword tokens that tripped it), and `covered_by` (concrete non-catch_all
# licenses established in the file / its directory). Bounded - called once per returned page row.
sub _enrich_snippet_detail ($self, $db, $row) {
  my $sid = $row->{snippet_id};

  # Describe the row's own occurrence (group=none) or a representative one (group=text). The
  # group=none row already comes from an unembargoed occurrence, but the group=text fallback must
  # not pick one in an embargoed package - that would leak an embargoed file path/context.
  my ($file_id, $sline, $eline, $package) = @{$row}{qw(file_id line eline package)};
  unless ($file_id) {
    my $occ = _visible_occurrence($db, $sid) or return;
    ($file_id, $sline, $eline, $package) = @{$occ}{qw(file sline eline package)};
  }
  return unless $file_id;

  # Curated matches intersecting or abutting [sline, eline] in this file. License matches become
  # `overlaps` (with position vs the snippet); empty-license keyword patterns become `keywords`.
  my $near = $db->query(
    'SELECT lp.license, lp.spdx, lp.pattern, pm.sline, pm.eline
       FROM pattern_matches pm JOIN license_patterns lp ON lp.id = pm.pattern
      WHERE pm.file = ? AND pm.ignored = false AND pm.eline >= ? AND pm.sline <= ?
      ORDER BY pm.sline', $file_id, $sline - 1, $eline + 1
  )->hashes;
  my (@overlaps, %kw);
  for my $m (@$near) {
    if ($m->{license} ne '') {
      my $pos
        = ($m->{sline} <= $sline && $m->{eline} >= $eline) ? 'contains'
        : ($m->{sline} >= $sline && $m->{eline} <= $eline) ? 'inside'
        : ($m->{eline} < $eline)                           ? 'head'
        :                                                    'tail';
      push @overlaps,
        {license => $m->{license}, spdx => $m->{spdx}, position => $pos, lines => "$m->{sline}-$m->{eline}"};
    }
    elsif (defined $m->{pattern} && $m->{pattern} ne '') { $kw{$m->{pattern}} = 1 }
  }
  $row->{overlaps} = \@overlaps;
  $row->{keywords} = [sort keys %kw];

  # covered_by: concrete (non catch_all) licenses established in the file and its directory.
  my $filename = $db->query('SELECT filename FROM matched_files WHERE id = ?', $file_id)->hash->{filename} // '';
  my $dir      = $filename =~ s{/[^/]*$}{}r;
  $row->{covered_by} = {
    file => $db->query(
      q{SELECT DISTINCT lp.license FROM pattern_matches pm JOIN license_patterns lp ON lp.id = pm.pattern
        WHERE pm.file = ? AND pm.ignored = false AND lp.license <> '' AND lp.catch_all = false}, $file_id
    )->arrays->flatten->to_array,
    dir => $db->query(
      q{SELECT DISTINCT lp.license FROM pattern_matches pm JOIN license_patterns lp ON lp.id = pm.pattern
          JOIN matched_files mf ON mf.id = pm.file
        WHERE mf.package = ? AND pm.ignored = false AND lp.license <> '' AND lp.catch_all = false
          AND regexp_replace(mf.filename, '/[^/]*$', '') = ?}, $package, $dir
    )->arrays->flatten->to_array
  };
}

sub mark_non_license ($self, $id) {
  $self->pg->db->update('snippets', {license => 0, approved => 1, classified => 1}, {id => $id});
}

sub packages_for_snippet ($self, $id) {
  return $self->pg->db->query('SELECT DISTINCT(package) FROM file_snippets WHERE snippet = ?', $id)
    ->arrays->flatten->to_array;
}

sub _occurrence ($db, $id, $file_id) {
  my $sql = 'SELECT fs.package, p.name, sline, eline, file, filename, p.checkout_dir
     FROM file_snippets fs JOIN matched_files m ON (m.id = fs.file)
       JOIN bot_packages p ON (p.id = fs.package)
     WHERE snippet = ?';
  my @bind = ($id);
  if (defined $file_id) {
    $sql .= ' AND fs.file = ?';
    push @bind, $file_id;
  }
  $sql .= ' LIMIT 1';
  return $db->query($sql, @bind)->hash;
}

# A representative occurrence for detail enrichment, from a package that is neither embargoed nor
# obsolete - so detail never leaks an embargoed file path or describes dead (superseded) work.
sub _visible_occurrence ($db, $id) {
  return $db->query(
    'SELECT fs.package, fs.file, fs.sline, fs.eline
       FROM file_snippets fs JOIN bot_packages p ON p.id = fs.package
      WHERE fs.snippet = ? AND p.embargoed = false AND p.obsolete = false LIMIT 1', $id
  )->hash;
}

sub with_context ($self, $id, $file_id = undef) {
  return undef unless my $snippet = $self->find($id);

  my $text     = $snippet->{text};
  my $sline    = 1;
  my $package  = undef;
  my $matches  = {};
  my $keywords = {};

  my $db = $self->pg->db;

  # Snippets are deduplicated by content hash, so the same snippet can occur in
  # many files across many packages, each with its own line numbers. When a
  # caller knows which occurrence it is showing (file_id), scope the lookup to
  # that file so the reported line numbers and context match it; otherwise fall
  # back to an arbitrary occurrence (standalone snippet views).
  my $example;
  $example = _occurrence($db, $id, $file_id) if defined $file_id;
  $example //= _occurrence($db, $id, undef);

  if ($example) {
    $sline   = $example->{sline};
    $package = {id => $example->{package}, name => $example->{name}, filename => $example->{filename}};

    my $file = path($self->checkout_dir, $package->{name}, $example->{checkout_dir}, '.unpacked', $example->{filename});
    $text = read_lines($file, $example->{sline}, $example->{eline});

    my $patterns = $db->query(
      'SELECT lp.id, lp.license, sline, eline FROM pattern_matches pm JOIN license_patterns lp ON (lp.id = pm.pattern)
     WHERE file = ? AND sline >= ? AND eline <= ? ORDER BY sline', $example->{file}, $example->{sline},
      $example->{eline}
    )->hashes;

    # Several patterns can cover the same line (two keyword patterns, or a license and a keyword match),
    # so each line keeps the full list of pattern ids - the editor highlight and the pinned reference
    # tooltip both show every pattern on a line, not just the last one seen.
    for my $pattern (@$patterns) {
      my $map = $pattern->{license} ? $matches : $keywords;
      for (my $line = $pattern->{sline}; $line <= $pattern->{eline}; $line += 1) {
        push @{$map->{$line - $example->{sline}}}, $pattern->{id};
      }
    }
  }

  return {
    package  => $package,
    matches  => $matches,
    keywords => $keywords,
    sline    => $sline,
    text     => $text,
    hash     => $snippet->{hash}
  };
}

1;
