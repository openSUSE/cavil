# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package Cavil::Model::Patterns;
use Mojo::Base -base, -signatures;

use Cavil::Util qw(license_is_catch_all license_link normalize_license_expr paginate pattern_checksum),
  qw(pattern_contains_skip),
  qw(spdx_link text_shingle_ids SNIPPET_SCORE_VERSION PRIORITY_WAITING @LICENSE_FLAGS @PATTERN_FLAGS);
use List::Util qw(max min sum);
use Mojo::File qw(path tempfile);
use Mojo::JSON qw(true false);
use Mojo::Util qw(md5_sum);
use Cavil::PatternEngine;

# Bounds of the cavil_test_pattern dry run (also run on every AI pattern proposal)
use constant TEST_PATTERN_CANDIDATES => 1000;
use constant TEST_PATTERN_TIMEOUT    => 10;

use constant SIMILARITY_PROBE_SHINGLES => 20;

# Corpus evaluation found three-token shingles give the best precision.
use constant SIMILARITY_SHINGLE_SIZE => 3;

# Require two rare shared shingles to reject generic single-token matches.
use constant SIMILARITY_DISTINCTIVE_IDF => 4.0;
use constant SIMILARITY_MIN_DISTINCTIVE => 2;

has [qw(cache log pg minion)];

# Snippet-similarity data lives in the database (pattern_shingles / shingle_license), not on disk, so only
# the compiled matcher and the tf-idf bag are cached here.
sub matcher_cache_file ($self) {
  return path($self->cache, 'cavil.matcher');
}

sub bag_cache_file ($self) {
  return path($self->cache, 'cavil.pattern.bag.cavil');
}

sub _all_cache_files ($self) {
  my $cache = path($self->cache);
  return map { $cache->child($_) } qw(cavil.matcher cavil.pattern.bag.cavil);
}

use constant LICENSE_DETAIL_MATCH_LIMIT   => 10_000;
use constant LICENSE_DETAIL_PACKAGE_LIMIT => 1_000;
use constant LICENSE_PREDICTION_THRESHOLD => 0.3;
use constant LICENSE_PREDICTION_LIMIT     => 10;

# One risk/flags combination per license for pre-filling editors. Catch-alls ("Any ...") carry patterns at
# many risks, so pick deterministically: the most common combination wins (ascending order, last write
# wins), the higher risk on a tie. Anything that must not guess uses license_risks instead.
sub autocomplete ($self) {
  my $licenses = {};

  my $columns  = join ', ', @LICENSE_FLAGS;
  my $patterns = $self->pg->db->query(
    "SELECT license, risk, $columns, catch_all, COUNT(*) AS patterns FROM license_patterns
      GROUP BY license, risk, $columns, catch_all ORDER BY patterns ASC, risk ASC"
  )->hashes;
  for my $pattern ($patterns->each) {
    $licenses->{$pattern->{license}}
      = {risk => $pattern->{risk}, catch_all => $pattern->{catch_all}, map { $_ => $pattern->{$_} } @LICENSE_FLAGS};
  }
  delete $licenses->{''};

  return $licenses;
}

# Every risk level a license's patterns use, lowest first, with the pattern count and the flags and text of
# its oldest pattern as an example (the one most likely to be curated rather than derived).
sub license_risks ($self, $license) {
  my $columns = join ', ', @LICENSE_FLAGS;
  return $self->pg->db->query(
    "SELECT DISTINCT ON (risk) risk, $columns, pattern AS example, COUNT(*) OVER (PARTITION BY risk) AS patterns
       FROM license_patterns WHERE license = ? ORDER BY risk ASC, id ASC", $license
  )->hashes->to_array;
}

sub closest_licenses ($self, $expr) {
  my $licenses = $self->autocomplete;

  # Exact match after normalization (case, whitespace, "+"/"-or-later", "OR" order)
  my %canonical;
  $canonical{normalize_license_expr($_)} //= $_ for sort keys %$licenses;
  my $normalized = normalize_license_expr($expr);
  return {closest => []} unless length $normalized;
  if (my $exact = $canonical{$normalized}) {
    return {exact => {license => $exact, %{$licenses->{$exact}}}};
  }

  # Otherwise rank known licenses by trigram similarity to the normalized expression
  my $matches = $self->pg->db->query(
    "SELECT license, similarity(LOWER(license), ?) AS score
       FROM (SELECT DISTINCT license FROM license_patterns WHERE license != '') AS known
      WHERE similarity(LOWER(license), ?) >= ?
      ORDER BY score DESC, license ASC
      LIMIT ?", $normalized, $normalized, LICENSE_PREDICTION_THRESHOLD, LICENSE_PREDICTION_LIMIT
  )->hashes;

  return {closest => [map { {license => $_->{license}, score => $_->{score}} } @$matches]};
}

sub closest_pattern ($self, $text) {
  return undef unless my $match   = $self->closest_match($text);
  return undef unless my $pattern = $self->find($match->{pattern});
  $pattern->{similarity} = int(($match->{match} // 0) * 1000 + 0.5) / 10;
  return $pattern;
}

sub closest_match ($self, $text) { $self->closest_matches($text, 1)->[0] }

sub closest_matches ($self, $text, $num) {
  my $cache = $self->bag_cache_file;
  return [] unless -r $cache;
  my $bag = Cavil::PatternEngine::init_bag_of_patterns;
  $bag->load($cache);
  return $bag->best_for($text, $num);
}

# Use the caller's transaction; empty-license keyword patterns are not fold targets.
sub sync_pattern_shingles ($self, $db, $id, $license, $text) {
  $db->query('DELETE FROM pattern_shingles WHERE pattern_id = ?', $id);
  return unless defined $license && length $license;
  my @shingles = keys %{text_shingle_ids($text, SIMILARITY_SHINGLE_SIZE)};
  return unless @shingles;
  $db->query('INSERT INTO pattern_shingles (pattern_id, license, shingle) SELECT ?, ?, unnest(?::bigint[])',
    $id, $license, \@shingles);
}

# One-time (re)population of the whole table from license_patterns - the migration backfill, and a resync
# after a shingle-format change. This is the only full pass; routine pattern edits are incremental via
# sync_pattern_shingles.
sub backfill_pattern_shingles ($self) {
  my $db = $self->pg->db;
  my $tx = $db->begin;

  # Disable the shingle_license triggers for the bulk load - firing them per row would mean millions of
  # single-row upserts. We rebuild shingle_license wholesale from the finished table instead (a couple of
  # seconds), which is exactly what the triggers would have produced row by row.
  $db->query('ALTER TABLE pattern_shingles DISABLE TRIGGER USER');
  $db->query('DELETE FROM pattern_shingles');
  for my $row ($db->query('SELECT id, license, pattern FROM license_patterns')->hashes->each) {
    $self->sync_pattern_shingles($db, $row->{id}, $row->{license}, $row->{pattern});
  }
  $db->query('DELETE FROM shingle_license');
  $db->query('INSERT INTO shingle_license (shingle, license) SELECT DISTINCT shingle, license FROM pattern_shingles');
  $db->query('ALTER TABLE pattern_shingles ENABLE TRIGGER USER');
  $tx->commit;

  # Refresh planner stats after the bulk load so the indexes are used immediately (before autovacuum would
  # otherwise get to it); a stale-stats seq scan over millions of rows would make scoring crawl.
  $db->query('ANALYZE pattern_shingles');
  $db->query('ANALYZE shingle_license');
  return $self;
}

# Snippets are scored by IDF-weighted containment against per-license signatures - the union of a
# license's patterns' token-shingles. The data lives in two tables maintained incrementally as patterns
# change (see sync_pattern_shingles): shingle_license is the license-level inverted index (one row per
# distinct shingle/license pair) used for df, candidate gathering and containment; pattern_shingles keeps
# the per-pattern shingles used only for the final closest-pattern refinement.

# Best matching license for a snippet's shingle ids, given a context holding the per-license signatures.
# The scoring math lives here so both callers stay identical: score_snippets (context built from the DB
# working set) and "cavil eval_fold" (context built from a held-out sample). Candidates come from the
# snippet's most distinctive (rarest) shingles, are re-ranked by weighted containment, and ties are broken
# by the winning license's lowest pattern id so the pick is reproducible across worker processes.
sub best_license ($self, $ids, $ctx) {
  return {license => undef, match => 0, second => 0} unless @$ids;
  my $idf = $ctx->{idf};

  # Sort the shingles once, up front: the weighted sums below are floating point, so a fixed summation
  # order is what makes the score (and thus the winner) reproducible - the shingle set arrives as unordered
  # hash keys, whose iteration order varies with Perl's hash seed from run to run.
  my @ids = sort { $a <=> $b } @$ids;

  # Rarest shingles first; the secondary sort on id keeps the top-N cut deterministic on IDF ties.
  my @distinctive = sort { ($idf->{$b} // 0) <=> ($idf->{$a} // 0) || $a <=> $b } @ids;
  my %candidates;
  for my $shingle (@distinctive[0 .. min(SIMILARITY_PROBE_SHINGLES, scalar @distinctive) - 1]) {
    my $licenses = $ctx->{index}{$shingle} or next;
    $candidates{$_} = 1 for keys %$licenses;
  }
  return {license => undef, match => 0, second => 0} unless %candidates;

  # Weight each snippet shingle once (a shared denominator), then score each candidate by summing only the
  # weights of the shingles its signature contains. An unseen shingle weighs 1 (//1), as in the reference.
  my $denom = 0;
  $denom += ($idf->{$_} // 1) for @ids;
  my @scored;
  for my $license (sort keys %candidates) {
    my $sig = $ctx->{signatures}{$license} // {};
    my $hit = 0;
    for my $shingle (@ids) { $hit += ($idf->{$shingle} // 1) if $sig->{$shingle} }
    push @scored, [$license, $denom > 0 ? $hit / $denom : 0, $ctx->{min_pid}{$license} // 0];
  }

  # Winner by score, then by the license's lowest pattern id - a deterministic tie-break for the shared
  # boilerplate that genuinely ties several related licenses (GPL-2.0/3.0/...).
  @scored = sort { $b->[1] <=> $a->[1] || $a->[2] <=> $b->[2] } @scored;
  my $best   = $scored[0] // [undef, 0];
  my $second = $scored[1] // [undef, 0];

  # Required-phrase gate (borrowed from ScanCode): a confident match must share at least min_distinctive
  # high-IDF shingles with the winner, not rest entirely on common boilerplate. Boilerplate-only matches
  # drop to no-confidence, the safe direction - the snippet stays unresolved rather than folding wrongly.
  if (defined $best->[0]) {
    my $sig         = $ctx->{signatures}{$best->[0]} // {};
    my $distinctive = grep { $sig->{$_} && ($idf->{$_} // 0) >= $ctx->{distinctive_idf} } @ids;
    $best = [undef, 0] if $distinctive < $ctx->{min_distinctive};
  }

  return {license => $best->[0], match => $best->[1], second => defined $best->[0] ? $second->[1] : 0};
}

# Score a batch of snippets ([{id, text}, ...]); returns a hashref of per-id scores, or undef when the
# tables are empty (bootstrapping - callers fall back to the bag). It loads the batch's *working set* - the
# shingles its snippets actually use - once, then scores every snippet in memory, so it scales to any
# snippet count without holding a per-worker copy of the whole corpus. Four bounded queries per batch, then
# everything is in memory:
#   1. the corpus license count (the IDF denominator);
#   2. the license-level slice for the working set (df + inverted index + per-license signatures);
#   3. each candidate license's lowest pattern id (the deterministic tie-break);
#   4. the winning licenses' patterns (for the closest-pattern refinement).
sub score_snippets ($self, $rows) {
  return {} unless @$rows;
  my $db = $self->pg->db;
  return undef unless $db->query('SELECT 1 FROM shingle_license LIMIT 1')->rows;

  # Shingle every snippet up front; their union is the working set the queries below are scoped to.
  my (%ids, %union);
  for my $row (@$rows) {
    my @shingles = keys %{text_shingle_ids($row->{text}, SIMILARITY_SHINGLE_SIZE)};
    $ids{$row->{id}} = \@shingles;
    $union{$_} = 1 for @shingles;
  }
  my @working = keys %union;
  return {map { $_->{id} => _empty_score() } @$rows} unless @working;

  # (1) IDF denominator = distinct licenses with a signature. This is deliberately taken from
  # shingle_license rather than license_patterns, which would also count the handful of non-empty-license
  # patterns whose text normalizes to no shingles. The DISTINCT-in-a-subquery form is a few times faster
  # than COUNT(DISTINCT).
  my $total = $db->query('SELECT COUNT(*) AS c FROM (SELECT DISTINCT license FROM shingle_license) t')->hash->{c};

  # (2) License-level slice for the working set: df (per shingle, counting licenses not the hundreds of
  # thousands of pattern rows a common shingle has), the inverted index (shingle -> licenses, for
  # candidate gathering) and the per-license signatures (license -> shingles, for containment).
  my (%idf, %index, %signatures, %df);
  for my $r ($db->query('SELECT shingle, license FROM shingle_license WHERE shingle = ANY(?::bigint[])', \@working)
    ->hashes->each)
  {
    $index{$r->{shingle}}{$r->{license}}      = 1;
    $signatures{$r->{license}}{$r->{shingle}} = 1;
    $df{$r->{shingle}}++;
  }
  $idf{$_} = log(($total + 1) / ($df{$_} + 1)) + 1 for keys %df;

  # (3) The lowest pattern id of each candidate license, for best_license's deterministic tie-break.
  my %min_pid;
  if (my @licenses = keys %signatures) {
    for my $r (
      $db->query(
        'SELECT license, MIN(id) AS min_id FROM license_patterns WHERE license = ANY(?::text[]) GROUP BY license',
        \@licenses)->hashes->each
      )
    {
      $min_pid{$r->{license}} = $r->{min_id};
    }
  }

  my $ctx = {
    idf             => \%idf,
    index           => \%index,
    signatures      => \%signatures,
    min_pid         => \%min_pid,
    distinctive_idf => SIMILARITY_DISTINCTIVE_IDF,
    min_distinctive => SIMILARITY_MIN_DISTINCTIVE
  };

  # First pass: each snippet's winning license, and the distinct set of winners.
  my (%best, %winners);
  for my $row (@$rows) {
    my $b = $self->best_license($ids{$row->{id}}, $ctx);
    $best{$row->{id}}       = $b;
    $winners{$b->{license}} = 1 if defined $b->{license};
  }

  # (4) The winning licenses' patterns (scoped to the working set), aggregated to one row per pattern so a
  # grab-bag winner's rows never fan out across the wire.
  my %patterns;
  if (my @won = keys %winners) {
    for my $r (
      $db->query(
        'SELECT license, pattern_id, array_agg(shingle) AS shingles FROM pattern_shingles
          WHERE license = ANY(?::text[]) AND shingle = ANY(?::bigint[]) GROUP BY license, pattern_id
          ORDER BY pattern_id', \@won, \@working
      )->hashes->each
      )
    {
      # Store each pattern's shingles as a once-sorted list: the closest-pattern sum below is floating point
      # (so it needs a fixed order for reproducibility) and is evaluated for every snippet that this license
      # wins, so sorting here avoids re-sorting the same list per snippet.
      push @{$patterns{$r->{license}}}, [$r->{pattern_id}, [sort { $a <=> $b } @{$r->{shingles}}]];
    }
  }

  # Second pass: attribute each snippet to the closest pattern *within* its winning license (most
  # IDF-weighted shingle hits, lowest id on a tie) so the stored like_pattern carries the right risk/spdx.
  my %scores;
  for my $row (@$rows) {
    my $won = $best{$row->{id}};
    unless (defined $won->{license}) { $scores{$row->{id}} = _empty_score(); next }

    my %snippet = map { $_ => 1 } @{$ids{$row->{id}}};
    my ($like, $like_score);
    for my $pattern (@{$patterns{$won->{license}} // []}) {
      my ($pid, $shingles) = @$pattern;
      my $score = 0;
      $score += ($idf{$_} // 1) for grep { $snippet{$_} } @$shingles;
      ($like, $like_score) = ($pid, $score) if !defined $like_score || $score > $like_score;
    }

    $scores{$row->{id}} = {
      likelyness    => $won->{match},
      like_pattern  => $like,
      second_match  => $won->{second},
      score_version => SNIPPET_SCORE_VERSION
    };
  }

  return \%scores;
}

sub _empty_score () {
  return {likelyness => 0, like_pattern => undef, second_match => 0, score_version => SNIPPET_SCORE_VERSION};
}

# Bootstrapping fallback for the classify task: before the shingle tables are populated, score a snippet
# with the engine's plain bag of patterns. Stamped version 0 so the later fold-in step never trusts it.
sub bag_score ($self, $bag, $text) {
  my $hits = $bag->best_for($text, 1);
  my $best = @$hits ? $hits->[0] : {match => 0, pattern => undef};
  return {likelyness => $best->{match}, like_pattern => $best->{pattern}, second_match => 0, score_version => 0};
}

# Score the snippets of one package that lack a current-version score. Called from analyze before the
# fold/clear/overlap resolution so scores are always present and current when a report is built - never
# dependent on a separate job's timing. Snippets persist across reindex (keyed by content hash), so scoping
# by score_version also self-heals rows stuck at version 0 (e.g. classified before the tables were
# populated). A no-op when nothing is stale (the common reindex case) or when the tables are empty
# (bootstrapping; left to classify / "snippets --rescore").
sub score_package_snippets ($self, $package_id, $generation = 0) {
  my $db = $self->pg->db;

  # Order by id so every concurrent analyze job locks shared snippet rows in the same order, keeping the
  # write transaction below from deadlocking against another job scoring an overlapping snippet set.
  my $rows = $db->query(
    'SELECT DISTINCT s.id, s.text FROM snippets s JOIN file_snippets fs ON fs.snippet = s.id
      WHERE fs.package = ? AND fs.generation = ? AND s.score_version IS DISTINCT FROM ? ORDER BY s.id', $package_id,
    $generation, SNIPPET_SCORE_VERSION
  )->hashes->to_array;
  return unless @$rows;

  # Score outside any transaction (these are reads), so we never hold locks on the shared cross-package
  # snippets table during scoring. undef means the tables are not built yet - leave the rows for later.
  return unless my $scores = $self->score_snippets($rows);

  # Then flush every row in one short transaction with plain SQL: the columns are fixed, so
  # SQL::Abstract's per-row query building is pure overhead here.
  my $tx = $db->begin;
  for my $row (@$rows) {
    my $s = $scores->{$row->{id}};
    $db->query('UPDATE snippets SET likelyness = ?, like_pattern = ?, second_match = ?, score_version = ? WHERE id = ?',
      $s->{likelyness}, $s->{like_pattern}, $s->{second_match}, $s->{score_version}, $row->{id});
  }
  $tx->commit;
}

# spdx is shared by every pattern of a license, not a per-pattern form field: inherit it from an existing
# sibling pattern of the same license (a brand-new license has none, and gets an empty identifier). On
# updates pass the pattern's own id as $exclude_id so it never inherits a stale value from itself.
# catch_all is not inherited, it follows from the license name, which is what keeps the two in step.
sub _license_properties ($self, $db, $license, $exclude_id = undef) {
  my %props = (spdx => '', catch_all => license_is_catch_all($license) ? 1 : 0);
  return \%props unless defined $license && length $license;

  my $sql  = 'SELECT spdx FROM license_patterns WHERE license = ?';
  my @bind = ($license);
  if (defined $exclude_id) {
    $sql .= ' AND id <> ?';
    push @bind, $exclude_id;
  }
  $sql .= ' LIMIT 1';

  if (my $sibling = $db->query($sql, @bind)->hash) { $props{spdx} = $sibling->{spdx} }
  return \%props;
}

# At most one row per license can satisfy this, so the caller never has to choose. The catch_all condition is
# not redundant: "backfill-catch-all" re-derives that column from the name, long after a text was curated.
sub full_license_texts ($self, $licenses) {
  return {} unless @$licenses;
  my $rows
    = $self->pg->db->query(
    'SELECT license, pattern FROM license_patterns WHERE license = ANY(?) AND full_license_text AND NOT catch_all',
    $licenses);
  return {map { $_->{license} => $_->{pattern} } $rows->hashes->each};
}

# The text is printed verbatim, so a wildcard would ship as part of the license, and a catch-all has no
# license to print
sub full_license_text_error ($self, %args) {
  return undef unless $args{full_license_text};
  return 'A catch-all license has no text to reproduce'      if $args{catch_all};
  return 'A full license text cannot contain a $SKIP marker' if pattern_contains_skip($args{pattern} // '');
  return undef;
}

# Exclusive per license, so the previous answer has to go. Before the write, or the unique index rejects it.
sub _release_full_license_text ($db, $license, $except = undef) {
  my $where = {license => $license, full_license_text => 1};
  $where->{id} = {'!=' => $except} if defined $except;
  $db->update('license_patterns', {full_license_text => 0}, $where);
}

sub create ($self, %args) {
  my $checksum = pattern_checksum($args{pattern});
  my $id       = $self->pattern_exists($checksum);
  return {conflict => $id} if $id;

  my $db    = $self->pg->db;
  my $props = $self->_license_properties($db, $args{license});
  if (my $error = $self->full_license_text_error(%args, catch_all => $props->{catch_all})) {
    return {error => $error};
  }

  my $tx = $db->begin;
  _release_full_license_text($db, $args{license} // '') if $args{full_license_text};

  my $mid = $db->insert(
    'license_patterns',
    {
      pattern      => $args{pattern},
      token_hexsum => $checksum,
      packname     => $args{packname} // '',
      catch_all    => $props->{catch_all},
      (map { $_ => $args{$_} // 0 } @PATTERN_FLAGS),
      license => $args{license} // '',
      spdx    => $props->{spdx},
      risk    => $args{risk} // 5,
      ($args{unique_id}   ? (unique_id   => $args{unique_id})   : ()), ($args{owner} ? (owner => $args{owner}) : ()),
      ($args{contributor} ? (contributor => $args{contributor}) : ())
    },
    {returning => 'id'}
  )->hash->{id};

  $self->sync_pattern_shingles($db, $mid, $args{license} // '', $args{pattern});
  $tx->commit;
  $self->expire_cache;

  return $self->find($mid);
}

# Low-level bulk write behind imports and backfills: insert one fully-specified pattern row (deduped on the
# token_hexsum unique index) and maintain its shingles. Fills in token_hexsum from the pattern text when
# absent. Returns the new id, or undef when a pattern with the same checksum already exists. Unlike create()
# it takes the row verbatim (no property inheritance) and does NOT expire caches - the caller expires once
# when the whole batch is done. catch_all is the one field it will not take on trust: an imported file that
# claims something other than what the license name says would put drift back into the column.
sub insert_pattern ($self, $row) {
  my $db = $self->pg->db;
  $row->{catch_all} = license_is_catch_all($row->{license}) ? 1 : 0;
  $row->{token_hexsum} //= pattern_checksum($row->{pattern});

  # After the insert, not before: this ignores every conflict, so a row that turns out to be a duplicate must
  # not have released the claim already here - and a colliding claim must not take the whole pattern with it.
  my $claim = delete $row->{full_license_text};

  my $tx = $db->begin;
  return undef unless my $new = $db->insert('license_patterns', $row, {on_conflict => undef, returning => 'id'})->hash;
  if ($claim) {
    _release_full_license_text($db, $row->{license} // '', $new->{id});
    $db->update('license_patterns', {full_license_text => 1}, {id => $new->{id}});
  }
  $self->sync_pattern_shingles($db, $new->{id}, $row->{license} // '', $row->{pattern});
  $tx->commit;

  return $new->{id};
}

# Create the highest-value pattern - "SPDX-License-Identifier: <expr>" - for every license that carries an
# SPDX expression but is still missing it. The identifier comes verbatim from the license's curated "spdx"
# field (which may be hand-set, not just derived from the name); every other property is inherited from a
# representative pattern of the license (lowest id carrying an spdx). Returns the created rows; idempotent, as
# insert_pattern dedupes on the token_hexsum unique index.
sub backfill_spdx_identifiers ($self) {
  my @created;
  for my $row (
    $self->pg->db->query(
      "SELECT DISTINCT ON (license) license, spdx, packname, patent, trademark, export_restricted, cla, eula,
         catch_all, risk
       FROM license_patterns WHERE license != '' AND spdx != '' ORDER BY license, id"
    )->hashes->each
    )
  {
    $row->{pattern} = "SPDX-License-Identifier: $row->{spdx}";
    push @created, $row if $self->insert_pattern($row);
  }

  # Only churn the matcher/bag when something actually changed - a no-op re-run must not enqueue a rebuild.
  $self->expire_cache if @created;
  return \@created;
}

sub expire_cache ($self) {

  # Drop every engine's matcher and bag caches, so stale caches are never used until they are rebuilt -
  # and so invalidation stays correct no matter which engine is active, and after switching engines. The
  # similarity tables are maintained incrementally in the pattern write path (sync_pattern_shingles), so
  # nothing to invalidate there.
  unlink $_->to_string for $self->_all_cache_files;

  # Rebuild the tf-idf bag
  $self->minion->enqueue(pattern_stats => [] => {priority => PRIORITY_WAITING});
}

# Only ever used as a yes/no, so it stops at the first pattern it finds instead of counting them all -
# the report page asks this on every metadata refresh
sub has_new_patterns ($self, $packname, $when) {
  return !!$self->pg->db->query(
    "select 1 from license_patterns
     where created > ? and (packname = '' or packname = ?) limit 1", $when, $packname
  )->rows;
}

sub is_proposal_owner ($self, $checksum, $login) {
  return !!$self->pg->db->query(
    'SELECT pc.id FROM proposed_changes pc JOIN bot_users bu ON (bu.id = pc.owner) WHERE token_hexsum = ? AND login = ?',
    $checksum, $login
  )->hash;
}

sub load_specific ($self, $matcher, $pname) {
  my $rows = $self->pg->db->select('license_patterns', ['id', 'pattern'], {packname => $pname});

  while (my $l = $rows->array) {
    my ($id, $pattern) = @$l;
    $pattern = Cavil::PatternEngine::parse_tokens($pattern);
    $matcher->add_pattern($id, $pattern);
  }
}

# possibly cached
sub load_unspecific ($self, $matcher) {
  my $cachefile = $self->matcher_cache_file;
  my $path      = $cachefile->to_string;
  if (-f $path) {
    $matcher->load($path);
    return;
  }

  $self->load_specific($matcher, '');

  my $tmp = $cachefile->sibling($cachefile->basename . ".tmp.$$")->to_string;
  $matcher->dump($tmp);
  rename $tmp, $path;
}

sub match_count ($self, $id) {
  return $self->pg->db->query(
    'SELECT COUNT(*) AS matches, COUNT(DISTINCT(package)) AS packages
       FROM pattern_matches WHERE pattern = ? AND generation = 0', $id
  )->hash;
}

sub capped_match_count ($self, $id) {
  my $match_limit   = LICENSE_DETAIL_MATCH_LIMIT;
  my $package_limit = LICENSE_DETAIL_PACKAGE_LIMIT;
  my $count         = $self->pg->db->query(
    'SELECT match_counts.matches, match_counts.matches_capped,
       package_counts.packages, package_counts.packages_capped
     FROM (SELECT 1) base
       LEFT JOIN LATERAL (
         SELECT LEAST(COUNT(*)::int, ?) AS matches, COUNT(*) > ? AS matches_capped
         FROM (SELECT 1 FROM pattern_matches pm WHERE pm.pattern = ? AND pm.generation = 0 LIMIT ?) limited_matches
       ) match_counts ON true
       LEFT JOIN LATERAL (
         SELECT LEAST(COUNT(*)::int, ?) AS packages, COUNT(*) > ? AS packages_capped
         FROM (SELECT DISTINCT pm.package FROM pattern_matches pm WHERE pm.pattern = ? AND pm.generation = 0 LIMIT ?)
           limited_packages
       ) package_counts ON true', $match_limit, $match_limit, $id, $match_limit + 1, $package_limit, $package_limit,
    $id, $package_limit + 1
  )->hash;

  return {
    matches         => 0 + ($count->{matches}  // 0),
    packages        => 0 + ($count->{packages} // 0),
    matches_capped  => $count->{matches_capped}  ? true : false,
    packages_capped => $count->{packages_capped} ? true : false
  };
}

# Corpus query over curated patterns - the precedent lookup ("what does Cavil already say about this text?")
# and the maintenance worklists. %opts:
#   filters: license, risk, flag (one of @PATTERN_FLAGS), catch_all, search (pattern substring), min_skip
#   contained_in: text - curated patterns that match inside it (full matcher, same engine as indexing), plus
#                 the similar_to neighbours so near-variants of the wording show up too
#   similar_to: text - nearest patterns by shingle containment, both ways (pattern_cov, text_cov)
#   report: 'inconsistent_risk' - licenses whose patterns disagree on risk
#   limit, offset
# Text queries also return a verdict: consensus (one license/risk), conflict, or none. Patterns matching inside
# the text outrank merely similar ones.
sub search ($self, %opts) {
  my $limit  = $opts{limit}  // 20;
  my $offset = $opts{offset} // 0;
  return $self->_inconsistent_risk($opts{license}, $limit, $offset) if ($opts{report} // '') eq 'inconsistent_risk';

  my (@where, @bind, %extra);
  my $hits;
  if (defined(my $text = $opts{contained_in})) {
    $hits = $self->_contained_in($text);
    my $similar = $self->_similar_to($text, keys %$hits);
    $hits->{$_} = {%{$similar->{$_}}, %{$hits->{$_} // {}}} for keys %$similar;
  }
  elsif (defined $opts{similar_to}) { $hits = $self->_similar_to($opts{similar_to}) }
  if    ($hits) {
    return {rows => [], verdict => _verdict([]), total => 0} unless %$hits;
    push @where, 'id = ANY(?)';
    push @bind,  [keys %$hits];
    %extra = %$hits;
  }

  push @where, "license <> ''";
  if (defined $opts{exclude_id}) { push @where, 'id <> ?';     push @bind, $opts{exclude_id} }
  if (defined $opts{license})    { push @where, 'license = ?'; push @bind, $opts{license} }
  if (defined $opts{risk})       { push @where, 'risk = ?';    push @bind, $opts{risk} }
  if (defined(my $flag = $opts{flag})) {
    die "Unknown flag: $flag\n" unless grep { $_ eq $flag } @PATTERN_FLAGS;
    push @where, $flag;
  }
  push @where, ($opts{catch_all} ? '' : 'NOT ') . 'catch_all' if defined $opts{catch_all};
  if (defined $opts{search} && length $opts{search}) {
    push @where, 'pattern ILIKE ?';
    push @bind,  '%' . ($opts{search} =~ s/([%_\\])/\\$1/gr) . '%';
  }
  if (defined $opts{min_skip}) {
    push @where, q{(SELECT MAX(m[1]::int) FROM regexp_matches(pattern, '\$SKIP(\d+)', 'g') m) >= ?};
    push @bind,  $opts{min_skip};
  }

  my $rows = $self->pg->db->query(
        'SELECT id, license, risk, pattern, catch_all, '
      . join(', ', @PATTERN_FLAGS)
      . ', COUNT(*) OVER() AS total
     FROM license_patterns WHERE ' . join(' AND ', @where) . ' ORDER BY id', @bind
  )->hashes;

  my $total = @$rows ? $rows->[0]{total} : 0;
  for my $row (@$rows) {
    delete $row->{total};
    my $pattern = delete $row->{pattern};
    $row->{length}   = length $pattern;
    $row->{max_skip} = max(0, map { 0 + $_ } $pattern =~ /\$SKIP(\d+)/g);
    $row->{flags}    = [grep { delete $row->{$_} } @LICENSE_FLAGS];
    $row->{$_}       = $row->{$_} ? true : false for qw(catch_all full_license_text);
    $row->{excerpt}  = substr($pattern =~ s/\s+/ /gr, 0, 160);
    %$row            = (%$row, %{$extra{$row->{id}}}) if $extra{$row->{id}};
  }

  # Strongest evidence first: contained, then by how much of each other the pattern and the text share
  my @sorted = sort {
         ($b->{contained} // 0)   <=> ($a->{contained} // 0)
      || ($b->{pattern_cov} // 0) <=> ($a->{pattern_cov} // 0)
      || $a->{id}                 <=> $b->{id}
  } @$rows;
  my @page = grep {defined} @sorted[$offset .. min($offset + $limit, scalar @sorted) - 1];
  $_->{matches} = $self->capped_match_count($_->{id}) for @page;

  return {rows => \@page, total => 0 + $total, (%extra ? (verdict => _verdict(\@sorted)) : ())};
}

# Consensus is decided by the patterns that match inside the text and cover at least half of it (a short
# pattern inside a longer text says nothing about the rest); near-misses only count when nothing matches. Short
# contained patterns alone make the verdict "partial": curated wording covers part of the text, never "none".
# Dissent lists close variants of the wording (half the pattern or more, a fifth of the text) classified differently from every
# strong match - the "precedent itself conflicts" case a reviewer needs to hear about.
sub _verdict ($rows) {
  my @strong = grep { $_->{contained} && ($_->{text_cov} // 0) >= 0.5 } @$rows;
  @strong = grep { ($_->{pattern_cov} // 0) >= 0.8 && ($_->{text_cov} // 0) >= 0.8 } @$rows unless @strong;
  my $partial = !@strong && (@strong = grep { $_->{contained} } @$rows);
  return {status => 'none', basis => undef, classes => [], dissent => []} unless @strong;

  my %classes;
  push @{$classes{"$_->{license}\0$_->{risk}"}}, $_->{id} for @strong;
  my @classes = map { my ($l, $r) = split /\0/; {license => $l, risk => 0 + $r, ids => $classes{$_}} }
    sort { @{$classes{$b}} <=> @{$classes{$a}} || $a cmp $b } keys %classes;
  my @dissent
    = map { {id => $_->{id}, license => $_->{license}, risk => 0 + $_->{risk}} }
    grep  { !$classes{"$_->{license}\0$_->{risk}"} && ($_->{pattern_cov} // 0) >= 0.5 && ($_->{text_cov} // 0) >= 0.2 }
    @$rows;
  return {
    status  => $partial ? 'partial' : @classes == 1 ? 'consensus' : 'conflict',
    basis   => $strong[0]{contained} ? 'contained' : 'similar',
    classes => \@classes,
    dissent => $partial ? [] : \@dissent
  };
}

sub _contained_in ($self, $text) {
  my $matcher = Cavil::PatternEngine::init_matcher();
  $self->load_unspecific($matcher);
  my $file = tempfile->spew("ABC\n$text\nABC\n", 'UTF-8');

  # Line 1 is the padding line, so shift spans back to the text's own numbering
  my %hits;
  for my $m (@{$matcher->find_matches($file)}) {
    my ($id, $sline, $eline) = @$m;
    $hits{$id} //= {contained => true, lines => ($sline - 1) . '-' . ($eline - 1)};
  }
  return \%hits;
}

# Candidates come from two sources, because neither sees everything: the shingle index (normalization drops
# copyright lines, so one-line notices mentioning copyright have no shingles) and the tf-idf bag. Coverage is
# then measured on raw token shingles in both directions, so the agent sees near-variants as well as supersets.
sub _similar_to ($self, $text, @always) {
  my @ids = keys %{text_shingle_ids($text, SIMILARITY_SHINGLE_SIZE)};
  my $db  = $self->pg->db;
  my %candidates;
  if (@ids) {
    my $licenses = $db->query(
      'SELECT license FROM shingle_license WHERE shingle = ANY(?::bigint[])
       GROUP BY license ORDER BY COUNT(*) DESC, license LIMIT 20', \@ids
    )->arrays->map(sub { $_->[0] })->to_array;
    $candidates{$_->[0]} = 1
      for $db->query(
      'SELECT pattern_id FROM pattern_shingles WHERE license = ANY(?::text[]) AND shingle = ANY(?::bigint[])
       GROUP BY pattern_id ORDER BY COUNT(*) DESC, pattern_id LIMIT 50', $licenses, \@ids
      )->arrays->each;
  }
  $candidates{$_->{pattern}} = 1 for @{$self->closest_matches($text, 20)};
  $candidates{$_} = 2 for @always;
  return {} unless %candidates;

  my $mine = _raw_shingles($text);
  return {} unless %$mine;
  my %hits;
  for
    my $row ($db->query('SELECT id, pattern FROM license_patterns WHERE id = ANY(?)', [keys %candidates])->hashes->each)
  {
    my $theirs = _raw_shingles($row->{pattern});
    next unless my $size = keys %$theirs;
    my $shared = grep { $mine->{$_} } keys %$theirs;
    my ($pattern_cov, $text_cov) = ($shared / $size, $shared / keys(%$mine));

    next if $pattern_cov < 0.3 && $text_cov < 0.3 && $candidates{$row->{id}} != 2;
    $hits{$row->{id}}
      = {pattern_cov => int($pattern_cov * 100 + 0.5) / 100, text_cov => int($text_cov * 100 + 0.5) / 100};
  }
  return \%hits;
}

# Token shingles without the scoring normalization; $SKIP tokens (encoded as their small width) are dropped
sub _raw_shingles ($text) {
  Cavil::PatternEngine::init_matcher();
  my @toks = grep { $_ >= 100 } @{Cavil::PatternEngine::parse_tokens($text)};
  my $k    = SIMILARITY_SHINGLE_SIZE;
  return {map { $_                                  => 1 } @toks} if @toks < $k;
  return {map { join(',', @toks[$_ .. $_ + $k - 1]) => 1 } 0 .. @toks - $k};
}

# Where a pattern matches in a text, and which words each $SKIPn swallowed there - what a reviewer needs to
# check a long pattern without reading it. Same token semantics as the matcher ($SKIPn = 1..n words), found
# by a depth-first walk that tries the shortest skips first. Returns undef when the pattern does not match.
sub align ($self, $pattern, $text) {
  Cavil::PatternEngine::init_matcher();
  my @p = @{Cavil::PatternEngine::parse_tokens($pattern)};
  my @t = @{Cavil::Matcher::normalize($text)};
  return undef unless @p && @t && $p[0] >= 100;

  # Walk returns the text position after the match plus the [position, words used, declared n] of each skip
  no warnings 'recursion';
  my %failed;
  my $walk;
  $walk = sub ($i, $j) {
    return [$j]  if $i == @p;
    return undef if $j >= @t || $failed{"$i,$j"};
    if ($p[$i] < 100) {
      for my $k (1 .. $p[$i]) {
        my $rest = $walk->($i + 1, $j + $k) or next;
        return [$rest->[0], [$j, $k, $p[$i]], @$rest[1 .. $#$rest]];
      }
    }
    elsif ($t[$j][2] eq $p[$i]) {
      my $rest = $walk->($i + 1, $j + 1);
      return $rest if $rest;
    }
    $failed{"$i,$j"} = 1;
    return undef;
  };

  my $found;
  for my $start (grep { $t[$_][2] eq $p[0] } 0 .. $#t) {
    next unless my $walked = $walk->(0, $start);
    my ($end, @skips) = @$walked;
    my @lines = split /\n/, $text, -1;
    my ($first, $last) = ($t[$start][0], $t[$end - 1][0]);
    $found = {
      lines => [$first, $last],
      text  => join("\n", @lines[$first - 1 .. $last - 1]),
      skips => [
        map {
          {skip => $_->[2], words => join(' ', map { $_->[1] } @t[$_->[0] .. $_->[0] + $_->[1] - 1])}
        } @skips
      ]
    };
    last;
  }
  undef $walk;
  return $found;
}

# Dry run of a pattern against the snippet corpus: how many snippets and packages it would match, samples, and
# what its $SKIPs swallow there. Candidates are prefiltered by full-text search on the pattern's longest
# literal words, then confirmed with the real matcher. Embargoed, obsolete and ephemeral packages never show.
sub test_pattern ($self, $pattern, %opts) {
  Cavil::PatternEngine::init_matcher();
  (my $literal = $pattern) =~ s/\$SKIP\d+/ /g;
  my %seen;
  my @words = grep { !$seen{$_}++ } map { $_->[1] } @{Cavil::Matcher::normalize($literal)};
  @words = sort { length $b <=> length $a || $a cmp $b } grep {/^\w{3,}$/} @words;
  splice @words, 4 if @words > 4;
  return {error => 'Pattern has no searchable words'} unless @words;

  # Production has millions of snippets and file_snippets rows, so every query is capped and the whole dry
  # run shares one statement timeout; a timeout is reported, never retried
  my $db = $self->pg->db;
  my $tx = $db->begin;
  $db->query("SET LOCAL statement_timeout = '@{[TEST_PATTERN_TIMEOUT]}s'");
  my $result = eval { $self->_test_pattern_queries($db, $pattern, \@words, $opts{package_id}) };
  return {error => 'Dry run timed out, narrow it with package_id or more distinctive wording', searched => \@words}
    if !$result && $@ =~ /statement timeout/;
  die $@ unless $result;
  return $result;
}

sub _test_pattern_queries ($self, $db, $pattern, $words, $package_id) {
  my $cap  = TEST_PATTERN_CANDIDATES;
  my @pkg  = defined $package_id ? ($package_id)        : ();
  my $pkg  = @pkg                ? 'AND fs.package = ?' : '';
  my $live = 'fs.generation = 0 AND NOT p.embargoed AND NOT p.obsolete AND NOT p.ephemeral';

  # No ORDER BY: with one the planner may walk the primary key and compute to_tsvector for every snippet
  # instead of using snippets_text_fts_idx
  my $candidates = $db->query(
    "SELECT s.id, s.text FROM snippets s
     WHERE to_tsvector('english', s.text) @@ websearch_to_tsquery('english', ?)
       AND EXISTS (SELECT 1 FROM file_snippets fs JOIN bot_packages p ON p.id = fs.package
                   WHERE fs.snippet = s.id AND $live $pkg)
     LIMIT ?", join(' ', @$words), @pkg, $cap + 1
  )->hashes;
  my $capped = @$candidates > $cap;
  pop @$candidates if $capped;

  my $matcher = Cavil::PatternEngine::init_matcher();
  $matcher->add_pattern(1, Cavil::PatternEngine::parse_tokens($pattern));
  my @matched;
  for my $snippet (@$candidates) {
    my $file = tempfile->spew("ABC\n$snippet->{text}\nABC\n", 'UTF-8');
    push @matched, $snippet if @{$matcher->find_matches($file)};
  }

  my $stats   = {snippets => 0, occurrences => 0, packages => 0, unresolved => 0};
  my $samples = [];
  if (my @ids = map { $_->{id} } @matched) {

    # A single snippet (an SPDX line) can occur millions of times, so counts stop at a limit, like
    # capped_match_count
    my ($occ_limit, $pkg_limit) = (LICENSE_DETAIL_MATCH_LIMIT, LICENSE_DETAIL_PACKAGE_LIMIT);
    my $counts = $db->query(
      "SELECT o.occurrences, o.unresolved, pk.packages
       FROM (SELECT COUNT(*)::int AS occurrences, COUNT(*) FILTER (WHERE resolution IS NULL)::int AS unresolved
             FROM (SELECT fs.resolution FROM file_snippets fs JOIN bot_packages p ON p.id = fs.package
                   WHERE fs.snippet = ANY(?) AND $live $pkg LIMIT ?) l) o,
            (SELECT COUNT(*)::int AS packages
             FROM (SELECT DISTINCT fs.package FROM file_snippets fs JOIN bot_packages p ON p.id = fs.package
                   WHERE fs.snippet = ANY(?) AND $live $pkg LIMIT ?) l) pk", \@ids, @pkg, $occ_limit + 1, \@ids, @pkg,
      $pkg_limit + 1
    )->hash;
    $capped ||= $counts->{occurrences} > $occ_limit || $counts->{packages} > $pkg_limit;
    $stats = {
      snippets    => scalar @ids,
      occurrences => min($counts->{occurrences}, $occ_limit),
      packages    => min($counts->{packages},    $pkg_limit),
      unresolved  => min($counts->{unresolved},  $occ_limit)
    };

    # One occurrence for each of the first 5 matched snippets, never a sort over all occurrences
    my @first = @ids[0 .. min(4, $#ids)];
    $samples = $db->query(
      "SELECT o.* FROM unnest(?::int[]) AS sn(id), LATERAL (
         SELECT fs.snippet, fs.package, p.name, m.filename, fs.sline, fs.resolution, lp.license AS closest_license
         FROM file_snippets fs JOIN bot_packages p ON p.id = fs.package JOIN matched_files m ON m.id = fs.file
           JOIN snippets s ON s.id = fs.snippet LEFT JOIN license_patterns lp ON lp.id = s.like_pattern
         WHERE fs.snippet = sn.id AND $live $pkg LIMIT 1) o", \@first, @pkg
    )->hashes->to_array;
    my %text = map { $_->{id} => $_->{text} } @matched;
    $_->{skips} = ($self->align($pattern, $text{$_->{snippet}}) // {})->{skips} // [] for @$samples;
  }

  return {%$stats, capped => $capped ? true : false, searched => $words, samples => $samples};
}

sub _inconsistent_risk ($self, $license, $limit, $offset) {
  my $rows = $self->pg->db->query(
    q{SELECT license, jsonb_object_agg(risk, jsonb_build_object('patterns', n, 'ids', ids)) AS risks, SUM(n)::int AS patterns, COUNT(*) OVER() AS total
      FROM (SELECT license, risk, COUNT(*) AS n, (array_agg(id ORDER BY id))[1:5] AS ids
            FROM license_patterns WHERE license <> '' AND (?::text IS NULL OR license = ?) GROUP BY license, risk) r
      GROUP BY license HAVING COUNT(*) > 1 ORDER BY SUM(n) DESC, license LIMIT ? OFFSET ?}, $license, $license, $limit,
    $offset
  )->expand->hashes;
  my $total = @$rows ? $rows->[0]{total} : 0;
  delete $_->{total} for @$rows;
  return {report => 'inconsistent_risk', rows => $rows, total => 0 + $total};
}

sub remove_proposal ($self, $checksum) {
  my $sth = $self->pg->db->dbh->prepare('DELETE FROM proposed_changes WHERE token_hexsum = ?');
  my $rc  = $sth->execute($checksum);
  return $rc > 0;
}

sub all ($self) {
  return $self->pg->db->select('license_patterns', '*')->hashes;
}

sub find ($self, $id) {
  return $self->pg->db->select('license_patterns', '*', {id => $id})->hash;
}

sub checksum ($self, $pattern) {
  Cavil::PatternEngine::init_matcher();
  my $a   = Cavil::PatternEngine::parse_tokens($pattern);
  my $ctx = Cavil::PatternEngine::init_hash(0, 0);
  for my $n (@$a) {

    # map the skips to each other
    $n = 99 if $n < 99;
    my $s = pack('q', $n);
    $ctx->add($s);
  }

  return $ctx->hex;
}

sub for_license ($self, $license) {
  my $patterns = $self->pg->db->query(
    'SELECT lp.*, bu1.login AS owner_login, bu2.login AS contributor_login,
       NULL AS matches, NULL AS matches_capped,
       NULL AS packages, NULL AS packages_capped
     FROM license_patterns lp LEFT JOIN bot_users bu1 ON (bu1.id = lp.owner)
       LEFT JOIN bot_users bu2 ON (bu2.id = lp.contributor)
     WHERE license = ?
     ORDER BY lp.created', $license
  )->hashes->to_array;
  for my $pattern (@$patterns) {
    $pattern->{spdx_html} = spdx_link($pattern->{spdx});
  }
  return $patterns;
}

sub ignore_pattern_exists ($self, $name, $checksum) {
  my $hash = $self->pg->db->select('ignored_lines', 'id', {packname => $name, hash => $checksum})->hash;
  return $hash ? $hash->{id} : undef;
}

sub pattern_exists ($self, $checksum) {
  my $hash = $self->pg->db->select('license_patterns', 'id', {token_hexsum => $checksum})->hash;
  return $hash ? $hash->{id} : undef;
}

sub paginate_ignored_matches ($self, $options) {
  my $db = $self->pg->db;

  my $search = '';
  if (length($options->{search}) > 0) {
    my $quoted = $db->dbh->quote("\%$options->{search}\%");
    $search = "WHERE packname ILIKE $quoted";
  }

  my $results = $db->query(
    qq{
      SELECT il.id, il.hash, il.packname, EXTRACT(EPOCH FROM il.created) AS created_epoch, bu1.login AS owner_login,
        bu2.login AS contributor_login, COUNT(*) OVER() AS total
      FROM ignored_lines il LEFT JOIN bot_users bu1 ON (bu1.id = il.owner)
        LEFT JOIN bot_users bu2 ON (bu2.id = il.contributor)
      $search
      ORDER BY il.created DESC
      LIMIT ? OFFSET ?
    }, $options->{limit}, $options->{offset}
  )->hashes->to_array;

  for my $result (@$results) {
    $result->{snippet} = $db->query('SELECT id FROM snippets WHERE hash = ?', $result->{hash})->hash;
    my $matches = $db->query(
      'SELECT COUNT(*) AS matches, COUNT(DISTINCT(package)) AS packages
       FROM pattern_matches WHERE ignored_line = ? AND generation = 0', $result->{id}
    )->hash;
    $result->{matches}  = $matches->{matches};
    $result->{packages} = $matches->{packages};
  }

  return paginate($results, $options);
}

sub paginate_known_licenses ($self, $options) {
  my $db = $self->pg->db;

  my @bind;
  my $search     = $options->{search} // '';
  my $normalized = normalize_license_expr($search);
  my $order      = 'license';
  my $where      = '';
  push @bind, $search, $search, $normalized;
  if (length $search) {
    $where = qq{
        WHERE license != ''
          AND (license ILIKE ? OR similarity(LOWER(license), LOWER(?)) >= ?)
    };
    $order = 'exact DESC, score DESC, license ASC';
    push @bind, "%$search%", $search, LICENSE_PREDICTION_THRESHOLD;
  }

  my $results = $db->query(
    qq{
      SELECT license, spdx, risks, COUNT(*) OVER() AS total
      FROM (
        SELECT license, spdx, ARRAY_AGG(DISTINCT(risk)) AS risks,
          similarity(LOWER(license), LOWER(?)) AS score,
          CASE WHEN LOWER(license) IN (LOWER(?), ?) THEN 1 ELSE 0 END AS exact
        FROM (
          SELECT DISTINCT(license), spdx, risk FROM license_patterns
          $where
        ) AS licenses
        GROUP BY license, spdx
      ) AS licenses
      ORDER BY $order
      LIMIT ? OFFSET ?
    }, @bind, $options->{limit}, $options->{offset}
  )->hashes->to_array;

  # Reviewers research licenses here, so every readable text needs a way in, identifier or not
  my $curated = $self->full_license_texts([map { $_->{license} } @$results]);
  for my $row (@$results) {
    $row->{text_html}
      = length $row->{spdx}         ? spdx_link($row->{spdx})
      : $curated->{$row->{license}} ? license_link($row->{license}, 1, 'Curated text')
      :                               '';
  }

  return paginate($results, $options);
}

sub proposal_exists ($self, $checksum) {
  my $hash = $self->pg->db->select('proposed_changes', 'id', {token_hexsum => $checksum})->hash;
  return $hash ? $hash->{id} : undef;
}

sub proposal_stats($self) {
  return $self->pg->db->query(
    "SELECT
       (SELECT COUNT(*) FROM proposed_changes
          WHERE action = 'create_pattern' OR action = 'create_ignore' OR action = 'create_glob') AS proposals,

       -- One per card shown on the Missing Licenses page: every new_license, plus each missing_license
       -- report NOT already covered by a new_license for the same snippet (same dedup as proposed_changes).
       -- Counting both would double a snippet that has a kept report and its proposal.
       (SELECT COUNT(*) FROM proposed_changes pc
          WHERE pc.action = 'new_license'
             OR (pc.action = 'missing_license'
                 AND NOT EXISTS (SELECT 1 FROM proposed_changes np WHERE np.action = 'new_license'
                                   AND (np.data->>'snippet')::bigint = (pc.data->>'snippet')::bigint))) AS missing"
  )->hash;
}

# Shared conflict guards for every pattern-shaped proposal: a live pattern with the same text already
# exists, or a pending proposal does. Returns the matching error hash, or undef when the checksum is free.
sub _pattern_proposal_conflict ($self, $checksum) {
  my $id = $self->pattern_exists($checksum);
  return {conflict => $id} if $id;
  my $proposal_id = $self->proposal_exists($checksum);
  return {proposal_conflict => $proposal_id} if $proposal_id;
  return undef;
}

# Insert a create_pattern / new_license proposal row on the given db handle. Both actions carry the same
# payload; only the action string and the caller's surrounding logic (license gate / report retirement)
# differ, so the data shape lives here in one place.
sub _insert_pattern_proposal ($self, $db, $action, $checksum, %args) {
  $db->insert(
    'proposed_changes',
    {
      action => $action,
      data   => {
        -json => {
          snippet              => $args{snippet},
          pattern              => $args{pattern},
          highlighted_keywords => $args{highlighted_keywords},
          highlighted_licenses => $args{highlighted_licenses},
          edited               => $args{edited} ? '1' : '0',
          license              => $args{license},
          risk                 => $args{risk},
          package              => $args{package},

          # Always strings, the proposals page and the create-pattern form expect '1'/'0'
          (map { $_ => $args{$_} ? '1' : '0' } @PATTERN_FLAGS),
          ai_assisted => $args{ai_assisted} // 0,
          reason      => $args{reason}      // '',

          # Server-computed facts for the reviewer (precedent, impact, $SKIP alignment) and the grouping key
          # for proposals about one legal text
          (map { defined $args{$_} ? ($_ => $args{$_}) : () } qw(evidence family))
        }
      },
      owner        => $args{owner},
      token_hexsum => $checksum
    }
  );
}

sub propose_create ($self, %args) {
  my $checksum = pattern_checksum($args{pattern});
  if (my $conflict = $self->_pattern_proposal_conflict($checksum)) { return $conflict }
  if (my $error    = $self->full_license_text_error(%args))        { return {error => $error} }

  my $db = $self->pg->db;
  my $hash
    = $db->query('SELECT id FROM license_patterns WHERE license = ? AND risk = ? LIMIT 1', $args{license}, $args{risk})
    ->hash;
  return {license_conflict => 1} unless $hash;

  $self->_insert_pattern_proposal($db, 'create_pattern', $checksum, %args);
  return {};
}

sub propose_new_license ($self, %args) {
  my $checksum = pattern_checksum($args{pattern});
  if (my $conflict = $self->_pattern_proposal_conflict($checksum)) { return $conflict }
  if (my $error    = $self->full_license_text_error(%args))        { return {error => $error} }

  # Unlike propose_create there is deliberately no existing-license gate: introducing a license Cavil has
  # never seen is the whole point. The curator's approval (the create-pattern action) bootstraps the
  # license via Patterns::create, which needs no sibling row. Routed to the lawyers' Missing Licenses page.
  #
  # The originating missing-license report is deliberately LEFT in place as the durable record. While this
  # proposal exists it is hidden from the page (see proposed_changes), and it is retired only when the
  # proposal is approved (Snippet::_apply_action create-pattern -> retire_missing_license). That way
  # dismissing a bad proposal falls back to the report instead of throwing it away.
  $self->_insert_pattern_proposal($self->pg->db, 'new_license', $checksum, %args);
  return {};
}

# Drop the missing-license report(s) for a snippet - called when a pattern is created for it (the report's
# question is answered) so it does not re-surface on the Missing Licenses page.
sub retire_missing_license ($self, $snippet_id) {
  $self->pg->db->query(
    "DELETE FROM proposed_changes WHERE action = 'missing_license' AND (data->>'snippet')::bigint = ?", $snippet_id);
}

sub propose_ignore ($self, %args) {
  my $from     = $args{from};
  my $checksum = $args{hash};
  my $id       = $self->ignore_pattern_exists($from, $checksum);
  return {conflict => $id} if $id;

  my $proposal_id = $self->proposal_exists($checksum);
  return {proposal_conflict => $proposal_id} if $proposal_id;

  $self->pg->db->insert(
    'proposed_changes',
    {
      action => 'create_ignore',
      data   => {
        -json => {
          snippet              => $args{snippet},
          from                 => $from,
          pattern              => $args{pattern},
          highlighted_keywords => $args{highlighted_keywords},
          highlighted_licenses => $args{highlighted_licenses},
          edited               => $args{edited} // '0',
          package              => $args{package},
          ai_assisted          => $args{ai_assisted} // 0,
          reason               => $args{reason}      // ''
        }
      },
      owner        => $args{owner},
      token_hexsum => $checksum
    }
  );

  return {};
}

sub propose_glob ($self, %args) {
  my $glob = $args{glob};

  # A glob has no snippet to checksum, so the glob string itself is the dedupe key (the unique
  # index on proposed_changes.token_hexsum then prevents duplicate proposals for the same glob).
  my $checksum = md5_sum($glob);

  my $existing = $self->pg->db->select('ignored_files', 'id', {glob => $glob})->hash;
  return {conflict => $existing->{id}} if $existing;

  my $proposal_id = $self->proposal_exists($checksum);
  return {proposal_conflict => $proposal_id} if $proposal_id;

  $self->pg->db->insert(
    'proposed_changes',
    {
      action => 'create_glob',
      data   => {
        -json => {
          glob        => $glob,
          from        => $args{from},
          package     => $args{package},
          ai_assisted => $args{ai_assisted} // 0,
          reason      => $args{reason}      // ''
        }
      },
      owner        => $args{owner},
      token_hexsum => $checksum
    }
  );

  return {};
}

sub propose_missing ($self, %args) {
  my $from     = $args{from};
  my $checksum = $args{hash};
  my $id       = $self->pattern_exists($checksum);
  return {conflict => $id} if $id;

  my $proposal_id = $self->proposal_exists($checksum);
  return {proposal_conflict => $proposal_id} if $proposal_id;

  $self->pg->db->insert(
    'proposed_changes',
    {
      action => 'missing_license',
      data   => {
        -json => {
          snippet              => $args{snippet},
          from                 => $from,
          pattern              => $args{pattern},
          highlighted_keywords => $args{highlighted_keywords},
          highlighted_licenses => $args{highlighted_licenses},
          edited               => $args{edited} // '0',
          package              => $args{package},
          ai_assisted          => $args{ai_assisted} // 0,
          reason               => $args{reason}      // ''
        }
      },
      owner        => $args{owner},
      token_hexsum => $checksum
    }
  );

  return {};
}

sub proposed_changes ($self, $options) {
  my $db = $self->pg->db;

  my $before = '';
  if ($options->{before} > 0) {
    my $quoted = $db->dbh->quote($options->{before});
    $before = "AND pc.id < $quoted";
  }

  my $search = '';
  if (length($options->{search}) > 0) {
    my $quoted = $db->dbh->quote("\%$options->{search}\%");
    $search = "AND (bu.login ILIKE $quoted OR pc.data::text ILIKE $quoted)";
  }

  # A snippet's missing-license report and a new_license proposal for it coexist (the report is the durable
  # record; dismissing the proposal must fall back to it). Show only the proposal while it exists, so the
  # snippet is never listed twice: hide a missing_license row when a new_license proposal covers its snippet.
  my $superseded = "AND NOT (pc.action = 'missing_license' AND EXISTS (SELECT 1 FROM proposed_changes np"
    . " WHERE np.action = 'new_license' AND (np.data->>'snippet')::bigint = (pc.data->>'snippet')::bigint))";

  my $changes = $db->query(
    "SELECT pc.*, EXTRACT(EPOCH FROM created) AS created_epoch, bu.login, COUNT(*) OVER() AS total
     FROM proposed_changes pc JOIN bot_users bu ON (bu.id = pc.owner)
     WHERE action = ANY (?) $before $search $superseded ORDER BY pc.id DESC LIMIT 10", $options->{actions}
  )->expand->hashes;

  my $total = 0;
  for my $change (@$changes) {
    $self->_enrich_proposed_change($db, $change);
    $total = delete $change->{total};
  }

  return {total => $total, changes => $changes->to_array};
}

# Attach the display context a proposed_changes row needs: the closest existing pattern (for the
# Unidentified card's footer) and the originating package. Shared by the list feed and the single-row
# fallback lookup below.
sub _enrich_proposed_change ($self, $db, $change) {

  # closest_pattern reloads the pattern bag from disk per call; new_license rows carry a pattern but the
  # Missing Licenses page never shows a closest match for them, so skip that work.
  $change->{closest} = undef;
  if ( $change->{action} ne 'new_license'
    && defined $change->{data}{pattern}
    && (my $closest = $self->closest_pattern($change->{data}{pattern})))
  {
    $change->{closest} = {
      id           => $closest->{id},
      similarity   => $closest->{similarity},
      license_name => $closest->{license},
      risk         => $closest->{risk}
    };
  }

  $change->{package} = undef;
  if (my $id = $change->{data}{package}) {
    $change->{package} = $db->query('SELECT id, name FROM bot_packages WHERE id = ?', $id)->hash;
  }

  return $change;
}

sub proposal_by_checksum ($self, $checksum) {
  return $self->pg->db->select('proposed_changes', '*', {token_hexsum => $checksum})->expand->hash;
}

# The missing-license report still on file for a snippet, enriched like a proposed_changes row. Used to
# swap the fallback report back into the page when a covering new_license proposal is dismissed. Returns
# undef when no report exists (nothing to fall back to).
sub report_for_snippet ($self, $snippet_id) {
  my $db     = $self->pg->db;
  my $change = $db->query(
    "SELECT pc.*, EXTRACT(EPOCH FROM created) AS created_epoch, bu.login
     FROM proposed_changes pc JOIN bot_users bu ON (bu.id = pc.owner)
     WHERE pc.action = 'missing_license' AND (pc.data->>'snippet')::bigint = ?
     ORDER BY pc.id DESC LIMIT 1", $snippet_id
  )->expand->hash;
  return undef unless $change;
  return $self->_enrich_proposed_change($db, $change);
}

sub recent ($self, $options) {
  my $db = $self->pg->db;

  my $before = '';
  if ($options->{before} > 0) {
    my $quoted = $db->dbh->quote($options->{before});
    $before = "AND lp.id < $quoted";
  }

  my $contributor = '';
  if ($options->{has_contributor} ne 'false') {
    $contributor = 'AND lp.contributor IS NOT NULL';
  }

  my $timeframe = '';
  if ($options->{timeframe} ne 'any') {
    my $interval = "1 $options->{timeframe}";
    $timeframe = "AND lp.created > NOW() - INTERVAL '$interval'";
  }

  # Keyset pagination with no exact total: fetch one extra row to learn whether a next page exists,
  # instead of a COUNT(*) OVER() that scans the whole filtered set on every page.
  my $patterns = $db->query(
    "SELECT lp.*, bu1.login AS owner_login, bu2.login AS contributor_login,
       EXTRACT(EPOCH FROM created) AS created_epoch
     FROM license_patterns lp LEFT JOIN bot_users bu1 ON (bu1.id = lp.owner)
       LEFT JOIN bot_users bu2 ON (bu2.id = lp.contributor)
     WHERE lp.id > 0 $before $contributor $timeframe ORDER BY lp.id DESC LIMIT 11"
  )->hashes->to_array;

  my $has_more = @$patterns > 10 ? 1 : 0;
  splice @$patterns, 10 if $has_more;

  for my $pattern (@$patterns) {
    my $count = $self->match_count($pattern->{id});
    $pattern->{matches}  = $count->{matches};
    $pattern->{packages} = $count->{packages};
  }

  return {has_more => $has_more, patterns => $patterns};
}

sub remove ($self, $id) {
  my $db = $self->pg->db;

  # Capture the affected packages and delete the pattern in one transaction. The "ON DELETE
  # CASCADE" on pattern_matches removes the matches along with the pattern, so we have to
  # remember which packages need reindexing before that information is gone, and the
  # transaction keeps the captured list consistent with the cascade even while other packages
  # are being indexed concurrently. Every generation counts here, not just the live report: a package
  # whose in-flight build matched the pattern needs the reindex just as much.
  my $tx       = $db->begin;
  my $packages = [map { $_->{package} }
      $db->query('SELECT DISTINCT package FROM pattern_matches WHERE pattern = ?', $id)->hashes->each];
  $db->delete('license_patterns', {id => $id});
  $tx->commit;

  # Only expire the caches once the row is actually gone, otherwise a concurrent index job
  # could rebuild the matcher cache with the just-deleted pattern still in it (and then keep
  # producing matches for a pattern id that no longer exists).
  $self->expire_cache;

  return $packages;
}

sub update ($self, $id, %args) {
  my $db = $self->pg->db;

  my $checksum = pattern_checksum($args{pattern});
  my $conflict = $db->select('license_patterns', 'id', {token_hexsum => $checksum})->hash;
  if ($conflict && $conflict->{id} != $id) {
    return {conflict => $conflict->{id}};
  }

  # catch_all and spdx are per-license properties, not form fields, so a license rename has to carry them
  # along. catch_all is always re-derived from the (possibly edited) license. spdx has no derivation from a
  # name, so we only refresh it when the license actually changes: adopt the new license's identifier, or
  # clear it for a brand-new license. Leaving spdx untouched on a rename was the bug that kept the stale
  # identifier after a GPL-3.0-only -> GPL-3.0-or-later correction.
  my $new_license = $args{license} // '';
  my $old         = $db->select('license_patterns', ['license', 'spdx'], {id => $id})->hash;
  my $renamed     = !$old || $old->{license} ne $new_license;
  my $props       = $self->_license_properties($db, $new_license, $id);
  my $catch_all   = $props->{catch_all};
  my $spdx        = $renamed ? $props->{spdx} : $old->{spdx};

  if (my $error = $self->full_license_text_error(%args, catch_all => $catch_all)) { return {error => $error} }

  my $tx = $db->begin;
  _release_full_license_text($db, $new_license, $id) if $args{full_license_text};

  $db->update(
    'license_patterns',
    {
      pattern      => $args{pattern},
      token_hexsum => $checksum,
      packname     => $args{packname} // '',
      license      => $args{license},
      catch_all    => $catch_all,
      (map { $_ => $args{$_} // 0 } @PATTERN_FLAGS),
      spdx => $spdx,
      risk => $args{risk} // 5,
      ($args{owner} ? (owner => $args{owner}) : ())
    },
    {id => $id}
  );

  $self->sync_pattern_shingles($db, $id, $args{license}, $args{pattern});
  $tx->commit;
}

# Bulk-edit the shared name/risk/spdx of every pattern of one license at once, atomically. This is the
# whole-license counterpart of update(): the pattern text is untouched, so it never changes matcher/bag
# caches (they key on text -> id) and needs no expire_cache - only the denormalized name copies and the
# cached reports have to follow, which the shingle resync here and the caller's reindex handle.
#   %args: license (new name, required), risk (undef leaves each pattern's risk), spdx (canonical string,
#   '' clears). Empty old names are the keyword-pattern bucket and must never be bulk-edited (guarded in
#   the controller). Returns {updated => n, license => $new, spdx => $spdx}.
sub update_license_meta ($self, $old_license, %args) {
  my $new  = $args{license};
  my $risk = $args{risk};
  my $spdx = $args{spdx} // '';
  my $db   = $self->pg->db;

  my $ids = $db->query('SELECT id FROM license_patterns WHERE license = ?', $old_license)->arrays->flatten->to_array;
  return {updated => 0} unless @$ids;

  my $renamed   = $new ne $old_license;
  my $catch_all = license_is_catch_all($new) ? 1 : 0;

  my $tx = $db->begin;

  # full_license_text is unique per license name (partial unique index). A catch-all has no text to
  # reproduce, and merging into a destination that already carries a full-text pattern would collide, so
  # in either case the incoming rows give up the claim rather than fight the index.
  if ($catch_all) {
    $db->query('UPDATE license_patterns SET full_license_text = false WHERE id = ANY(?)', $ids);
  }
  elsif (
    $renamed
    && $db->query('SELECT 1 FROM license_patterns WHERE license = ? AND full_license_text AND id <> ALL(?) LIMIT 1',
      $new, $ids)->rows
    )
  {
    $db->query('UPDATE license_patterns SET full_license_text = false WHERE id = ANY(?)', $ids);
  }

  $db->query('UPDATE license_patterns SET license = ?, catch_all = ? WHERE id = ANY(?)', $new, $catch_all, $ids);
  $db->query('UPDATE license_patterns SET risk = ? WHERE id = ANY(?)', $risk, $ids) if defined $risk;

  # spdx and catch_all are per-license properties: normalize them across the whole destination so a merge
  # cannot leave the pre-existing rows with a different identifier than the ones just moved in.
  $db->query('UPDATE license_patterns SET spdx = ?, catch_all = ? WHERE license = ?', $spdx, $catch_all, $new);

  # The name is denormalized into pattern_shingles/shingle_license; resync the moved rows so snippet
  # scoring attributes to the new name (the DELETE+INSERT lets the shingle_license trigger follow).
  if ($renamed) {
    for my $row ($db->query('SELECT id, pattern FROM license_patterns WHERE id = ANY(?)', $ids)->hashes->each) {
      $self->sync_pattern_shingles($db, $row->{id}, $new, $row->{pattern});
    }
  }

  $tx->commit;

  return {updated => scalar @$ids, license => $new, spdx => $spdx};
}

1;
