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

package Cavil::Model::Patterns;
use Mojo::Base -base, -signatures;

use Cavil::Util
  qw(license_is_catch_all normalize_license_expr paginate pattern_checksum spdx_link text_shingle_ids SNIPPET_SCORE_VERSION);
use List::Util qw(min);
use Mojo::File qw(path);
use Mojo::JSON qw(true false);
use Mojo::Util qw(md5_sum);
use Cavil::PatternEngine;

# Candidate licenses pulled from a snippet's most distinctive shingles before precise re-scoring
use constant SIMILARITY_PROBE_SHINGLES => 20;

# Tokens per shingle for the snippet similarity scorer. Empirically (eval_fold on the full corpus)
# k=3 gives the best precision; larger k trades precision for recall.
use constant SIMILARITY_SHINGLE_SIZE => 3;

# Required-phrase gate: the winning license must share at least MIN_DISTINCTIVE shingles this
# distinctive (IDF, i.e. present in few licenses) with the snippet. The count requirement (>=2) kills
# the dominant real-world false fold: tiny generic header fragments ("Disclaimer", "Attribution")
# matching a pseudo-license on a single token. Calibrate with "cavil eval_fold" / staging snippets.
use constant SIMILARITY_DISTINCTIVE_IDF => 4.0;
use constant SIMILARITY_MIN_DISTINCTIVE => 2;

has [qw(cache log pg minion)];

# The compiled matcher and the tf-idf bag are cached under engine-specific filenames, because their
# on-disk formats differ between engines. This lets an instance switch engines (or run "matcher-diff")
# without ever reading a cache written by the other one. Snippet-similarity data lives in the database
# (pattern_shingles / shingle_license), not on disk, so it needs no cache file here.
sub matcher_cache_file ($self) {
  return path($self->cache, Cavil::PatternEngine::name() eq 'cavil' ? 'cavil.matcher' : 'cavil.tokens');
}

sub bag_cache_file ($self) {
  return path($self->cache, Cavil::PatternEngine::name() eq 'cavil' ? 'cavil.pattern.bag.cavil' : 'cavil.pattern.bag');
}

sub _all_cache_files ($self) {
  my $cache = path($self->cache);
  return map { $cache->child($_) } qw(cavil.tokens cavil.matcher cavil.pattern.bag cavil.pattern.bag.cavil);
}

use constant LICENSE_DETAIL_MATCH_LIMIT   => 10_000;
use constant LICENSE_DETAIL_PACKAGE_LIMIT => 1_000;
use constant LICENSE_PREDICTION_THRESHOLD => 0.3;
use constant LICENSE_PREDICTION_LIMIT     => 10;

sub autocomplete ($self) {
  my $licenses = {};

  my $patterns
    = $self->pg->db->query(
    'SELECT DISTINCT(license), risk, patent, trademark, export_restricted, cla, eula, catch_all FROM license_patterns')
    ->hashes;
  for my $pattern ($patterns->each) {
    $licenses->{$pattern->{license}} = {
      risk              => $pattern->{risk},
      patent            => $pattern->{patent},
      trademark         => $pattern->{trademark},
      export_restricted => $pattern->{export_restricted},
      cla               => $pattern->{cla},
      eula              => $pattern->{eula},
      catch_all         => $pattern->{catch_all}
    };
  }
  delete $licenses->{''};

  return $licenses;
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

# Incrementally maintain pattern_shingles for one pattern: replace its rows with the shingles of its
# current text, tagged with its current license. Called whenever a pattern's text or license is created,
# updated or imported; deletes are handled by the table's ON DELETE CASCADE. Runs on the caller's $db so
# it shares the pattern write's transaction. An empty-license pattern (the keyword-detection layer) is
# never a fold target, so it is not stored.
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

# --- Snippet similarity scoring ----------------------------------------------------------------------
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
# with the plain Spooky bag. Stamped version 0 so the later fold-in step never trusts it.
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
sub score_package_snippets ($self, $package_id) {
  my $db = $self->pg->db;

  # Order by id so every concurrent analyze job locks shared snippet rows in the same order, keeping the
  # write transaction below from deadlocking against another job scoring an overlapping snippet set.
  my $rows = $db->query(
    'SELECT DISTINCT s.id, s.text FROM snippets s JOIN file_snippets fs ON fs.snippet = s.id
      WHERE fs.package = ? AND s.score_version IS DISTINCT FROM ? ORDER BY s.id', $package_id, SNIPPET_SCORE_VERSION
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

sub create ($self, %args) {
  my $checksum = pattern_checksum($args{pattern});
  my $id       = $self->pattern_exists($checksum);
  return {conflict => $id} if $id;

  # Inherit per-license properties (spdx, catch_all) from already known licenses; for a brand-new
  # license derive catch_all from its name so the "covered" gate treats it consistently right away.
  my $db        = $self->pg->db;
  my $spdx      = '';
  my $catch_all = license_is_catch_all($args{license}) ? 1 : 0;
  if (my $license = $args{license}) {
    my $pattern = $db->query('SELECT spdx, catch_all FROM license_patterns WHERE license = ? LIMIT 1', $license)->hash;
    if ($pattern) {
      $spdx      = $pattern->{spdx};
      $catch_all = $pattern->{catch_all};
    }
  }

  my $mid = $db->insert(
    'license_patterns',
    {
      pattern           => $args{pattern},
      token_hexsum      => $checksum,
      packname          => $args{packname}          // '',
      patent            => $args{patent}            // 0,
      trademark         => $args{trademark}         // 0,
      export_restricted => $args{export_restricted} // 0,
      cla               => $args{cla}               // 0,
      eula              => $args{eula}              // 0,
      catch_all         => $catch_all,
      license           => $args{license} // '',
      spdx              => $spdx,
      risk              => $args{risk} // 5,
      ($args{unique_id}   ? (unique_id   => $args{unique_id})   : ()), ($args{owner} ? (owner => $args{owner}) : ()),
      ($args{contributor} ? (contributor => $args{contributor}) : ())
    },
    {returning => 'id'}
  )->hash->{id};

  $self->sync_pattern_shingles($db, $mid, $args{license} // '', $args{pattern});
  $self->expire_cache;

  return $self->find($mid);
}

sub expire_cache ($self) {

  # Drop every engine's matcher and bag caches, so stale caches are never used until they are rebuilt -
  # and so invalidation stays correct no matter which engine is active, and after switching engines. The
  # similarity tables are maintained incrementally in the pattern write path (sync_pattern_shingles), so
  # nothing to invalidate there.
  unlink $_->to_string for $self->_all_cache_files;

  # Rebuild the tf-idf bag
  $self->minion->enqueue(pattern_stats => [] => {priority => 9});
}

sub has_new_patterns ($self, $packname, $when) {
  return $self->pg->db->query(
    "select count(*) from license_patterns
     where created > ? and (packname = '' or packname = ?)", $when, $packname
  )->array->[0];
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
       FROM pattern_matches WHERE pattern = ?', $id
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
         FROM (SELECT 1 FROM pattern_matches pm WHERE pm.pattern = ? LIMIT ?) limited_matches
       ) match_counts ON true
       LEFT JOIN LATERAL (
         SELECT LEAST(COUNT(*)::int, ?) AS packages, COUNT(*) > ? AS packages_capped
         FROM (SELECT DISTINCT pm.package FROM pattern_matches pm WHERE pm.pattern = ? LIMIT ?) limited_packages
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
       FROM pattern_matches WHERE ignored_line = ?', $result->{id}
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
  $_->{spdx_html} = spdx_link($_->{spdx}) for @$results;

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
       (SELECT COUNT(*) FROM proposed_changes WHERE action = 'missing_license') AS missing"
  )->hash;
}

sub propose_create ($self, %args) {
  my $pattern  = $args{pattern};
  my $checksum = pattern_checksum($pattern);
  my $id       = $self->pattern_exists($checksum);
  return {conflict => $id} if $id;

  my $proposal_id = $self->proposal_exists($checksum);
  return {proposal_conflict => $proposal_id} if $proposal_id;

  my $db      = $self->pg->db;
  my $license = $args{license};
  my $risk    = $args{risk};
  my $hash
    = $db->query('SELECT id FROM license_patterns WHERE license = ? AND risk = ? LIMIT 1', $license, $risk)->hash;
  return {license_conflict => 1} unless $hash;

  $db->insert(
    'proposed_changes',
    {
      action => 'create_pattern',
      data   => {
        -json => {
          snippet              => $args{snippet},
          pattern              => $pattern,
          highlighted_keywords => $args{highlighted_keywords},
          highlighted_licenses => $args{highlighted_licenses},
          edited               => $args{edited} // '0',
          license              => $license,
          risk                 => $risk,
          package              => $args{package},
          patent               => $args{patent}            // '0',
          trademark            => $args{trademark}         // '0',
          export_restricted    => $args{export_restricted} // '0',
          cla                  => $args{cla}               // '0',
          eula                 => $args{eula}              // '0',
          ai_assisted          => $args{ai_assisted}       // 0,
          reason               => $args{reason}            // ''
        }
      },
      owner        => $args{owner},
      token_hexsum => $checksum
    }
  );

  return {};
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

  my $changes = $db->query(
    "SELECT pc.*, EXTRACT(EPOCH FROM created) AS created_epoch, bu.login, COUNT(*) OVER() AS total
     FROM proposed_changes pc JOIN bot_users bu ON (bu.id = pc.owner)
     WHERE action = ANY (?) $before $search ORDER BY pc.id DESC LIMIT 10", $options->{actions}
  )->expand->hashes;

  my $total = 0;
  for my $change (@$changes) {
    $change->{closest} = undef;
    if (defined $change->{data}{pattern} && (my $closest = $self->closest_pattern($change->{data}{pattern}))) {
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

    $total = delete $change->{total};
  }

  return {total => $total, changes => $changes->to_array};
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
  # are being indexed concurrently.
  my $tx       = $db->begin;
  my $packages = [map { $_->{package} }
      $db->query('SELECT DISTINCT package FROM pattern_matches WHERE pattern = ?', $id)->hashes->each];
  $db->delete('license_patterns', {id => $id});
  $tx->commit;

  # Only expire the caches once the row is actually gone, otherwise a concurrent index job
  # could rebuild cavil.tokens with the just-deleted pattern still in it (and then keep
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

  # catch_all is a per-license property, not a form field: derive it from the (possibly edited)
  # license so it stays consistent - inherit from a sibling pattern of that license, else from its name.
  my $catch_all = license_is_catch_all($args{license}) ? 1 : 0;
  if (my $license = $args{license}) {
    my $sibling
      = $db->query('SELECT catch_all FROM license_patterns WHERE license = ? AND id <> ? LIMIT 1', $license, $id)->hash;
    $catch_all = $sibling->{catch_all} if $sibling;
  }

  $db->update(
    'license_patterns',
    {
      pattern           => $args{pattern},
      token_hexsum      => $checksum,
      packname          => $args{packname} // '',
      license           => $args{license},
      patent            => $args{patent}            // 0,
      trademark         => $args{trademark}         // 0,
      export_restricted => $args{export_restricted} // 0,
      cla               => $args{cla}               // 0,
      eula              => $args{eula}              // 0,
      catch_all         => $catch_all,
      risk              => $args{risk} // 5,
      ($args{owner} ? (owner => $args{owner}) : ())
    },
    {id => $id}
  );

  $self->sync_pattern_shingles($db, $id, $args{license}, $args{pattern});
}

1;
