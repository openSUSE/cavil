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

use Cavil::Util qw(normalize_license_expr paginate pattern_checksum spdx_link text_shingles weighted_containment);
use List::Util  qw(min);
use Mojo::File  qw(path);
use Mojo::JSON  qw(true false);
use Mojo::Util  qw(md5_sum);
use Spooky::Patterns::XS;
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

use constant LICENSE_DETAIL_MATCH_LIMIT   => 10_000;
use constant LICENSE_DETAIL_PACKAGE_LIMIT => 1_000;
use constant LICENSE_PREDICTION_THRESHOLD => 0.3;
use constant LICENSE_PREDICTION_LIMIT     => 10;

sub autocomplete ($self) {
  my $licenses = {};

  my $patterns = $self->pg->db->query(
    'SELECT DISTINCT(license), risk, patent, trademark, export_restricted, cla, eula FROM license_patterns')->hashes;
  for my $pattern ($patterns->each) {
    $licenses->{$pattern->{license}} = {
      risk              => $pattern->{risk},
      patent            => $pattern->{patent},
      trademark         => $pattern->{trademark},
      export_restricted => $pattern->{export_restricted},
      cla               => $pattern->{cla},
      eula              => $pattern->{eula}
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
  my $cache = path($self->cache, 'cavil.pattern.bag');
  return [] unless -r $cache;
  my $bag = Spooky::Patterns::XS::init_bag_of_patterns;
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

  my @scored;
  for my $license (keys %candidates) {
    push @scored, [$license, weighted_containment($shingles, $ctx->{signatures}{$license}, $ctx->{idf})];
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
    license => $best->[0],
    match   => $best->[1],
    pattern => defined $best->[0] ? $ctx->{representative}{$best->[0]} : undef,
    second  => defined $best->[0] ? $second->[1]                       : 0
  };
}

sub create ($self, %args) {
  my $checksum = pattern_checksum($args{pattern});
  my $id       = $self->pattern_exists($checksum);
  return {conflict => $id} if $id;

  # Get SPDX expression for already known licenses
  my $db   = $self->pg->db;
  my $spdx = '';
  if (my $license = $args{license}) {
    my $pattern = $db->query('SELECT spdx FROM license_patterns WHERE license = ? LIMIT 1', $license)->hash;
    $spdx = $pattern->{spdx} if $pattern;
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
      license           => $args{license}           // '',
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
  my $cache = path($self->cache);
  unlink $cache->child('cavil.tokens')->to_string;
  unlink $cache->child('cavil.pattern.bag')->to_string;

  # Drop the similarity sidecar too, so stale per-license signatures / representative ids are not
  # used until pattern_stats rebuilds them.
  unlink $cache->child('cavil.license.signatures')->to_string;

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
    $pattern = Spooky::Patterns::XS::parse_tokens($pattern);
    $matcher->add_pattern($id, $pattern);
  }
}

# possibly cached
sub load_unspecific ($self, $matcher) {
  my $cachefile = path($self->cache, 'cavil.tokens')->to_string;
  if (-f $cachefile) {
    $matcher->load($cachefile);
    return;
  }

  $self->load_specific($matcher, '');

  my $dir = path($self->cache);
  my $tmp = $dir->child("cavil.tokens.tmp.$$")->to_string;
  $matcher->dump($tmp);
  rename $tmp, $cachefile;
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
  Spooky::Patterns::XS::init_matcher();
  my $a   = Spooky::Patterns::XS::parse_tokens($pattern);
  my $ctx = Spooky::Patterns::XS::init_hash(0, 0);
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

  my $search = '';
  if (length($options->{search}) > 0) {
    my $quoted = $db->dbh->quote("\%$options->{search}\%");
    $search = "WHERE license ILIKE $quoted";
  }

  my $results = $db->query(
    qq{
      SELECT license, spdx, ARRAY_AGG(DISTINCT(risk)) AS risks, COUNT(*) OVER() AS total
      FROM (
        SELECT DISTINCT(license), spdx, risk FROM license_patterns
        $search
      ) AS licenses
      GROUP BY license, spdx
      ORDER BY license
      LIMIT ? OFFSET ?
    }, $options->{limit}, $options->{offset}
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

  my $patterns = $db->query(
    "SELECT lp.*, bu1.login AS owner_login, bu2.login AS contributor_login,
       EXTRACT(EPOCH FROM created) AS created_epoch, COUNT(*) OVER() AS total
     FROM license_patterns lp LEFT JOIN bot_users bu1 ON (bu1.id = lp.owner)
       LEFT JOIN bot_users bu2 ON (bu2.id = lp.contributor)
     WHERE lp.id > 0 $before $contributor $timeframe ORDER BY lp.id DESC LIMIT 10"
  )->hashes;

  my $total = 0;
  for my $pattern (@$patterns) {
    $total = delete $pattern->{total};
    my $count = $self->match_count($pattern->{id});
    $pattern->{matches}  = $count->{matches};
    $pattern->{packages} = $count->{packages};
  }

  return {total => $total, patterns => $patterns->to_array};
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
      risk              => $args{risk}              // 5,
      ($args{owner} ? (owner => $args{owner}) : ())
    },
    {id => $id}
  );
}

1;
