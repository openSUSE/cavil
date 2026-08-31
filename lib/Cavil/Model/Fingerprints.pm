# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later
#
# The fingerprint index for snippet code search: a Postgres GIN inverted index. fp_files maps a content hash to
# the packages/paths that carry it (generation-tracked, so it rides the report's atomic promote), and fp_contents
# is the content dimension - one row per distinct content holding its winnowed fingerprints as a GIN-indexed
# bigint[] with parallel slines/elines arrays for the line positions. A query overlaps (&&) its own fingerprints
# against those arrays, so it only touches contents that share one. Ubiquitous fingerprints are recorded in
# fp_stopwords and pruned from the query (not the arrays), so a common gram never blows the candidate set up.
# Only used when code search is enabled (see Cavil::codesearch).

package Cavil::Model::Fingerprints;
use Mojo::Base -base, -signatures;

use Cavil::Matcher ();
use Cavil::PatternEngine;
use Cavil::ReportUtil qw(is_vendored_path);
use Cavil::Util       qw(checkout_path original_filename);
use Mojo::File        qw(path tempfile);
use Mojo::JSON        qw(false true);
use Time::HiRes       ();

has [qw(pg log checkout_dir generation_file)];
has k => 4;
has w => 8;

# How many contents a fingerprint may be carried by before it stops discriminating a copy. It bounds the search
# twice over, which is what keeps query cost predictable: refresh_stopwords records the fingerprints above it so
# their posting lists are skipped outright, and search_fingerprints caps how many carriers of any ONE fingerprint
# it will read, so total work stays under (query size x df_cap) even for a gram no stopword sweep has caught yet.
# The main precision and query-speed knob, config-driven (codesearch.df_cap); deliberately aggressive.
has df_cap => 500;

# Cap on fingerprints stored per content (0 disables). A generated, minified or data file can winnow to tens of
# thousands of fingerprints; the overlap count unnests a candidate's whole array, so one such giant content makes
# every query that shares a single fingerprint with it slow. Such files are not function-copy targets anyway, so
# keep only the first max_fingerprints (file order). Config-driven (codesearch.max_fingerprints).
has max_fingerprints => 5000;

# Lines of context shown around a matched region in a result preview.
use constant EXCERPT_CONTEXT => 3;

# Winnowed fingerprints are uint64; a Postgres bigint is signed. Reinterpret the bits losslessly (NOT $fp -
# 2**64, which is float-lossy) and identically on write and query, so the same content hashes to the same key.
# A whole list at a time, because pack/unpack do that natively: converting value by value was ~35% of the
# build's Perl time (a few hundred calls per file, millions of files), and is 6x slower for the same result.
sub _fp_bigints (@fps) { return unpack 'q*', pack 'Q*', @fps }

# Was this location indexed through a rewritten ".processed" copy? Reported so a caller knows the names it got
# are the original's while any line numbers are the copy's (see the processed flag in search_fingerprints).
sub _is_processed ($where) {
  return $where && original_filename($where->{filename}) ne $where->{filename} ? 1 : 0;
}

# Record one indexed file: its content hash maps to (package, path) at this generation. The content itself
# is registered separately (queue_contents), once per batch, to keep this hot-path insert conflict-free.
sub record_file ($self, $db, $package, $filename, $hash, $generation) {
  $db->query('INSERT INTO fp_files (package, filename, hash, generation) VALUES (?, ?, ?, ?)',
    $package, $filename, $hash, $generation);
}

# Register content hashes for fingerprinting (build_pending later winnows the pending ones). Inserted in
# sorted order so concurrent index_batch jobs lock fp_contents keys in the same order; per-file inserts in
# file order deadlocked in production. Mirrors the sorted url/email/copyright upserts in Task::Index.
sub queue_contents ($self, $db, $hashes) {
  $db->query('INSERT INTO fp_contents (hash) VALUES (?) ON CONFLICT (hash) DO NOTHING', $_) for sort keys %$hashes;
}

# Discard the whole index so the next build starts fresh (a k/w change or a forced rebuild): drop the stopwords
# and set every content back to pending. The stale arrays are simply overwritten as each content is rebuilt, and
# search ignores non-indexed rows, so there is nothing to clear. Cheap next to a re-winnow.
sub reset_index ($self) {
  my $db = $self->pg->db;
  my $tx = $db->begin;
  $db->query('DELETE FROM fp_stopwords');
  $db->query('UPDATE fp_contents SET indexed = false WHERE indexed');
  $tx->commit;
}

# Fingerprint up to $limit not-yet-indexed contents into the index. One representative file per content is enough
# (all copies share the bytes). Shards are disjoint id slices, so parallel builders never write the same row and
# nothing needs claiming; at shards = 1 the filter is a no-op, which keeps it to one query.
sub build_pending ($self, $shard = 0, $shards = 1, $limit = 20000) {
  my $db   = $self->pg->db;
  my $rows = $db->query(
    "SELECT c.id, p.name, p.checkout_dir AS co, f.filename
       FROM fp_contents c
       JOIN LATERAL (
         SELECT package, filename FROM fp_files WHERE hash = c.hash AND generation = 0 LIMIT 1
       ) f ON true
       JOIN bot_packages p ON p.id = f.package
      WHERE NOT c.indexed AND c.id % ? = ?
      LIMIT ?", $shards, $shard, $limit
  )->hashes;
  return 0 unless @$rows;

  my $tx = $db->begin;
  for my $r (@$rows) {
    my $abs = checkout_path($self->checkout_dir, $r->{name}, $r->{co}, '.unpacked', $r->{filename});
    $self->_store_arrays($db, $r->{id}, Cavil::Matcher::fingerprint_file("$abs", $self->k, $self->w));
  }
  $tx->commit;
  return scalar @$rows;
}

# Store a content's winnowed fingerprints as a GIN-indexed array with parallel line positions, one entry per
# distinct fingerprint (its first occurrence). Stopwords are kept here and pruned from the query instead, so a
# shifting stopword set never has to rewrite arrays.
sub _store_arrays ($self, $db, $content, $raw) {
  my @signed = _fp_bigints(map { $_->[0] } @$raw);

  my (%seen, @fp, @sl, @el);
  for my $i (0 .. $#signed) {
    next if $seen{$signed[$i]}++;
    push @fp, $signed[$i];
    push @sl, $raw->[$i][1];
    push @el, $raw->[$i][2];
  }

  # Cap a pathologically large file (generated/minified/data): its array would be unnested in full by every query
  # that shares a single fingerprint with it. Keep the first max_fingerprints in file order; 0 disables the cap.
  my $max = $self->max_fingerprints;
  if ($max && @fp > $max) { $#fp = $#sl = $#el = $max - 1 }

  $db->query(
    'UPDATE fp_contents SET fingerprints = ?::bigint[], slines = ?::int[], elines = ?::int[], indexed = true
                WHERE id = ?', \@fp, \@sl, \@el, $content
  );
}

# Recompute the stopword set - fingerprints whose document frequency exceeds the cap - over the current arrays,
# so the query can prune them. No array rewrite: they stay stored (GIN compresses them away) and are dropped at
# query time. ORDER BY is load-bearing, not tidiness: shards run this concurrently, and a GROUP BY emits rows in
# hash order, so without one insert order two of them take conflict locks in opposite orders and deadlock.
sub refresh_stopwords ($self, $cap = undef) {
  $cap //= $self->df_cap;
  $self->pg->db->query(
    'INSERT INTO fp_stopwords (fingerprint)
       SELECT fp FROM fp_contents c, unnest(c.fingerprints) fp WHERE c.indexed GROUP BY fp HAVING count(*) > ?
       ORDER BY fp
     ON CONFLICT DO NOTHING', $cap
  );
}

# The corpus version, bumped per build, in a small file in the shared cache dir. Losing it resets to 0, which
# only makes clients drop their caches once (they invalidate on any change, not on ordering).
sub generation ($self) {
  my $g = eval { path($self->generation_file)->slurp } // '';
  $g =~ s/\D//g;
  return length $g ? 0 + $g : 0;
}

sub bump_generation ($self) {
  my $file = path($self->generation_file);
  my $tmp  = $file->sibling($file->basename . ".tmp.$$");
  $tmp->spew($self->generation + 1);
  rename $tmp, "$file" or die "cannot update fingerprint generation: $!\n";
  return $self;
}

# Drop content bookkeeping for hashes no file references any more (their packages went obsolete or were
# reindexed away). fp_files is pruned by the promote and obsolete cleanup, so without this fp_contents would
# only ever grow. Called from the daily cleanup; a pruned content's fingerprint arrays go with its row.
sub prune_contents ($self) {
  return $self->pg->db->query(
    'DELETE FROM fp_contents WHERE NOT EXISTS (SELECT 1 FROM fp_files WHERE fp_files.hash = fp_contents.hash)')->rows;
}

# A query winnowing to fewer distinct fingerprints than this cannot be located reliably: containment is
# hits/distinct, so with a tiny set even one shared common gram scores 100%. Short or repetitive pastes (a
# struct of identical short fields, say) land here and are reported as too short instead of flooding results.
use constant MIN_QUERY_FINGERPRINTS => 8;

# A match must share at least this fraction of the (now guaranteed sizable) query; below it is idiom
# coincidence, not resemblance.
use constant MIN_CONTAINMENT => 0.25;

# A search taking at least this long is logged with a timing breakdown, to pinpoint performance problems.
use constant SLOW_SEARCH_MS => 1000;

# Search known sources for content resembling a snippet. Returns ranked matches, each with both-direction
# containment, the matched line regions, the licenses/packages that carry the content, and a risk level.
# $exclude_embargoed hides embargoed packages; only the MCP surface sets it, as its results feed an AI model.
sub search ($self, $snippet, $limit = 10, $offset = 0, $exclude_embargoed = 0) {
  return {matches => [], total => 0} unless length($snippet // '');

  # The matcher winnows files, not strings, so the snippet goes through a temp file for identical treatment.
  my $tmp = tempfile;
  $tmp->spew($snippet);
  my $raw = Cavil::Matcher::fingerprint_file($tmp->to_string, $self->k, $self->w);    # [[fp, sline, eline], ...]
  my %seen;
  my @qfps = grep { !$seen{$_}++ } map { $_->[0] } @$raw;

  # The snippet's line span feeds alignment (see search_fingerprints / _alignment): a verbatim copy occupies
  # about this many lines in the matched file.
  my ($qlo, $qhi);
  for my $r (@$raw) {
    $qlo = $r->[1] if !defined $qlo || $r->[1] < $qlo;
    $qhi = $r->[2] if !defined $qhi || $r->[2] > $qhi;
  }
  my $qspan = defined $qlo ? $qhi - $qlo + 1 : 1;

  return $self->search_fingerprints(\@qfps, $qspan, $limit, $offset, $exclude_embargoed);
}

# Rank and enrich a page of matches for an already-winnowed query: the deduped query fingerprints and their
# line span (needed for alignment). This is the shared core of the snippet search and the batch fingerprint
# API; search() is just the winnowing front-end that turns a snippet into these. Fingerprints may arrive as
# numbers (snippet path) or decimal strings (batch API, where JSON cannot carry a 64-bit value losslessly);
# both coerce identically for the index lookup and for the alignment hash keys.
sub search_fingerprints (
  $self, $qfps, $qspan,
  $limit             = 10,
  $offset            = 0,
  $exclude_embargoed = 0,
  $exclude_packages  = undef
  )
{

  # Too few distinct fingerprints to search on (see MIN_QUERY_FINGERPRINTS); say so rather than return noise.
  # No token-count guidance: the real floor is distinct fingerprints, which repetitive code reaches far later.
  return {matches => [], total => 0, too_short => \1} if @$qfps < MIN_QUERY_FINGERPRINTS;

  # Cap an oversized query the same way the index caps a content (see _store_arrays): a huge file - a data blob, a
  # minified bundle - winnows to tens of thousands of fingerprints, and an overlap search on all of them would
  # gather most of the corpus. It is not a function-copy target, so search on its first max_fingerprints.
  my $max = $self->max_fingerprints;
  $qfps = [@{$qfps}[0 .. $max - 1]] if $max && @$qfps > $max;

  my $db    = $self->pg->db;
  my $t0    = Time::HiRes::time;
  my @bfps  = _fp_bigints(@$qfps);
  my $denom = scalar @bfps;
  my $need  = int(MIN_CONTAINMENT * $denom);
  $need++ if MIN_CONTAINMENT * $denom > $need;    # ceil: a match must clear the containment floor

  # Skip fingerprints already known to be ubiquitous, so their posting lists are never read at all. This is an
  # optimization, not a correctness or safety requirement: the probe limit below independently bounds what any
  # single fingerprint can cost, so a stopword the set has not caught yet (the set is recomputed as the corpus
  # grows) is merely a little slower, never catastrophic. denom stays the full query size, so a query full of
  # common grams simply scores lower.
  my %stop = map { $_->{fingerprint} => 1 }
    @{$db->query('SELECT fingerprint FROM fp_stopwords WHERE fingerprint = ANY(?::bigint[])', \@bfps)->hashes};
  my @live = grep { !$stop{$_} } @bfps;
  return {matches => [], total => 0} unless @live;

  # Use the GIN index as a true inverted index: one lookup per live query fingerprint (contents that contain it),
  # union the postings, then count per content. This touches only the matching postings - never unnesting a
  # candidate's whole array, and with no per-element membership test - so cost tracks the postings read, not
  # (candidates x array size x query size). Counting via unnest+`f = ANY(query)` instead makes that ANY a linear
  # scan of the query array per element, which multiplied the work by the query size and cost tens of seconds.
  #
  # LIMIT bounds each fingerprint's contribution, which is what keeps the whole query safe: total work is at most
  # (query size x df_cap) however common a gram turns out to be, instead of being dominated by the single worst
  # one. Truncation only ever affects a fingerprint carried by more than df_cap contents, and such a fingerprint
  # cannot identify a copy anyway - it is precisely what the stopword set exists to discard - so this reads as
  # "look at up to df_cap carriers of any one gram" rather than as an approximation of something meaningful.
  my $cand = $db->query(
    "SELECT c.id AS content, c.hash, count(*) AS hits
       FROM unnest(?::bigint[]) AS q(fp)
       CROSS JOIN LATERAL (
         SELECT id, hash FROM fp_contents WHERE indexed AND fingerprints @> ARRAY[q.fp] LIMIT ?
       ) c
      GROUP BY c.id, c.hash
      HAVING count(*) >= ?", \@live, $self->df_cap, $need
  )->hashes;
  my $t_idx = Time::HiRes::time;

  # Drop obsolete (and embargoed/excluded when asked) carriers before paging, keyed by hash, so offset/total
  # stay consistent - a content can outlive or be excluded from its visible carriers.
  my %live = map { $_ => 1 } @{$self->_live_hashes([map { $_->{hash} } @$cand], $exclude_embargoed, $exclude_packages)};
  my @all  = grep { $live{$_->{hash}} } @$cand;
  my $t_db = Time::HiRes::time;

  if ($self->log && int(($t_db - $t0) * 1000) >= SLOW_SEARCH_MS) {
    $self->log->info(
      sprintf 'Slow code search: %d fingerprints, %d matches; aggregate %dms, db %dms',
      $denom, scalar @all,
      int(($t_idx - $t0) * 1000),
      int(($t_db - $t_idx) * 1000)
    );
  }

  # Strongest first by containment (hits/denom, and denom is constant so hits orders it); a stable hash tiebreak
  # keeps paging deterministic.
  @all = sort { $b->{hits} <=> $a->{hits} || $a->{hash} cmp $b->{hash} } @all;
  my $total = scalar @all;
  return {matches => [], total => $total} if $offset >= $total;
  my $end = $offset + $limit - 1;
  $end = $#all if $end > $#all;
  my @page   = @all[$offset .. $end];
  my @ids    = map { $_->{content} } @page;
  my @hashes = map { $_->{hash} } @page;

  # For the page only, straight from each content's arrays: the matched line positions (for alignment and the
  # excerpt) and its stored fingerprint count for the content-direction containment. Both use the live query
  # fingerprints and exclude stopwords, so a stopword gram never spuriously aligns and a self-match reads ~1.0.
  my %regions;
  for my $p (
    @{
      $db->query(
        'SELECT c.id AS content, u.fp, u.sl, u.el
           FROM fp_contents c
           CROSS JOIN LATERAL unnest(c.fingerprints, c.slines, c.elines) AS u(fp, sl, el)
           JOIN unnest(?::bigint[]) AS q(fp) ON q.fp = u.fp
          WHERE c.id = ANY(?::int[])', \@live, \@ids
      )->hashes
    }
    )
  {
    push @{$regions{$p->{content}}}, [$p->{sl}, $p->{el} - $p->{sl}, $p->{fp}];    # [sline, span, fp]
  }
  my %cfps = map { $_->{content} => $_->{n} } @{
    $db->query(
      'SELECT c.id AS content, count(*) AS n
         FROM fp_contents c, unnest(c.fingerprints) f
        WHERE c.id = ANY(?::int[]) AND f NOT IN (SELECT fingerprint FROM fp_stopwords)
        GROUP BY c.id', \@ids
    )->hashes
  };

  my $lic  = $self->_licenses_by_hash(\@hashes, $exclude_embargoed, $exclude_packages);
  my $locs = $self->_locations_by_hash(\@hashes, $exclude_embargoed, $exclude_packages);
  my $decl = $self->_declared_by_hash(\@hashes, $exclude_embargoed, $exclude_packages);

  my @matches;
  for my $p (@page) {
    my $hash    = $p->{hash};
    my $regions = [sort { $a->[0] <=> $b->[0] } @{$regions{$p->{content}} // []}];
    my $where   = $locs->{$hash} // [];

    # Marks are over the query's own fingerprints in order (@bfps mirrors @$qfps); a stopword query fingerprint
    # never aligns, like any unmatched one.
    my ($marks, $aligned) = _alignment($regions, \@bfps, $qspan);
    push @matches, {
      hash           => $hash,
      containment    => $p->{hits} / $denom,
      containment_of => $p->{hits} / ($cfps{$p->{content}} || $p->{hits}),
      licenses       => $lic->{$hash}{licenses} // [],
      risk           => $lic->{$hash}{risk},    # max license risk (Cavil's 1-9 scale), undef if none

      # Reported under the name the scanned copy was made from, so a caller is never shown (or handed on) the
      # internal ".processed" variant. The excerpt keeps the real path, because its line numbers are the copy's.
      files => [
        map {
          { %$_, filename => original_filename($_->{filename}) }
        } @$where
      ],
      excerpt => $self->_excerpt($where->[0], $regions->[0]),
      marks   => $marks,                                        # per query fingerprint, in order: 1 aligned, 0 not
      aligned => $aligned,
      total   => scalar @$qfps,
      exact   => ($aligned == @$qfps ? true : false),           # Mojo::JSON booleans: correct in Perl and JSON

      # Set when this content was indexed through a rewritten copy of the file (long lines re-wrapped, see
      # Cavil::PostProcess). The names above are the original's, but the line numbers - excerpt, and the regions
      # they came from - are positions in that copy, so they do not address the named file. Flagged rather than
      # papered over: only the caller knows whether it is showing a preview (fine) or resolving a location.
      (_is_processed($where->[0]) ? (processed => true) : ()),

      # The carrier's declared main license when this content is its own (non-vendored) source; accompanies the
      # per-file licenses above, which still drive the risk. Absent when no non-vendored carrier declares one.
      ($decl->{$hash} ? (declared_license => $decl->{$hash}) : ())
    };
  }
  return {matches => \@matches, total => $total};
}

# Batch content-hash lookup for the CLI: for each hash Cavil has seen, its licenses, max risk, and one package
# and path that carry it (so the client can say what a recognized file is a copy of, not just "a known
# source"). A hash the instance knows but has no license match for still returns an entry (empty licenses,
# undef risk), so the caller can tell "known, no license detected" from "never seen" (absent from the result).
sub known_hashes ($self, $hashes, $exclude_embargoed = 0, $exclude_packages = undef) {
  return {} unless @$hashes;
  my $live = $self->_live_hashes($hashes, $exclude_embargoed, $exclude_packages);
  return {} unless @$live;

  my $lic  = $self->_licenses_by_hash($live, $exclude_embargoed, $exclude_packages);
  my $locs = $self->_locations_by_hash($live, $exclude_embargoed, $exclude_packages);
  my $decl = $self->_declared_by_hash($live, $exclude_embargoed, $exclude_packages);
  my %known;
  for my $hash (@$live) {
    my $where = $locs->{$hash}[0];
    $known{$hash} = {
      licenses => $lic->{$hash}{licenses} // [],
      risk     => $lic->{$hash}{risk},
      ($where ? (package => $where->{name}, filename => original_filename($where->{filename})) : ()),
      (_is_processed($where) ? (processed => true) : ()), ($decl->{$hash} ? (declared_license => $decl->{$hash}) : ())
    };
  }
  return \%known;
}

# Tell an aligned copy from scattered coincidence: group the matched fingerprints' content lines into runs,
# breaking a run at any gap wider than the snippet itself - the largest run is the copy. Returns a per-query-
# fingerprint mark array (query order, 1 = inside that run) and the aligned count. A verbatim copy aligns
# every fingerprint; a modified one leaves the changed ones dark - absent, or matched only outside the copy
# (as when a renamed token's fingerprint happens to recur elsewhere in the file, which inflates containment).
# Gap-based, not a fixed-width window: identical text can winnow to a slightly wider line span in the file
# than in the standalone snippet, so a window sized to the query span clips the copy's edge fingerprints.
sub _alignment ($regions, $qfps, $qspan) {
  my @pts = sort { $a->[0] <=> $b->[0] } map { [$_->[0], $_->[2]] } @$regions;    # [content_line, fp]
  my $gap = $qspan > 1 ? $qspan : 1;
  my (%best, %run);
  for my $i (0 .. $#pts) {
    if ($i > 0 && $pts[$i][0] - $pts[$i - 1][0] > $gap) {
      %best = %run if keys %run > keys %best;
      %run  = ();
    }
    $run{$pts[$i][1]} = 1;
  }
  %best = %run if keys %run > keys %best;
  my @marks = map { $best{$_} ? 1 : 0 } @$qfps;
  return (\@marks, scalar grep {$_} @marks);
}

# Names shown in the provenance strip; a larger total appears as a count, which flags common boilerplate.
use constant PROVENANCE_LIST => 6;

# Other current packages carrying this file's exact bytes. Content-derived only: never says whether the code
# was accepted there, because acceptability is a per-package compatibility decision that does not transfer.
# Obsolete carriers are dropped; embargoed are not, since this feeds the report browser (which shows them).
sub file_provenance ($self, $package_id, $filename) {
  my $db   = $self->pg->db;
  my $hash = $db->query('SELECT hash FROM fp_files WHERE package = ? AND filename = ? AND generation = 0 LIMIT 1',
    $package_id, $filename)->array;
  return undef unless $hash;
  $hash = $hash->[0];

  # Cheap count first: most files are unique, so bail before the list query.
  my $count = $db->query(
    "SELECT count(DISTINCT p.name)
       FROM fp_files ff JOIN bot_packages p ON p.id = ff.package
      WHERE ff.hash = ? AND ff.generation = 0 AND p.obsolete = false AND p.id <> ?", $hash, $package_id
  )->array->[0];
  return undef unless $count;

  my $locations = $db->query(
    "SELECT DISTINCT ON (p.name) p.id AS package, p.name, ff.filename
       FROM fp_files ff JOIN bot_packages p ON p.id = ff.package
      WHERE ff.hash = ? AND ff.generation = 0 AND p.obsolete = false AND p.id <> ?
      ORDER BY p.name LIMIT ?", $hash, $package_id, PROVENANCE_LIST
  )->hashes->to_array;

  return {count => $count, locations => $locations};
}

# The matched region of one representative file (all copies share the bytes), with a little context, each
# line flagged matched or not - shown inline in the result so a reviewer sees the code without a round trip.
sub _excerpt ($self, $where, $region) {
  return [] unless $where && $region;
  my ($sline, $span) = @$region;
  my $pkg = $self->pg->db->select('bot_packages', ['name', 'checkout_dir'], {id => $where->{package}})->hash;
  return [] unless $pkg;

  my ($from, $to) = ($sline - EXCERPT_CONTEXT, $sline + $span + EXCERPT_CONTEXT);
  $from = 1 if $from < 1;
  my %wanted = map { $_ => 1 } $from .. $to;
  my $abs    = checkout_path($self->checkout_dir, $pkg->{name}, $pkg->{checkout_dir}, '.unpacked', $where->{filename});
  return [map { {number => $_->[0], text => $_->[2], matched => ($_->[0] >= $sline && $_->[0] <= $sline + $span)} }
    sort { $a->[0] <=> $b->[0] } @{Cavil::PatternEngine::read_lines("$abs", \%wanted)}];
}

# The licenses (and their max risk) found in the matched content, from the per-file license data of the
# packages that carry it. Best-effort: source with no license match of its own reports none - a follow-up
# could fall back to the directory's declared license, the way the compatibility feature does.
#
# catch_all patterns are excluded: they match generic boilerplate (a specfile's shape, a copyright phrase, a
# "reference" to a license elsewhere) rather than establishing a license, exactly as the rest of Cavil treats
# them as non-concrete. Including them buried the real license in "Any openSUSE specfile, Any SUSE copyright,
# ..." noise and skewed the risk.
sub _licenses_by_hash ($self, $hashes, $exclude_embargoed = 0, $exclude_packages = undef) {
  my $emb = $exclude_embargoed                      ? ' AND p.embargoed = false' : '';
  my $exc = $exclude_packages && @$exclude_packages ? ' AND p.name <> ALL(?)'    : '';
  my %info;
  my $rows = $self->pg->db->query(
    "SELECT ff.hash, array_agg(DISTINCT lp.license) AS licenses, max(lp.risk) AS risk
       FROM fp_files ff
       JOIN bot_packages p ON p.id = ff.package AND p.obsolete = false$emb
       JOIN matched_files mf ON mf.package = ff.package AND mf.filename = ff.filename AND mf.generation = 0
       JOIN pattern_matches pm ON pm.file = mf.id AND pm.ignored = false
       JOIN license_patterns lp ON lp.id = pm.pattern AND lp.license <> '' AND lp.catch_all = false
      WHERE ff.hash = ANY(?) AND ff.generation = 0$exc
      GROUP BY ff.hash", $hashes, ($exc ? $exclude_packages : ())
  )->hashes;
  $info{$_->{hash}} = {risk => $_->{risk}, licenses => $_->{licenses}} for @$rows;
  return \%info;
}

# Which packages/paths carry each matched content (capped per content; the full expansion is available on
# demand). This is the "found in" list, and dedup means one content lists every version that ships it.
sub _locations_by_hash ($self, $hashes, $exclude_embargoed = 0, $exclude_packages = undef) {
  my $emb = $exclude_embargoed                      ? ' AND p.embargoed = false' : '';
  my $exc = $exclude_packages && @$exclude_packages ? ' AND p.name <> ALL(?)'    : '';
  my %locs;
  my $rows = $self->pg->db->query(
    "SELECT ff.hash, p.name, p.id AS package, ff.filename
       FROM fp_files ff JOIN bot_packages p ON p.id = ff.package
      WHERE ff.hash = ANY(?) AND ff.generation = 0 AND p.obsolete = false$emb$exc
      ORDER BY p.name", $hashes, ($exc ? $exclude_packages : ())
  )->hashes;
  for my $r (@$rows) {
    my $list = $locs{$r->{hash}} //= [];
    push @$list, {package => $r->{package}, name => $r->{name}, filename => $r->{filename}} if @$list < 25;
  }
  return \%locs;
}

# For each hash, the declared (specfile) main license of a carrier that ships it as its own, non-vendored code -
# the high-value indicator the report shows at the top. Only carriers with a declared license are considered
# (declared_license IS NOT NULL), and a vendored carrier is skipped: a package's declared license describes its
# own source, not a dependency it bundles. The first non-vendored carrier by name wins; a hash carried only in
# vendored trees (or by packages that declare nothing) is simply absent. Accompanies the per-file licenses, it
# does not replace them, so the risk and gate still come from the per-file patterns.
sub _declared_by_hash ($self, $hashes, $exclude_embargoed = 0, $exclude_packages = undef) {
  return {} unless @$hashes;
  my $emb  = $exclude_embargoed                      ? ' AND p.embargoed = false' : '';
  my $exc  = $exclude_packages && @$exclude_packages ? ' AND p.name <> ALL(?)'    : '';
  my $rows = $self->pg->db->query(
    "SELECT ff.hash, ff.filename, r.declared_license
       FROM fp_files ff
       JOIN bot_packages p ON p.id = ff.package
       JOIN bot_reports r ON r.package = p.id
      WHERE ff.hash = ANY(?) AND ff.generation = 0 AND p.obsolete = false AND r.declared_license IS NOT NULL$emb$exc
      ORDER BY p.name", $hashes, ($exc ? $exclude_packages : ())
  )->hashes;

  my %declared;
  for my $r (@$rows) {
    next if exists $declared{$r->{hash}} || is_vendored_path($r->{filename});
    $declared{$r->{hash}} = $r->{declared_license};
  }
  return \%declared;
}

# Of the given hashes, those in a visible package: never obsolete, never embargoed when asked, and never carried
# only by an excluded package. A hash left with no carrier is simply not live: an engineer scanning their own
# package excludes it and their code stops matching itself, while a file also shipped elsewhere still surfaces.
sub _live_hashes ($self, $hashes, $exclude_embargoed = 0, $exclude_packages = undef) {
  return [] unless @$hashes;
  my $emb  = $exclude_embargoed                      ? ' AND p.embargoed = false' : '';
  my $exc  = $exclude_packages && @$exclude_packages ? ' AND p.name <> ALL(?)'    : '';
  my $rows = $self->pg->db->query(
    "SELECT DISTINCT ff.hash
       FROM fp_files ff JOIN bot_packages p ON p.id = ff.package
      WHERE ff.hash = ANY(?) AND ff.generation = 0 AND p.obsolete = false$emb$exc", $hashes,
    ($exc ? $exclude_packages : ())
  )->hashes;
  return [map { $_->{hash} } @$rows];
}

1;
