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
  qw(license_is_catch_all normalize_license_expr paginate pattern_checksum spdx_link text_shingles weighted_containment SNIPPET_SCORE_VERSION);
use List::Util qw(min);
use Mojo::File qw(path);
use Mojo::JSON qw(true false);
use Mojo::Util qw(md5_sum);
use Cavil::PatternEngine;
use Storable;

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
# without ever reading a cache written by the other one. The similarity sidecar
# (cavil.license.signatures) is pure-Perl and engine-independent, so it is shared.
sub matcher_cache_file ($self) {
  return path($self->cache, Cavil::PatternEngine::name() eq 'cavil' ? 'cavil.matcher' : 'cavil.tokens');
}

sub bag_cache_file ($self) {
  return path($self->cache, Cavil::PatternEngine::name() eq 'cavil' ? 'cavil.pattern.bag.cavil' : 'cavil.pattern.bag');
}

sub _all_cache_files ($self) {
  my $cache = path($self->cache);
  return
    map { $cache->child($_) }
    qw(cavil.tokens cavil.matcher cavil.pattern.bag cavil.pattern.bag.cavil cavil.license.signatures);
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

# Rebuild the per-license similarity signatures that back the improved snippet scoring. This is an
# extension of the Spooky bag (built alongside it in the pattern_stats task): for every license we
# union the normalized token-shingles of all its patterns, so a snippet is later compared against a
# license's *combined* signature instead of one arbitrary fragment. Stored as a rebuildable sidecar
# next to the bag - no database tables. Empty-license keyword patterns are skipped (they are the
# keyword-detection layer, not fold-in targets).
sub rebuild_similarity_data ($self, $k = SIMILARITY_SHINGLE_SIZE) {
  my $rows = $self->pg->db->select('license_patterns', 'id,license,pattern')->hashes;

  my (%signatures, %representative);
  for my $row (@$rows) {
    my $license = $row->{license};
    next unless defined $license && length $license;
    my $shingles = text_shingles($row->{pattern}, $k);
    $signatures{$license}{$_} = 1 for keys %$shingles;
    $representative{$license} //= $row->{id};
  }

  # Write atomically (temp + rename) so readers never see a half-written Storable file, mirroring
  # how the pattern bag is published.
  my $data  = {signatures => \%signatures, representative => \%representative, k => $k};
  my $cache = path($self->cache);
  my $temp  = $cache->child("cavil.license.signatures.new.$$");
  store($data, $temp->to_string);
  rename($temp->to_string, $cache->child('cavil.license.signatures')->to_string);
  return $data;
}

# Load the similarity signatures and derive the inverted index (shingle -> licenses) and IDF
# weights (rare shingles weigh more). Returns undef if the sidecar has not been built yet, so
# callers can fall back to the plain bag.
sub similarity_context ($self) {
  my $file = path($self->cache, 'cavil.license.signatures');
  return undef unless -r $file;
  my $data = retrieve($file->to_string);

  my %index;
  for my $license (keys %{$data->{signatures}}) {
    $index{$_}{$license} = 1 for keys %{$data->{signatures}{$license}};
  }

  my $total = scalar keys %{$data->{signatures}};
  my %idf;
  for my $shingle (keys %index) {
    my $df = scalar keys %{$index{$shingle}};
    $idf{$shingle} = log(($total + 1) / ($df + 1)) + 1;
  }

  return {
    signatures      => $data->{signatures},
    representative  => $data->{representative},
    index           => \%index,
    idf             => \%idf,
    k               => $data->{k} // SIMILARITY_SHINGLE_SIZE,
    distinctive_idf => SIMILARITY_DISTINCTIVE_IDF,
    min_distinctive => SIMILARITY_MIN_DISTINCTIVE
  };
}

# Best matching license for a snippet, using IDF-weighted containment against per-license
# signatures. Candidate licenses are gathered from the snippet's most distinctive shingles (so we
# never score against all licenses), then re-ranked precisely. Returns the winning license, its
# score, a representative pattern id (for risk/name/spdx lookup) and the runner-up score (margin).
sub best_license_for ($self, $text, $ctx) {
  my $shingles = text_shingles($text, $ctx->{k} // SIMILARITY_SHINGLE_SIZE);
  return {license => undef, match => 0, pattern => undef, second => 0} unless %$shingles;

  my @distinctive = sort { ($ctx->{idf}{$b} // 0) <=> ($ctx->{idf}{$a} // 0) } keys %$shingles;
  my %candidates;
  for my $shingle (@distinctive[0 .. min(SIMILARITY_PROBE_SHINGLES, scalar @distinctive) - 1]) {
    next unless my $licenses = $ctx->{index}{$shingle};
    $candidates{$_} = 1 for keys %$licenses;
  }

  # Weight each snippet shingle once - the denominator is the same for every candidate license - then
  # score each candidate by summing only the weights of the shingles its signature contains.
  my @weighted = map { [$_, $ctx->{idf}{$_} // 1] } keys %$shingles;
  my $total    = 0;
  $total += $_->[1] for @weighted;

  my @scored;
  for my $license (keys %candidates) {
    my $sig = $ctx->{signatures}{$license};
    my $hit = 0;
    for my $sw (@weighted) { $hit += $sw->[1] if $sig->{$sw->[0]} }
    push @scored, [$license, $total > 0 ? $hit / $total : 0];
  }
  @scored = sort { $b->[1] <=> $a->[1] } @scored;

  my $best   = $scored[0] // [undef, 0];
  my $second = $scored[1] // [undef, 0];

  # Required-phrase gate (borrowed from ScanCode's "required phrases"): a confident match must share
  # at least one *distinctive* (high-IDF) shingle with the winning license, not rest entirely on
  # common legal boilerplate. Boilerplate-only matches are dropped to no-confidence, which is the
  # safe direction - the snippet stays unresolved and its estimated risk rises rather than folding.
  if (defined $best->[0]) {
    my $floor       = $ctx->{distinctive_idf} // SIMILARITY_DISTINCTIVE_IDF;
    my $min         = $ctx->{min_distinctive} // SIMILARITY_MIN_DISTINCTIVE;
    my $sig         = $ctx->{signatures}{$best->[0]};
    my $distinctive = grep { $sig->{$_} && ($ctx->{idf}{$_} // 0) >= $floor } keys %$shingles;
    $best = [undef, 0] if $distinctive < $min;
  }

  return {
    license  => $best->[0],
    match    => $best->[1],
    pattern  => defined $best->[0] ? $ctx->{representative}{$best->[0]} : undef,
    second   => defined $best->[0] ? $second->[1]                       : 0,
    shingles => $shingles
  };
}

# The license pick above is by license (the combined fingerprint), so the pattern it returns is only an
# arbitrary representative of that license. Refine it to the *actual* closest pattern within the winning
# license, so the resolution reads the right risk/spdx - patterns of one license (e.g. grab-bag "Any CLA")
# can span very different risk levels. The winning license's patterns are loaded once per run (memoized on
# the context) and scored with the same IDF-weighted containment; returns undef if the license has no
# patterns, so callers fall back to the representative.
sub _closest_pattern_in_license ($self, $shingles, $license, $ctx) {

  # Per-license inverted index (shingle -> pattern positions), memoized for the run. Building it costs
  # the same single pass over the license's patterns as the old per-pattern signature cache, but lets
  # each snippet touch only the patterns that actually share a shingle with it - instead of running
  # weighted_containment against every pattern of the license (the analyze hotspot).
  my $entry = $ctx->{pattern_index}{$license} //= do {
    my (@ids, %index);
    my $pos = 0;
    for my $p ($self->pg->db->select('license_patterns', [qw(id pattern)], {license => $license})->hashes->each) {
      my $sig = text_shingles($p->{pattern}, $ctx->{k} // SIMILARITY_SHINGLE_SIZE);
      push @ids,          $p->{id};
      push @{$index{$_}}, $pos for keys %$sig;
      $pos++;
    }
    {ids => \@ids, index => \%index};
  };
  my $ids = $entry->{ids};
  return undef unless @$ids;

  # The containment denominator (total snippet weight) is identical across the license's patterns, so
  # the closest pattern is just the one accumulating the most IDF-weighted shingle hits - no division
  # needed. Only patterns the snippet's shingles actually reach get a hit.
  my $idf   = $ctx->{idf};
  my $index = $entry->{index};
  my @hit;
  for my $shingle (keys %$shingles) {
    my $postings = $index->{$shingle} or next;
    my $w        = $idf->{$shingle} // 1;
    $hit[$_] += $w for @$postings;
  }

  # Argmax with first-wins-on-tie, preserving the previous scan's order and its "always return a
  # pattern" behaviour (unreachable-with-zero-overlap here, thanks to best_license_for's phrase gate).
  my ($best_id, $best_score);
  for my $pos (0 .. $#$ids) {
    my $score = $hit[$pos] // 0;
    ($best_id, $best_score) = ($ids->[$pos], $score) if !defined $best_score || $score > $best_score;
  }
  return $best_id;
}

# Single place that turns a snippet's text into its four scoring columns. With similarity signatures
# ($ctx) it uses the IDF-weighted scorer and stamps the current score version; without them it falls
# back to the plain Spooky bag (stamped version 0, so fold-in will not trust it); with neither it
# returns undef. Shared by analyze (score_package_snippets), the classify task and "snippets --rescore".
sub score_text ($self, $text, $ctx, $bag = undef) {
  if ($ctx) {
    my $best = $self->best_license_for($text, $ctx);

    # Attribute the snippet to the closest pattern *within* the winning license, not the license's
    # arbitrary representative, so the stored like_pattern carries the right risk/spdx. likelyness and
    # second_match stay license-level (the fold thresholds are tuned against that), so only the pattern
    # changes.
    my $like = $best->{pattern};
    if (defined $best->{license}) {
      my $closest = $self->_closest_pattern_in_license($best->{shingles}, $best->{license}, $ctx);
      $like = $closest if defined $closest;
    }

    return {
      likelyness    => $best->{match},
      like_pattern  => $like,
      second_match  => $best->{second} // 0,
      score_version => SNIPPET_SCORE_VERSION
    };
  }

  if ($bag) {
    my $hits = $bag->best_for($text, 1);
    my $best = @$hits ? $hits->[0] : {match => 0, pattern => undef};
    return {likelyness => $best->{match}, like_pattern => $best->{pattern}, second_match => 0, score_version => 0};
  }

  return undef;
}

# Score the snippets of one package that lack a current-version score, using the similarity signatures.
# Called from analyze before the fold/clear/overlap resolution so scores are always present and current
# when a report is built - never dependent on a separate job's timing. Snippets persist across reindex
# (keyed by content hash), so scoping by score_version also self-heals rows stuck at version 0 (e.g.
# classified before the signatures existed). A no-op when nothing is stale (the common reindex case) or
# when the signatures have not been built yet (bootstrapping; left to classify / "snippets --rescore").
sub score_package_snippets ($self, $package_id) {
  my $db = $self->pg->db;

  # Order by id so every concurrent analyze job locks shared snippet rows in the same order, keeping the
  # write transaction below from deadlocking against another job scoring an overlapping snippet set.
  my $rows = $db->query(
    'SELECT DISTINCT s.id, s.text FROM snippets s JOIN file_snippets fs ON fs.snippet = s.id
      WHERE fs.package = ? AND s.score_version IS DISTINCT FROM ? ORDER BY s.id', $package_id, SNIPPET_SCORE_VERSION
  )->hashes;
  return unless $rows->size;

  return unless my $ctx = $self->similarity_context;

  # Score first, outside any transaction, so we never hold locks on the shared (cross-package) snippets
  # table during the CPU-heavy similarity work.
  my @scores = map { [$_->{id}, $self->score_text($_->{text}, $ctx)] } $rows->each;

  # Then flush every row in one short transaction with plain SQL: the columns are fixed, so
  # SQL::Abstract's per-row query building is pure overhead here.
  my $tx = $db->begin;
  for my $score (@scores) {
    my ($id, $s) = @$score;
    $db->query('UPDATE snippets SET likelyness = ?, like_pattern = ?, second_match = ?, score_version = ? WHERE id = ?',
      $s->{likelyness}, $s->{like_pattern}, $s->{second_match}, $s->{score_version}, $id);
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

  $self->expire_cache;

  return $self->find($mid);
}

sub expire_cache ($self) {

  # Drop every engine's matcher and bag caches plus the (shared) similarity sidecar, so stale caches
  # are never used until they are rebuilt - and so invalidation stays correct no matter which engine
  # is active, and after switching engines.
  unlink $_->to_string for $self->_all_cache_files;

  # Reclculate the tf-idfs
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
}

1;
