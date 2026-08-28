# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later
#
# The fingerprint index for snippet code search: a Postgres inverted index. fp_files maps a content hash to
# the packages/paths that carry it (generation-tracked, so it rides the report's atomic promote), fp_contents
# is the content dimension (a compact id per distinct content), and fp_postings is the inverted index proper -
# fingerprint -> content, with line positions - hash-partitioned by fingerprint. Ubiquitous fingerprints are
# pruned into fp_stopwords at build time and never stored, so a query only ever touches the postings of its own
# (discriminative) fingerprints. Only used when code search is enabled (see Cavil::codesearch).

package Cavil::Model::Fingerprints;
use Mojo::Base -base, -signatures;

use Cavil::Matcher ();
use Cavil::PatternEngine;
use Cavil::ReportUtil qw(is_vendored_path);
use Cavil::Util       qw(checkout_path);
use Mojo::File        qw(path tempfile);
use Mojo::JSON        qw(false true);
use Time::HiRes       ();

has [qw(pg log checkout_dir generation_file)];
has k => 4;
has w => 8;

# Lines of context shown around a matched region in a result preview.
use constant EXCERPT_CONTEXT => 3;

# A fingerprint whose document frequency (contents it appears in) exceeds this is a stopword: pruned from the
# index, because it is common boilerplate that neither discriminates a copy nor fits in a lean index. The main
# precision and size knob; deliberately aggressive, and re-tunable on the next reindex (see Cavil::codesearch).
use constant DF_CAP => 500;

# Winnowed fingerprints are uint64; a Postgres bigint is signed. Reinterpret the bits losslessly (NOT $fp -
# 2**64, which is float-lossy) and identically on write and query, so the same content hashes to the same key.
sub _fp_bigint ($fp) { return unpack 'q', pack 'Q', $fp }

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

# Discard the whole index so the next build starts fresh (a k/w change or a forced rebuild): drop every
# posting and stopword and set every content back to pending. Cheap next to a re-winnow, and the reindex
# repopulates.
sub reset_index ($self) {
  my $db = $self->pg->db;
  my $tx = $db->begin;
  $db->query('TRUNCATE fp_postings');
  $db->query('DELETE FROM fp_stopwords');
  $db->query('UPDATE fp_contents SET indexed = false WHERE indexed');
  $tx->commit;
}

# Fingerprint up to $limit not-yet-indexed contents into the inverted index. One representative file per content
# is enough (all copies share the bytes). Postings for known stopwords are skipped so common fingerprints are
# never stored; a from-scratch reindex (empty stopwords) stores everything and refresh_stopwords prunes after.
sub build_pending ($self, $limit = 20000) {
  my $db   = $self->pg->db;
  my $rows = $db->query(
    "SELECT c.id, p.name, p.checkout_dir AS co, f.filename
       FROM fp_contents c
       JOIN LATERAL (
         SELECT package, filename FROM fp_files WHERE hash = c.hash AND generation = 0 LIMIT 1
       ) f ON true
       JOIN bot_packages p ON p.id = f.package
      WHERE NOT c.indexed
      LIMIT ?", $limit
  )->hashes;
  return 0 unless @$rows;

  my %stop = map { $_->{fingerprint} => 1 } @{$db->query('SELECT fingerprint FROM fp_stopwords')->hashes};

  my $tx = $db->begin;
  for my $r (@$rows) {
    my $abs = checkout_path($self->checkout_dir, $r->{name}, $r->{co}, '.unpacked', $r->{filename});
    $self->_store_postings($db, $r->{id}, Cavil::Matcher::fingerprint_file("$abs", $self->k, $self->w), \%stop);
    $db->query('UPDATE fp_contents SET indexed = true WHERE id = ?', $r->{id});
  }
  $tx->commit;
  return scalar @$rows;
}

# Insert a content's winnowed rows as postings (signed fingerprint + line span), skipping stopwords, in bind-
# limit-safe chunks (4 params per row).
sub _store_postings ($self, $db, $content, $raw, $stop) {
  my @tuples;
  for my $row (@$raw) {
    my $fp = _fp_bigint($row->[0]);
    push @tuples, [$content, $fp, $row->[1], $row->[2]] unless $stop->{$fp};
  }
  while (my @chunk = splice @tuples, 0, 10000) {
    my $sql
      = 'INSERT INTO fp_postings (content, fingerprint, sline, eline) VALUES ' . join(',', ('(?, ?, ?, ?)') x @chunk);
    $db->query($sql, map {@$_} @chunk);
  }
}

# Recompute the stopword set over the current postings and delete their rows, so ubiquitous fingerprints stop
# occupying the index. A GROUP BY + DELETE over postings, no re-winnowing; run at the end of a build.
sub refresh_stopwords ($self, $cap = DF_CAP) {
  my $db = $self->pg->db;
  my $tx = $db->begin;
  $db->query(
    'INSERT INTO fp_stopwords (fingerprint)
       SELECT fingerprint FROM fp_postings GROUP BY fingerprint HAVING count(DISTINCT content) > ?
     ON CONFLICT DO NOTHING', $cap
  );
  $db->query('DELETE FROM fp_postings WHERE fingerprint IN (SELECT fingerprint FROM fp_stopwords)');
  $tx->commit;
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
# only ever grow. Called from the daily cleanup; a pruned content's postings go with it via ON DELETE CASCADE.
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

  my $db    = $self->pg->db;
  my $t0    = Time::HiRes::time;
  my @bfps  = map { _fp_bigint($_) } @$qfps;
  my $denom = scalar @bfps;
  my $need  = int(MIN_CONTAINMENT * $denom);
  $need++ if MIN_CONTAINMENT * $denom > $need;    # ceil: a match must clear the containment floor

  # The inverted-index aggregate: hits per content over the query's fingerprints. Stopword fingerprints have no
  # postings, so they cost nothing and simply do not contribute - no query-side pruning needed.
  my $cand = $db->query(
    "SELECT fp.content, c.hash, count(DISTINCT fp.fingerprint) AS hits
       FROM fp_postings fp JOIN fp_contents c ON c.id = fp.content
      WHERE fp.fingerprint = ANY(?::bigint[])
      GROUP BY fp.content, c.hash
      HAVING count(DISTINCT fp.fingerprint) >= ?", \@bfps, $need
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

  # For the page only: the matched postings (for alignment and the excerpt) and each content's stored
  # fingerprint count (for the content-direction containment - no maintained column needed).
  my %regions;
  for my $p (
    @{
      $db->query(
        'SELECT content, fingerprint, sline, eline FROM fp_postings WHERE content = ANY(?::int[]) AND fingerprint = ANY(?::bigint[])',
        \@ids, \@bfps
      )->hashes
    }
    )
  {
    push @{$regions{$p->{content}}}, [$p->{sline}, $p->{eline} - $p->{sline}, $p->{fingerprint}];    # [sline, span, fp]
  }
  my %cfps = map { $_->{content} => $_->{n} } @{
    $db->query(
      'SELECT content, count(DISTINCT fingerprint) AS n FROM fp_postings WHERE content = ANY(?::int[]) GROUP BY content',
      \@ids
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
      risk    => $lic->{$hash}{risk},                           # max license risk (Cavil's 1-9 scale), undef if none
      files   => $where,
      excerpt => $self->_excerpt($where->[0], $regions->[0]),
      marks   => $marks,                                        # per query fingerprint, in order: 1 aligned, 0 not
      aligned => $aligned,
      total   => scalar @$qfps,
      exact   => ($aligned == @$qfps ? true : false),           # Mojo::JSON booleans: correct in Perl and JSON

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
      ($where         ? (package          => $where->{name}, filename => $where->{filename}) : ()),
      ($decl->{$hash} ? (declared_license => $decl->{$hash})                                 : ())
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
