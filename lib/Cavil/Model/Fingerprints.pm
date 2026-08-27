# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later
#
# The fingerprint index for snippet code search. The winnowed fingerprints live in an on-disk segment
# store (Cavil::Matcher::FpIndex); this model keeps the database side: fp_files maps a content hash to the
# packages/paths that carry it (generation-tracked, so it rides the report's atomic promote), and
# fp_contents is the global "which contents are already fingerprinted" oracle. Only used when code search is
# enabled (see Cavil::codesearch).

package Cavil::Model::Fingerprints;
use Mojo::Base -base, -signatures;

use Cavil::PatternEngine;
use Cavil::Util qw(checkout_path);
use Mojo::File  qw(path tempfile);
use Mojo::JSON  qw(false true);

has [qw(pg log checkout_dir index_dir)];
has k => 4;
has w => 8;

# Lines of context shown around a matched region in a result preview.
use constant EXCERPT_CONTEXT => 3;

# Loaded lazily so instances that never search (code search off) don't pay for the on-disk index store.
sub _index ($self) {
  require Cavil::Matcher::FpIndex;
  return $self->{index} //= Cavil::Matcher::FpIndex->new(dir => $self->index_dir, k => $self->k, w => $self->w);
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

# Delete the on-disk index so the next build starts fresh (used to change k/w or force a full rebuild).
# The database is left untouched; resync/build_pending requeue and repopulate. Contents are removed rather
# than the directory itself, and the cached handle is dropped so the next use recreates the index with the
# current k/w.
sub wipe ($self) {
  my $dir = path($self->index_dir);
  $dir->list({hidden => 1})->each(sub { $_->remove }) if -d $dir;
  delete $self->{index};
}

# Keep the "already fingerprinted" bookkeeping honest with the on-disk index. If the segment store was
# wiped (the supported way to change k/w or force a rebuild), it has no segments while the database still
# marks contents as indexed; requeue them so a plain rebuild needs no manual database surgery. A no-op once
# the index has any segments, so it is safe to call before every build.
sub resync ($self) {
  return if $self->_index->generation > 0;
  $self->pg->db->query("UPDATE fp_contents SET state = 'pending' WHERE state <> 'pending'");
}

# Fingerprint up to $limit not-yet-indexed contents into one new segment. Returns the number fingerprinted.
# One representative file per content is enough (all copies share the bytes); FpIndex::add_segment dedups
# and appends without touching existing segments.
sub build_pending ($self, $limit = 20000) {
  my $rows = $self->pg->db->query(
    "SELECT c.hash, p.name, p.checkout_dir AS co, f.filename
       FROM fp_contents c
       JOIN LATERAL (
         SELECT package, filename FROM fp_files WHERE hash = c.hash AND generation = 0 LIMIT 1
       ) f ON true
       JOIN bot_packages p ON p.id = f.package
      WHERE c.state = 'pending'
      LIMIT ?", $limit
  )->hashes;
  return 0 unless @$rows;

  my @paths
    = map { checkout_path($self->checkout_dir, $_->{name}, $_->{co}, '.unpacked', $_->{filename})->to_string } @$rows;
  $self->_index->add_segment(\@paths);

  my @hashes = map { $_->{hash} } @$rows;
  $self->pg->db->query("UPDATE fp_contents SET state = 'indexed' WHERE hash = ANY(?)", \@hashes);
  return scalar @hashes;
}

# Drop content bookkeeping for hashes no file references any more (their packages went obsolete or were
# reindexed away). fp_files is pruned by the promote and obsolete cleanup, so without this fp_contents would
# only ever grow. Called from the daily cleanup; segment space is reclaimed separately by a full rebuild.
# ponytail: one anti-join over fp_files, fine for a daily maintenance pass.
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
sub search_fingerprints ($self, $qfps, $qspan, $limit = 10, $offset = 0, $exclude_embargoed = 0) {

  # Too few distinct fingerprints to search on (see MIN_QUERY_FINGERPRINTS); say so rather than return noise.
  # No token-count guidance: the real floor is distinct fingerprints, which repetitive code reaches far later.
  return {matches => [], total => 0, too_short => \1} if @$qfps < MIN_QUERY_FINGERPRINTS;

  # Rank all in memory, enrich only the page: licenses and excerpts are the cost, so paging stays a few reads.
  my $all = $self->_index->search($qfps, 0);

  # Drop obsolete (and embargoed when asked) carriers before paging: segments are append-only, so a content
  # can outlive its files, and filtering here keeps offset and total consistent.
  my %live = map { $_ => 1 } @{$self->_live_hashes([map { $_->[0] } @$all], $exclude_embargoed)};
  @$all = grep { $live{$_->[0]} } @$all;

  # Keep only real resemblance, then order strongest first (containment, then how much of the file matched,
  # so the file the snippet mostly *is* outranks one that merely embeds it).
  @$all = sort { $b->[2] <=> $a->[2] || $b->[3] <=> $a->[3] } grep { $_->[2] >= MIN_CONTAINMENT } @$all;

  my $total = scalar @$all;
  return {matches => [], total => $total} if $offset >= $total;
  my $end = $offset + $limit - 1;
  $end = $#$all if $end > $#$all;
  my @page = @$all[$offset .. $end];

  my @hashes = map { $_->[0] } @page;
  my $lic    = $self->_licenses_by_hash(\@hashes, $exclude_embargoed);
  my $locs   = $self->_locations_by_hash(\@hashes, $exclude_embargoed);

  my @matches;
  for my $h (@page) {
    my ($hash, undef, $containment, $containment_of, $regions) = @$h;    # [hash, hits, containment, of, regions]
    my $where = $locs->{$hash} // [];
    my ($marks, $aligned) = _alignment($regions, $qfps, $qspan);
    push @matches, {
      hash           => $hash,
      containment    => $containment,
      containment_of => $containment_of,
      licenses       => $lic->{$hash}{licenses} // [],
      risk           => $lic->{$hash}{risk},             # max license risk (Cavil's 1-9 scale), undef if none
      files          => $where,
      excerpt        => $self->_excerpt($where->[0], $regions->[0]),
      marks          => $marks,                                      # per query fingerprint, in order: 1 aligned, 0 not
      aligned        => $aligned,
      total          => scalar @$qfps,
      exact          => ($aligned == @$qfps ? true : false)          # Mojo::JSON booleans: correct in Perl and JSON
    };
  }
  return {matches => \@matches, total => $total};
}

# Batch content-hash lookup for the CLI: for each hash Cavil has seen, its licenses and max risk. A hash the
# instance knows but has no license match for still returns an entry (empty licenses, undef risk), so the
# caller can tell "known, no license detected" from "never seen" (which is absent from the result).
sub known_hashes ($self, $hashes, $exclude_embargoed = 0) {
  return {} unless @$hashes;
  my $live = $self->_live_hashes($hashes, $exclude_embargoed);
  return {} unless @$live;
  my $lic = $self->_licenses_by_hash($live, $exclude_embargoed);
  return {map { $_ => {licenses => $lic->{$_}{licenses} // [], risk => $lic->{$_}{risk}} } @$live};
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
# ponytail: excludes the current package by id, so another current version of it can still list; rare once
# obsolete versions are filtered. Tighten to name if that gets noisy.
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
sub _licenses_by_hash ($self, $hashes, $exclude_embargoed = 0) {
  my $emb = $exclude_embargoed ? ' AND p.embargoed = false' : '';
  my %info;
  my $rows = $self->pg->db->query(
    "SELECT ff.hash, array_agg(DISTINCT lp.license) AS licenses, max(lp.risk) AS risk
       FROM fp_files ff
       JOIN bot_packages p ON p.id = ff.package AND p.obsolete = false$emb
       JOIN matched_files mf ON mf.package = ff.package AND mf.filename = ff.filename AND mf.generation = 0
       JOIN pattern_matches pm ON pm.file = mf.id AND pm.ignored = false
       JOIN license_patterns lp ON lp.id = pm.pattern AND lp.license <> ''
      WHERE ff.hash = ANY(?) AND ff.generation = 0
      GROUP BY ff.hash", $hashes
  )->hashes;
  $info{$_->{hash}} = {risk => $_->{risk}, licenses => $_->{licenses}} for @$rows;
  return \%info;
}

# Which packages/paths carry each matched content (capped per content; the full expansion is available on
# demand). This is the "found in" list, and dedup means one content lists every version that ships it.
sub _locations_by_hash ($self, $hashes, $exclude_embargoed = 0) {
  my $emb = $exclude_embargoed ? ' AND p.embargoed = false' : '';
  my %locs;
  my $rows = $self->pg->db->query(
    "SELECT ff.hash, p.name, p.id AS package, ff.filename
       FROM fp_files ff JOIN bot_packages p ON p.id = ff.package
      WHERE ff.hash = ANY(?) AND ff.generation = 0 AND p.obsolete = false$emb
      ORDER BY p.name", $hashes
  )->hashes;
  for my $r (@$rows) {
    my $list = $locs{$r->{hash}} //= [];
    push @$list, {package => $r->{package}, name => $r->{name}, filename => $r->{filename}} if @$list < 25;
  }
  return \%locs;
}

# Of the given hashes, those in a visible package: never obsolete, and never embargoed when asked.
# ponytail: one indexed query over the whole candidate set; chunk it if a common snippet makes it too large.
sub _live_hashes ($self, $hashes, $exclude_embargoed = 0) {
  return [] unless @$hashes;
  my $emb  = $exclude_embargoed ? ' AND p.embargoed = false' : '';
  my $rows = $self->pg->db->query(
    "SELECT DISTINCT ff.hash
       FROM fp_files ff JOIN bot_packages p ON p.id = ff.package
      WHERE ff.hash = ANY(?) AND ff.generation = 0 AND p.obsolete = false$emb", $hashes
  )->hashes;
  return [map { $_->{hash} } @$rows];
}

1;
