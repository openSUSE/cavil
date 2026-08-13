# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package Cavil::Model::Snippets;
use Mojo::Base -base, -signatures;

use Mojo::File  qw(path);
use Cavil::Util qw(file_and_checksum read_lines);
use Cavil::ReportUtil
  qw(is_license_filename overlapping_licenses should_clear_boilerplate should_cover_snippet should_fold_snippet should_overlap_clear);

has [qw(checkout_dir pg snippet_fold)];

# A snippet is "reported" when a contributor/agent has filed a missing-license report against it (a
# proposed_changes row with action 'missing_license' whose data->>'snippet' is the snippet id) AND no
# new_license proposal has answered it yet. Excluding already-proposed snippets keeps the triage sweep
# self-limiting; the underlying report is kept as a fallback (see propose_new_license) and re-enters this
# set if the proposal is dismissed. Keyed on the id (not token_hexsum) to sidestep the snippet-hash prefix.
# Shared by snippet_search (MCP) and unclassified (web UI) so both surfaces resolve the same set.
my $REPORTED_EXISTS
  = "EXISTS (SELECT 1 FROM proposed_changes pc WHERE pc.action = 'missing_license'"
  . " AND (pc.data->>'snippet')::bigint = s.id)"
  . " AND NOT EXISTS (SELECT 1 FROM proposed_changes np WHERE np.action = 'new_license'"
  . " AND (np.data->>'snippet')::bigint = s.id)";

# Store resolution once so report consumers cannot reimplement or drift from these gates.
# Keep generations isolated while a reindex builds beside the live report.
sub resolve_snippets ($self, $package_id, $generation = 0) {
  my $db  = $self->pg->db;
  my $cfg = $self->snippet_fold;

  # Leave ignored snippets unresolved so consumers need no separate ignore rule.
  my $packname = $db->select('bot_packages', 'name', {id => $package_id})->hash->{name};
  my %ignored  = map { $_->{hash} => 1 } $db->select('ignored_lines', 'hash', {packname => $packname})->hashes->each;

# Catch-all markers cannot establish coverage; treating them as concrete can hide novel terms.
  my $cover_scope = ($cfg && $cfg->{enabled}) ? ($cfg->{cover_scope} // 'off') : 'off';
  my $cover       = $cover_scope ne 'off';
  my (%spans, %file_cover, %dir_cover, %file_dir);
  for my $m (
    $db->query(
      "SELECT pm.file, pm.sline, pm.eline, lp.license, lp.risk, mf.filename
       FROM pattern_matches pm
       JOIN license_patterns lp ON lp.id = pm.pattern
       JOIN matched_files mf ON mf.id = pm.file
      WHERE pm.package = ? AND pm.generation = ? AND pm.ignored = false AND lp.license <> ''
        AND lp.catch_all = false", $package_id, $generation
    )->hashes->each
    )
  {
    push @{$spans{$m->{file}}}, [$m->{sline}, $m->{eline}, $m->{license}];
    next unless $cover;
    my $risk = $m->{risk};
    $file_cover{$m->{file}} = $risk if !defined $file_cover{$m->{file}} || $risk > $file_cover{$m->{file}};
    my $dir = $m->{filename} =~ s{/[^/]*$}{}r;
    $dir_cover{$dir} = $risk if !defined $dir_cover{$dir} || $risk > $dir_cover{$dir};
  }

  if ($cover) {
    for my $f (
      $db->query(
        'SELECT DISTINCT mf.id, mf.filename FROM matched_files mf
           JOIN file_snippets fs ON fs.file = mf.id WHERE fs.package = ? AND fs.generation = ?', $package_id,
        $generation
      )->hashes->each
      )
    {
      $file_dir{$f->{id}} = $f->{filename} =~ s{/[^/]*$}{}r;
    }
  }

  my $rows = $db->query(
    'SELECT fs.id, fs.file, fs.sline, fs.eline, fs.resolution AS current_resolution, s.hash, s.license,
            s.likelyness, s.second_match, s.score_version, s.like_pattern, lp.license AS plicense, lp.risk AS prisk,
            lp.catch_all AS pcatch_all, mf.filename
       FROM file_snippets fs
       JOIN snippets s ON s.id = fs.snippet
       JOIN matched_files mf ON mf.id = fs.file
       LEFT JOIN license_patterns lp ON lp.id = s.like_pattern
      WHERE fs.package = ? AND fs.generation = ?', $package_id, $generation
  );

  # Bucket the few resolution values to avoid thousands of individual updates.
  my %ids_by_resolution;
  for my $row ($rows->hashes->each) {
    my $pattern = {license => $row->{plicense}, risk => $row->{prisk}};
    $row->{is_license_file} = is_license_filename($row->{filename});

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

    my $current = $row->{current_resolution};
    next
      if (defined $current && defined $resolution && $current eq $resolution)
      || (!defined $current && !defined $resolution);
    push @{$ids_by_resolution{defined $resolution ? $resolution : ''}}, $row->{id};
  }

  # Keep the write transaction short by computing first.
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

# Render stored resolution; curated matches remain authoritative for their own lines.
sub file_line_info ($self, $package_id, $file_id) {
  my $db   = $self->pg->db;
  my $info = {};

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

  # No generation predicate is needed anywhere here: the file id already belongs to exactly one report
  # generation, so every match and snippet joined through it comes from that same report
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

    # Preserve distinct explanations for two no-license outcomes.
    elsif ($resolution eq 'clear' || $resolution eq 'overlap') {
      $line_info = {
        %common,
        risk        => 0,
        name        => 'Cleared boilerplate',
        cleared     => 1,
        clearReason => $resolution eq 'overlap' ? 'overlap' : 'boilerplate'
      };
    }

    elsif ($resolution eq 'covered') {
      $line_info = {%common, risk => 0, name => 'Covered by existing license match', covered => 1};
    }
    else {
      $line_info = {%common, risk => 9, name => 'Snippet of missing keywords'};
      $line_info->{pids} = [$snippet->{like_pattern}] if $snippet->{like_pattern};
    }

    # Resolved regions defer to curated matches; unresolved regions retain precedence.
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

  # The new occurrence joins the report generation its file belongs to, so a manual snippet created
  # against the live report cannot end up attached to a build running alongside it (or the reverse)
  $db->insert(
    'file_snippets',
    {
      package    => $package->{id},
      snippet    => $snippet_id,
      sline      => $first_line,
      eline      => $last_line,
      file       => $file_id,
      generation => $file->{generation}
    }
  ) unless $exists;

  return $snippet_id;
}

# Indexing only records a file once something matched in it, so a file with no matches at all has no row
# to hang a snippet on. That is exactly the file whose license text nobody has a pattern for yet, so the
# row is created on demand; a reindex replaces these rows anyway, and the snippet outlives them.
sub from_file_path ($self, $package_id, $filename, $first_line, $last_line) {
  my $db   = $self->pg->db;
  my $file = $db->select('matched_files', 'id', {package => $package_id, filename => $filename, generation => 0})->hash;

  if (!$file) {
    return undef if $filename =~ /\.\./;
    return undef unless my $package = $db->select('bot_packages', ['name', 'checkout_dir'], {id => $package_id})->hash;

    my $unpacked = path($self->checkout_dir, $package->{name}, $package->{checkout_dir}, '.unpacked');
    my $path     = $unpacked->child($filename);
    return undef unless -f $path;

    # An unpacked archive can contain symlinks pointing anywhere, and the name has not been through
    # indexing, so the file has to be proven to sit inside this package before its content is read
    my $root = eval { $unpacked->realpath->to_string };
    my $real = eval { $path->realpath->to_string };
    return undef unless defined $root && defined $real && index($real, "$root/") == 0;

    # The mimetype is used for display alone
    $file->{id} = $db->insert(
      'matched_files',
      {package   => $package_id, filename => $filename, mimetype => 'text/plain', generation => 0},
      {returning => 'id'}
    )->hash->{id};
  }

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
  # are reused below to pin the linked occurrence to one that actually has that resolution. Every
  # occurrence clause is pinned to generation 0: a reindex building alongside a live report has a second
  # copy of every occurrence, and counting both would double every number on this page.
  my $resolution = '';
  my @binds;
  my @kinds;
  my $resolution_option = $options->{resolution} // 'any';
  my $match             = 'AND fs.generation = 0';
  if ($resolution_option eq 'unresolved') {
    $resolution = 'AND EXISTS (SELECT 1 FROM file_snippets fs WHERE fs.snippet = s.id AND fs.generation = 0
                       AND fs.resolution IS NULL)';
    $match .= ' AND fs.resolution IS NULL';
  }
  elsif ($resolution_option =~ /^(fold|clear|overlap|covered)$/) {
    @kinds = $1 eq 'clear' ? ('clear', 'overlap', 'covered') : ($1);
    my $placeholders = join ', ', ('?') x @kinds;
    $resolution = "AND EXISTS (SELECT 1 FROM file_snippets fs WHERE fs.snippet = s.id AND fs.generation = 0
                                 AND fs.resolution IN ($placeholders))";
    push @binds, @kinds;
    $match .= " AND fs.resolution IN ($placeholders)";
  }

  # "Reported" is independent of the file_snippets.resolution states by design: a report can be filed
  # against a snippet Cavil auto-resolved (folded/cleared/covered) as a correction, and hiding those would
  # let a wrongly-resolved new license slip through. So it does not touch $match/@kinds - the linked
  # occurrence and counts stay generation-only, and reported snippets surface whatever their resolution.
  elsif ($resolution_option eq 'reported') {
    $resolution = "AND $REPORTED_EXISTS";
  }

  # Full-text (lexeme) search over snippet bodies; expression matches the GIN index exactly.
  my $search = '';
  if (defined $options->{search} && $options->{search} ne '') {
    $search = "AND to_tsvector('english', s.text) @@ websearch_to_tsquery('english', ?)";
    push @binds, $options->{search};
  }

  # Keyset pagination with no exact total: fetch one extra row to learn whether a next page exists
  # (COUNT(*) OVER() scanned the whole filtered set on every page and does not scale to 1M snippets).
  my $count_match = 'AND fs_count.generation = 0';
  $count_match
    .= $resolution_option eq 'unresolved' ? ' AND fs_count.resolution IS NULL'
    : @kinds                              ? ' AND fs_count.resolution IN (' . join(', ', ('?') x @kinds) . ')'
    :                                       '';
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

# Grouping by content-derived snippet id aggregates identical text fleet-wide.
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
    : $res eq 'reported'                         ? $REPORTED_EXISTS
    : $res =~ /^(?:fold|clear|overlap|covered)$/ ? do { push @binds, $res; 'fs.resolution = ?' }
    :                                              'fs.resolution IS NULL';

  my $extra = '';
  if ($options->{package_id}) { $extra .= ' AND fs.package = ?'; push @binds, $options->{package_id}; }

  # Match the report's definition of an unresolved match (Cavil::Model::Reports missed_snippets
  # partition): drop snippets the classifier has decided are NOT license text (classified = true AND
  # license = false). Confirmed candidates (license = true) and snippets still pending classification
  # (classified = false) are kept. Without this the tool floods callers with classifier-rejected code
  # comments the report never shows, and its counts drift far above the package's unresolved_matches.
  #
  # Skip this for "reported": a missing-license report is an explicit human/agent assertion that the
  # snippet IS a license, and reporting one Cavil auto-resolved (folded/cleared/covered) or the classifier
  # rejected is an expected *correction*. Those must surface regardless of resolution or classifier verdict
  # (the res_clause above already imposes no resolution filter), and the curated report set can't flood.
  $extra .= ' AND (s.license OR NOT s.classified)' unless $res eq 'reported';
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
  # Occurrences are also pinned to the live report (generation 0), so a package being reindexed right now
  # contributes each of its occurrences once, not twice.
  my $visible
    = 'fs.generation = 0 AND bp.embargoed = false AND bp.obsolete = false AND COALESCE(sp.embargoed, false) = false';

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
        WHERE mf.package = ? AND mf.generation = 0 AND pm.ignored = false AND lp.license <> ''
          AND lp.catch_all = false AND regexp_replace(mf.filename, '/[^/]*$', '') = ?}, $package, $dir
    )->arrays->flatten->to_array
  };
}

sub mark_non_license ($self, $id) {
  $self->pg->db->update('snippets', {license => 0, approved => 1, classified => 1}, {id => $id});
}

# Every generation on purpose: this drives reindexing after a snippet decision, and a package whose
# in-flight build carries the snippet needs the reindex just as much as one whose live report does
sub packages_for_snippet ($self, $id) {
  return $self->pg->db->query('SELECT DISTINCT(package) FROM file_snippets WHERE snippet = ?', $id)
    ->arrays->flatten->to_array;
}

sub _occurrence ($db, $id, $file_id) {
  my $sql = 'SELECT fs.package, p.name, sline, eline, file, filename, p.checkout_dir
     FROM file_snippets fs JOIN matched_files m ON (m.id = fs.file)
       JOIN bot_packages p ON (p.id = fs.package)
     WHERE snippet = ? AND fs.generation = 0';
  my @bind = ($id);
  if (defined $file_id) {
    $sql .= ' AND fs.file = ?';
    push @bind, $file_id;
  }

  # Deterministic pick for the no-file_id fallback (standalone snippet/missing-license views): without
  # an order the arbitrary occurrence could flip between reindexes. Scoping by file_id above is the
  # real fix; this just keeps the fallback stable.
  $sql .= ' ORDER BY fs.file LIMIT 1';
  return $db->query($sql, @bind)->hash;
}

# A representative occurrence for detail enrichment, from a package that is neither embargoed nor
# obsolete - so detail never leaks an embargoed file path or describes dead (superseded) work.
sub _visible_occurrence ($db, $id) {
  return $db->query(
    'SELECT fs.package, fs.file, fs.sline, fs.eline
       FROM file_snippets fs JOIN bot_packages p ON p.id = fs.package
      WHERE fs.snippet = ? AND fs.generation = 0 AND p.embargoed = false AND p.obsolete = false LIMIT 1', $id
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
