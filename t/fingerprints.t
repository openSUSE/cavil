# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Mojo::Base -strict, -signatures;

use FindBin;
use lib "$FindBin::Bin/lib";

use Test::More;
use Test::Mojo;
use Cavil::Test;
use Mojo::Date;
use Mojo::File qw(path tempfile);
use MCP::Client;

plan skip_all => 'set TEST_ONLINE to enable this test' unless $ENV{TEST_ONLINE};

my $cavil_test = Cavil::Test->new(online => $ENV{TEST_ONLINE}, schema => 'codesearch_test');

# Small k/w so the modest fixture files still winnow to fingerprints (production uses 4/8).
my %config = (%{$cavil_test->default_config}, codesearch => {enabled => 1, k => 3, w => 4});

# Config gate: with code search disabled the helpers are inert no matter what matcher is installed.
subtest 'disabled by config' => sub {
  my $off = Test::Mojo->new(Cavil => {%config, codesearch => {enabled => 0}});
  ok !$off->app->codesearch,   'codesearch helper is off';
  ok !$off->app->fingerprints, 'no fingerprints model';
};

my $t   = Test::Mojo->new(Cavil => \%config);
my $app = $t->app;
my $db  = $app->pg->db;
$cavil_test->mojo_fixtures($app);

subtest 'indexing records content hashes that ride the atomic promote' => sub {
  $app->minion->enqueue(unpack => [1]);
  $app->minion->perform_jobs;
  ok $db->query("SELECT count(*) FROM fp_files WHERE generation = 0")->array->[0] > 0, 'fp_files at generation 0';
  is $db->query("SELECT count(*) FROM fp_files WHERE generation <> 0")->array->[0], 0, 'nothing left mid-build';
  ok $db->query("SELECT count(*) FROM fp_contents")->array->[0] > 0, 'contents queued';
};

subtest 'a fingerprint build indexes the pending contents' => sub {

  # Indexing only records content; the scheduled fingerprint_build task fingerprints it, so it is pending here.
  ok $db->query('SELECT count(*) FROM fp_contents WHERE NOT indexed')->array->[0] > 0, 'contents await a build';

  # The task is self-contained: it also prunes content whose files are all gone (an orphan has no fp_files row).
  my $orphan = 'e' x 32;
  $db->query('INSERT INTO fp_contents (hash) VALUES (?)', $orphan);
  $app->minion->enqueue('fingerprint_build');
  $app->minion->perform_jobs;
  ok !$db->query('SELECT 1 FROM fp_contents WHERE hash = ?', $orphan)->rows, 'the build pruned an orphaned content';
  is $db->query('SELECT count(*) FROM fp_contents WHERE NOT indexed')->array->[0], 0, 'all contents built';
  ok $db->query('SELECT count(*) FROM fp_contents WHERE indexed')->array->[0] > 0, 'contents marked indexed';
  is $app->fingerprints->build_pending, 0, 'an explicit build is then a no-op';
};

subtest 'only one builder runs at a time, and the lock is released when it finishes' => sub {

  # A second builder alongside the first would duplicate every winnow and double the write load on the index
  # searches read. The task holds a lock it renews as it runs, so a build that outlives one TTL stays alone.
  my $held = $app->minion->lock('fingerprint_build', 3600);
  ok $held, 'the lock is free between builds (the previous build released it)';

  my $id = $app->minion->enqueue('fingerprint_build');
  $app->minion->perform_jobs;
  is $app->minion->job($id)->info->{result}, 'Fingerprint build already in progress', 'a second builder bows out';

  $app->minion->unlock('fingerprint_build');
  $app->minion->enqueue('fingerprint_build');
  $app->minion->perform_jobs;
  ok $app->minion->lock('fingerprint_build', 0), 'and the lock is free again once the build is done';
};

# Re-querying an indexed file with its own content must find that exact content at full containment. Pick a
# file that actually winnows to a few fingerprints (tiny files legitimately produce none).
my ($sample, $content);
for
  my $r (@{$db->query("SELECT DISTINCT ON (hash) package, filename, hash FROM fp_files WHERE generation = 0")->hashes})
{
  my $abs = $app->packages->pkg_checkout_dir($r->{package})->child('.unpacked', $r->{filename});
  next
    unless -f $abs && @{Cavil::Matcher::fingerprint_file("$abs", $config{codesearch}{k}, $config{codesearch}{w})} >= 3;
  ($sample, $content) = ($r, path($abs)->slurp);
  last;
}
ok $sample, 'found a fingerprintable file to query with' or BAIL_OUT('no fingerprintable fixture file');

# Every package name that carries the sample content, for the self-exclusion tests below.
my @sample_carriers = map { $_->{name} } @{
  $db->query(
    'SELECT DISTINCT p.name FROM fp_files ff JOIN bot_packages p ON p.id = ff.package
      WHERE ff.hash = ? AND ff.generation = 0 AND p.obsolete = false', $sample->{hash}
  )->hashes
};

subtest 'search finds an exact copy at full containment' => sub {
  my $matches = $app->fingerprints->search($content, 20)->{matches};
  ok @$matches, 'got matches';
  my ($self) = grep { $_->{hash} eq $sample->{hash} } @$matches;
  ok $self, 'the exact content is found';
  cmp_ok $self->{containment},    '>=', 0.99, 'query-direction containment is ~1.0';
  cmp_ok $self->{containment},    '<=', 1.0,  'and never exceeds 1.0';
  cmp_ok $self->{containment_of}, '>',  0,    'content-direction containment is set';
  cmp_ok $self->{containment_of}, '<=', 1.0,  'and never exceeds 1.0';
  ok +(grep { $_->{package} == $sample->{package} } @{$self->{files}}), 'resolves back to the source package';
  ok !defined $self->{risk} || $self->{risk} =~ /^\d+$/,                'risk, when known, is the numeric license risk';
  ok !(grep { $_->{containment} < 0.25 } @$matches), 'every returned match clears the containment floor';

  # A verbatim copy aligns every query fingerprint as one block.
  ok $self->{exact}, 'a verbatim copy is reported exact';
  is $self->{aligned},         $self->{total}, 'all query fingerprints align';
  is scalar @{$self->{marks}}, $self->{total}, 'one mark per query fingerprint';
  ok !(grep { $_ == 0 } @{$self->{marks}}), 'no fingerprint is marked as differing';
};

# The real paste is a fragment, not the whole file. Identical text can winnow to a slightly wider line span
# in the file than in the standalone fragment: this short, comment-heavy block spans 11 query lines but 14
# in the file, so a window sized to the query clipped its edge fingerprints and called a verbatim copy
# "modified" (regression). Extracted verbatim from perl-Mojolicious lib/Mojo/DOM/HTML.pm.
subtest 'a verbatim fragment that winnows wider in the file is still exact' => sub {
  my $fragment = <<'FRAGMENT';
sub _end {
  my ($end, $xml, $current) = @_;
  # Search stack for start tag
  my $next = $$current;
  do {
    # Ignore useless end tag
    return if $next->[0] eq 'root';
    # Right tag
    return $$current = $next->[3] if $next->[1] eq $end;
    # Phrasing content can only cross phrasing content
    return if !$xml && $PHRASING{$end} && !$PHRASING{$next->[1]};
  } while $next = $next->[3];
}
FRAGMENT
  my $matches = $app->fingerprints->search($fragment, 20)->{matches};
  my ($self) = grep { $_->{files}[0]{filename} =~ m!Mojo/DOM/HTML\.pm$! } @$matches;
  ok $self, 'the source file is found from the fragment' or return;
  cmp_ok $self->{containment}, '>=', 0.99, 'every fragment fingerprint is present in the file';
  ok $self->{exact}, 'and the verbatim fragment is reported exact';
  is $self->{aligned}, $self->{total}, 'every fingerprint of the fragment aligns';
  ok !(grep { $_ == 0 } @{$self->{marks}}), 'no fingerprint is marked as differing';
};

subtest 'a modified query is reported as not exact, with the changed fingerprints marked' => sub {
  my $noise  = join "\n", map {"zzqx_$_ wibble_$_ frobnicate_$_ grumble_$_"} 1 .. 8;    # absent from the source
  my ($self) = grep { $_->{hash} eq $sample->{hash} } @{$app->fingerprints->search("$noise\n$content", 20)->{matches}};
  ok $self,           'the source content is still found';
  ok !$self->{exact}, 'not exact: the added fingerprints are absent from the source';
  cmp_ok $self->{aligned}, '<', $self->{total}, 'fewer aligned than total';
  ok +(grep { $_ == 0 } @{$self->{marks}}), 'the differing fingerprints are marked';
  ok +(grep { $_ == 1 } @{$self->{marks}}), 'the copied part is marked aligned';
};

subtest 'a snippet too short to yield enough fingerprints is not searched' => sub {
  my $result = $app->fingerprints->search('one two three four five six seven eight');
  ok $result->{too_short}, 'flagged as too short to locate reliably';
  is scalar @{$result->{matches}}, 0, 'and returns no noisy matches';
};

subtest 'an unrelated snippet does not match the source (precision)' => sub {
  my $noise   = join "\n", map {"zzqx_$_ wibble_$_ frobnicate_$_ gr%^&umble_$_"} 1 .. 40;
  my $matches = $app->fingerprints->search($noise, 20)->{matches};
  ok !(grep { $_->{hash} eq $sample->{hash} } @$matches), 'the indexed file is not a false positive';
};

subtest 'obsolete packages are excluded (code search is non-obsolete only)' => sub {
  my $hash = $sample->{hash};
  my @pkgs = map { $_->{package} }
    @{$db->query('SELECT DISTINCT package FROM fp_files WHERE hash = ? AND generation = 0', $hash)->hashes};
  $db->query('UPDATE bot_packages SET obsolete = true WHERE id = ANY(?)', \@pkgs);
  my $matches = $app->fingerprints->search($content, 20)->{matches};
  ok !(grep { $_->{hash} eq $hash } @$matches), 'a content only in obsolete packages is hidden';

  $db->query('UPDATE bot_packages SET obsolete = false WHERE id = ANY(?)', \@pkgs);
  $matches = $app->fingerprints->search($content, 20)->{matches};
  ok +(grep { $_->{hash} eq $hash } @$matches), 'and shown again once a package is current';
};

subtest 'the MCP surface hides embargoed packages (web and API do not)' => sub {
  my $hash = $sample->{hash};
  $db->query('UPDATE bot_packages SET embargoed = true');
  ok !(grep { $_->{hash} eq $hash } @{$app->fingerprints->search($content, 20, 0, 1)->{matches}}),
    'embargoed content is hidden when excluded (MCP)';
  ok +(grep { $_->{hash} eq $hash } @{$app->fingerprints->search($content, 20)->{matches}}),
    'but shown by default (web and API)';
  $db->query('UPDATE bot_packages SET embargoed = false');
};

subtest 'file provenance links identical content in other current packages' => sub {

  # A second package is built from the same sources, so its files are byte-identical to the first's.
  $app->minion->enqueue(unpack => [2]);
  $app->minion->perform_jobs;

  my $prov = $app->fingerprints->file_provenance($sample->{package}, $sample->{filename});
  ok $prov, 'the file is reported as shared';
  cmp_ok $prov->{count}, '>=', 1, 'at least one other package carries it';
  ok +(grep { $_->{package} != $sample->{package} } @{$prov->{locations}}), 'and the other carrier is listed';

  # Non-obsolete only, same as search: obsolete carriers do not count.
  $db->query('UPDATE bot_packages SET obsolete = true WHERE id <> ?', $sample->{package});
  ok !$app->fingerprints->file_provenance($sample->{package}, $sample->{filename}),
    'a file whose only other carriers are obsolete reports no provenance';
  $db->query('UPDATE bot_packages SET obsolete = false');

  # A path that was never fingerprinted has none.
  ok !$app->fingerprints->file_provenance($sample->{package}, 'does/not/exist'), 'unknown file has no provenance';
};

subtest 'web search endpoint returns ranked matches' => sub {
  $t->get_ok('/login')->status_is(302);
  $t->post_ok('/code-search/query' => form => {snippet => $content})
    ->status_is(200)
    ->json_has('/matches/0/hash')
    ->json_has('/matches/0/containment')
    ->json_has('/matches/0/licenses');
};

subtest 'MCP tool is offered and returns results' => sub {
  $t->get_ok('/login')->status_is(302);
  my $expires = Mojo::Date->new(time + 36000)->to_datetime =~ s/:\d{2}Z$//r;
  $t->post_ok('/api_keys' => form => {expires => $expires, type => 'read-only', description => 'fp'})->status_is(200);
  $t->get_ok('/api_keys/meta')->status_is(200);
  my $key = $t->tx->res->json('/keys/0/api_key');
  $t->ua->on(start => sub ($ua, $tx) { $tx->req->headers->authorization("Bearer $key") });

  my $client = MCP::Client->new(ua => $t->ua, url => $t->ua->server->url->path('/mcp'));
  $client->can('discover') ? $client->discover : $client->initialize_session;    # MCP 0.15 / 0.12 handshake
  my $tools = $client->list_tools;
  ok +(grep { $_->{name} eq 'cavil_code_search' } @{$tools->{tools}}), 'tool listed when code search is on';
  my $res = $client->call_tool('cavil_code_search', {snippet => $content});
  like $res->{content}[0]{text}, qr/Code search/, 'tool returns a result block';
};

subtest 'HTTP API endpoint returns ranked matches' => sub {

  # The api_key Bearer header set in the MCP subtest still applies to $t->ua.
  $t->post_ok('/api/v1/code/search' => form => {snippet => $content})
    ->status_is(200)
    ->json_has('/matches/0/hash')
    ->json_has('/total');
};

subtest 'the CLI API endpoints (config, known-hash, batch fingerprint search)' => sub {

  # The api_key Bearer header set in the MCP subtest still applies to $t->ua.

  # config exposes the winnowing parameters the client must match.
  $t->get_ok('/api/v1/code/config')
    ->status_is(200)
    ->json_is('/k' => $config{codesearch}{k})
    ->json_is('/w' => $config{codesearch}{w})
    ->json_has('/generation')
    ->json_has('/max_fingerprints');

  # known-hash recognition: an indexed hash comes back with licenses/risk and a carrying package/path, an
  # unindexed one is absent.
  my $bogus = 'a' x 32;
  $t->post_ok('/api/v1/code/known' => json => {hashes => [$sample->{hash}, $bogus]})
    ->status_is(200)
    ->json_has("/$sample->{hash}")
    ->json_has("/$sample->{hash}/package")
    ->json_has("/$sample->{hash}/filename")
    ->json_hasnt("/$bogus");

  # exclude_packages flows through the endpoint: excluding every carrier makes the sample unknown.
  $t->post_ok('/api/v1/code/known' => json => {hashes => [$sample->{hash}], exclude_packages => \@sample_carriers})
    ->status_is(200)
    ->json_hasnt("/$sample->{hash}");

  # batch fingerprint search: winnow the sample content the way the server would, send the deduped
  # fingerprints as decimal strings with the query's line span, and find the sample among the matches.
  my $tmp = tempfile;
  $tmp->spew($content);
  my $raw = Cavil::Matcher::fingerprint_file($tmp->to_string, $config{codesearch}{k}, $config{codesearch}{w});
  my %seen;
  my @fps = grep { !$seen{$_}++ } map {"$_->[0]"} @$raw;
  my ($lo, $hi);
  for my $r (@$raw) {
    $lo = $r->[1] if !defined $lo || $r->[1] < $lo;
    $hi = $r->[2] if !defined $hi || $r->[2] > $hi;
  }
  $t->post_ok(
    '/api/v1/code/search-batch' => json => {queries => [{id => 'q1', fingerprints => \@fps, span => $hi - $lo + 1}]})
    ->status_is(200)
    ->json_is('/results/0/id' => 'q1')
    ->json_has('/results/0/matches/0/hash');
  my $matches = $t->tx->res->json('/results/0/matches');
  ok +(grep { $_->{hash} eq $sample->{hash} } @$matches), 'the batch query finds the sample content';

  # A query below the fingerprint floor is reported too short, not as noise.
  $t->post_ok(
    '/api/v1/code/search-batch' => json => {queries => [{id => 'tiny', fingerprints => ['1', '2'], span => 2}]})
    ->status_is(200)
    ->json_has('/results/0/too_short')
    ->json_is('/results/0/matches' => []);

  # Schema validation rejects malformed bodies with a 400 instead of a crash or garbage.
  $t->post_ok('/api/v1/code/known'        => json => {hashes  => [{}]})->status_is(400);
  $t->post_ok('/api/v1/code/known'        => json => {nope    => 1})->status_is(400);
  $t->post_ok('/api/v1/code/search-batch' => json => {queries => ['not-an-object']})->status_is(400);
};

subtest 'catch_all patterns are noise, excluded from the reported licenses and risk' => sub {

  # Wire both a concrete and a catch_all license pattern onto the sample's file, then confirm only the concrete
  # one surfaces. catch_all patterns match generic boilerplate (a specfile's shape, a copyright phrase) and must
  # never masquerade as the file's license, or the real one drowns in "Any openSUSE specfile, Any ..." noise.
  my $mf = $db->insert(
    'matched_files',
    {package   => $sample->{package}, filename => $sample->{filename}, mimetype => 'text/plain'},
    {returning => 'id'}
  )->hash->{id};
  my $concrete = $db->insert(
    'license_patterns',
    {pattern   => 'concrete pattern text', token_hexsum => '1' x 32, license => 'Test-Concrete-1.0', risk => 3},
    {returning => 'id'}
  )->hash->{id};
  my $catchall = $db->insert(
    'license_patterns',
    {
      pattern      => 'catch_all pattern text',
      token_hexsum => '2' x 32,
      license      => 'Any test boilerplate',
      risk         => 9,
      catch_all    => 1
    },
    {returning => 'id'}
  )->hash->{id};
  $db->insert('pattern_matches', {file => $mf, pattern => $_, sline => 1, eline => 1, package => $sample->{package}})
    for $concrete, $catchall;

  my $known = $app->fingerprints->known_hashes([$sample->{hash}])->{$sample->{hash}};
  ok +(grep { $_ eq 'Test-Concrete-1.0' } @{$known->{licenses}}),    'the concrete license is reported';
  ok !(grep { $_ eq 'Any test boilerplate' } @{$known->{licenses}}), 'the catch_all pattern is excluded';
  cmp_ok $known->{risk}, '<', 9, 'and its risk does not count towards the max either';
};

subtest 'a match on non-vendored source carries the carrier declared license' => sub {
  my $hash = $sample->{hash};
  ok !Cavil::ReportUtil::is_vendored_path($sample->{filename}),
    'the sample file is the package own source, not vendored';

  # Give every carrier of the content a known declared license, so whichever non-vendored carrier is picked
  # returns it.
  $db->query(
    'UPDATE bot_reports SET declared_license = ? WHERE package IN
       (SELECT DISTINCT package FROM fp_files WHERE hash = ? AND generation = 0)', 'Sentinel-1.0', $hash
  );

  is $app->fingerprints->known_hashes([$hash])->{$hash}{declared_license}, 'Sentinel-1.0',
    'recognition carries the declared license alongside the per-file licenses';

  my $tmp = tempfile;
  $tmp->spew($content);
  my $raw = Cavil::Matcher::fingerprint_file($tmp->to_string, $config{codesearch}{k}, $config{codesearch}{w});
  my %seen;
  my @qfps   = grep { !$seen{$_}++ } map { $_->[0] } @$raw;
  my ($self) = grep { $_->{hash} eq $hash } @{$app->fingerprints->search_fingerprints(\@qfps, 1, 20)->{matches}};
  is $self->{declared_license}, 'Sentinel-1.0', 'and a search match carries it too';

  # With nothing declared, the field is simply absent (per-file licenses still stand).
  $db->query(
    'UPDATE bot_reports SET declared_license = NULL WHERE package IN
       (SELECT DISTINCT package FROM fp_files WHERE hash = ? AND generation = 0)', $hash
  );
  ok !exists $app->fingerprints->known_hashes([$hash])->{$hash}{declared_license},
    'no declared license means the field is omitted, not null-filled';
};

subtest 'exclude_packages suppresses a content carried only by an excluded package (self-match)' => sub {
  my $hash = $sample->{hash};
  ok @sample_carriers, 'the sample content has at least one carrier';

  ok $app->fingerprints->known_hashes([$hash])->{$hash}, 'recognized with no exclusion';
  ok $app->fingerprints->known_hashes([$hash], 0, ['definitely-not-a-package'])->{$hash},
    'excluding an unrelated package changes nothing';
  ok !$app->fingerprints->known_hashes([$hash], 0, \@sample_carriers)->{$hash},
    'excluding every carrier makes the content unknown, so a working copy stops matching itself';

  # And the same filter reaches the batch search: excluding every carrier drops the sample from the matches.
  my $tmp = tempfile;
  $tmp->spew($content);
  my $raw = Cavil::Matcher::fingerprint_file($tmp->to_string, $config{codesearch}{k}, $config{codesearch}{w});
  my %seen;
  my @qfps    = grep { !$seen{$_}++ } map { $_->[0] } @$raw;
  my $matches = $app->fingerprints->search_fingerprints(\@qfps, 1, 20, 0, 0, \@sample_carriers)->{matches};
  ok !(grep { $_->{hash} eq $hash } @$matches), 'search excludes the self-match too';
};

subtest 'the CLI API endpoints are gated on code search being enabled' => sub {
  my $toff = Test::Mojo->new(Cavil => {%config, codesearch => {enabled => 0}});
  $toff->get_ok('/login')->status_is(302);
  my $expires = Mojo::Date->new(time + 36000)->to_datetime =~ s/:\d{2}Z$//r;
  $toff->post_ok('/api_keys' => form => {expires => $expires, type => 'read-only', description => 'off'})
    ->status_is(200);
  $toff->get_ok('/api_keys/meta')->status_is(200);
  my $key = $toff->tx->res->json('/keys/0/api_key');
  $toff->ua->on(start => sub ($ua, $tx) { $tx->req->headers->authorization("Bearer $key") });

  # Authenticated, but the instance has code search off: the endpoints report that, they do not 403.
  $toff->get_ok('/api/v1/code/config')->status_is(404);
  $toff->post_ok('/api/v1/code/known' => json => {hashes => ['a' x 32]})->status_is(404);
};

subtest 'search page renders behind login' => sub {
  $t->get_ok('/code-search')->status_is(200)->content_like(qr/id="code-search"/);
};

subtest 'the fingerprint command queues a rebuild that a worker runs' => sub {
  require Cavil::Command::fingerprint;
  my $out = '';
  {
    open my $capture, '>', \$out;
    local *STDOUT = $capture;
    Cavil::Command::fingerprint->new(app => $app)->run('--rebuild');
  }
  like $out, qr/Queued .* job \d+ \(rebuild\)/, 'command enqueues a rebuild job instead of doing the work inline';

  $app->minion->perform_jobs;    # the worker discards the index and rebuilds, no database surgery
  is $db->query('SELECT count(*) FROM fp_contents WHERE NOT indexed')->array->[0], 0, 'nothing left pending';
  my $matches = $app->fingerprints->search($content, 20)->{matches};
  ok +(grep { $_->{hash} eq $sample->{hash} } @$matches), 'content is searchable again after the rebuild';
};

subtest 'cleanup prunes content bookkeeping with no files left' => sub {

  # An orphan is a fp_contents row whose files are all gone (obsolete cleanup removes fp_files, not
  # fp_contents); a hash that no fp_files references models exactly that.
  my $orphan = 'f' x 32;
  $db->query('INSERT INTO fp_contents (hash, indexed) VALUES (?, true)', $orphan);
  my $kept = $db->query('SELECT hash FROM fp_files WHERE generation = 0 LIMIT 1')->array->[0];

  ok $app->fingerprints->prune_contents >= 1, 'prune removes orphaned content rows';
  ok !$db->query('SELECT 1 FROM fp_contents WHERE hash = ?', $orphan)->rows, 'the orphan is gone';
  ok $db->query('SELECT 1 FROM fp_contents WHERE hash = ?',  $kept)->rows,   'referenced content is kept';
};

subtest 'refresh_stopwords records a ubiquitous fingerprint, and the query prunes it' => sub {

  # Pick a cap above every real fingerprint's document frequency, then seed one synthetic fingerprint above it.
  my $maxdf = $db->query(
    'SELECT COALESCE(max(df), 0) FROM
       (SELECT count(*) df FROM fp_contents c, unnest(c.fingerprints) fp WHERE c.indexed GROUP BY fp) s'
  )->array->[0];
  my $cap    = $maxdf + 2;
  my $common = 4242424242;
  my @ids;
  for (1 .. $cap + 3) {
    push @ids, $db->query(
      'INSERT INTO fp_contents (hash, indexed, fingerprints, slines, elines)
         VALUES (?, true, ?::bigint[], ?::int[], ?::int[]) RETURNING id', "stopword-$_", [$common], [1], [1]
    )->array->[0];
  }

  # A real fingerprint (DF <= cap) to prove only the over-cap one becomes a stopword.
  my $real
    = $db->query('SELECT fp FROM fp_contents c, unnest(c.fingerprints) fp WHERE fp <> ? LIMIT 1', $common)->array->[0];

  $app->fingerprints->refresh_stopwords($cap);

  ok $db->query('SELECT 1 FROM fp_stopwords WHERE fingerprint = ?', $common)->rows,
    'the over-cap fingerprint became a stopword';
  ok !$db->query('SELECT 1 FROM fp_stopwords WHERE fingerprint = ?', $real)->rows,
    'a below-cap fingerprint is left alone';

  # It stays in the arrays (GIN compresses it away) but is dropped from the query, so the contents that carry only
  # it are never dragged into the candidate set: a query of the sample plus the stopword still finds the sample and
  # none of the stopword-only contents.
  my $stored  = $db->query('SELECT fingerprints FROM fp_contents WHERE hash = ?', $sample->{hash})->array->[0];
  my $matches = $app->fingerprints->search_fingerprints([@$stored, $common], 1, 50)->{matches};
  ok +(grep { $_->{hash} eq $sample->{hash} } @$matches), 'the real content is still found';
  ok !(grep { $_->{hash} =~ /^stopword-/ } @$matches),    'a content sharing only the stopword is not pulled in';

  $db->query('DELETE FROM fp_contents WHERE id = ANY(?)',      \@ids);
  $db->query('DELETE FROM fp_stopwords WHERE fingerprint = ?', $common);
};

subtest 'a query for fingerprints absent from the index returns nothing, fast' => sub {
  my @absent = map {"90000000000000000$_"} 1 .. 12;                    # distinctive values that cannot be in the corpus
  my $result = $app->fingerprints->search_fingerprints(\@absent, 1);
  is scalar @{$result->{matches}}, 0, 'no matches';
  is $result->{total},             0, 'and a zero total';
};

subtest 'generation advances on each build so clients drop stale caches' => sub {
  my $g0 = $app->fingerprints->generation;
  $app->fingerprints->bump_generation;
  is $app->fingerprints->generation, $g0 + 1, 'generation is bumped';
};

subtest 'the build stores one array entry per distinct fingerprint, at its first position' => sub {
  my $id
    = $db->query('INSERT INTO fp_contents (hash, indexed) VALUES (?, false) RETURNING id', 'store-arrays')->array->[0];
  $app->fingerprints->_store_arrays($db, $id, [[111, 1, 1], [222, 2, 5], [111, 3, 3]]);

  my $row = $db->query('SELECT fingerprints, slines, elines, indexed FROM fp_contents WHERE id = ?', $id)->hash;
  is_deeply $row->{fingerprints},
    [Cavil::Model::Fingerprints::_fp_bigint(111), Cavil::Model::Fingerprints::_fp_bigint(222)],
    'each distinct fingerprint is stored once, in first-seen order (the repeat is dropped)';
  is_deeply $row->{slines}, [1, 2], 'with the start line of its first occurrence';
  is_deeply $row->{elines}, [1, 5], 'and the matching end line';
  ok $row->{indexed}, 'and the content is marked indexed';

  $db->query('DELETE FROM fp_contents WHERE id = ?', $id);
};

subtest 'a pathologically large content is capped to max_fingerprints' => sub {
  my $fp   = $app->fingerprints;
  my $prev = $fp->max_fingerprints;
  $fp->max_fingerprints(2);
  my $id
    = $db->query('INSERT INTO fp_contents (hash, indexed) VALUES (?, false) RETURNING id', 'cap-arrays')->array->[0];
  $fp->_store_arrays($db, $id, [[10, 1, 1], [20, 2, 2], [30, 3, 3], [40, 4, 4]]);

  my $row = $db->query('SELECT fingerprints, slines, elines FROM fp_contents WHERE id = ?', $id)->hash;
  is scalar @{$row->{fingerprints}}, 2, 'only the first max_fingerprints are stored';
  is_deeply $row->{fingerprints},
    [Cavil::Model::Fingerprints::_fp_bigint(10), Cavil::Model::Fingerprints::_fp_bigint(20)],
    'keeping the earliest in file order';
  is_deeply $row->{slines}, [1, 2], 'positions are truncated in step';
  is_deeply $row->{elines}, [1, 2], 'both position arrays stay aligned';

  $fp->max_fingerprints($prev);
  $db->query('DELETE FROM fp_contents WHERE id = ?', $id);
};

subtest 'an oversized query is capped to max_fingerprints' => sub {
  my $tmp = tempfile;
  $tmp->spew($content);
  my $raw = Cavil::Matcher::fingerprint_file($tmp->to_string, $config{codesearch}{k}, $config{codesearch}{w});
  my %seen;
  my @qfps = grep { !$seen{$_}++ } map { $_->[0] } @$raw;
  return unless @qfps >= 9;    # need more than the floor so a cap below the query size still searches

  my $fp   = $app->fingerprints;
  my $prev = $fp->max_fingerprints;
  my $cap  = $#qfps;                  # one below the query size, so the cap actually bites
  $fp->max_fingerprints($cap);

  my ($self) = grep { $_->{hash} eq $sample->{hash} } @{$fp->search_fingerprints(\@qfps, 1, 20)->{matches}};
  ok $self, 'still finds the sample from the capped query';
  is $self->{total},           $cap, 'total reflects the capped query size, not the original';
  is scalar @{$self->{marks}}, $cap, 'one mark per capped fingerprint';

  $fp->max_fingerprints($prev);
};

subtest 'fingerprints reinterpret uint64 to signed bigint losslessly and bijectively' => sub {
  is Cavil::Model::Fingerprints::_fp_bigint(5),                       5, 'a small value is unchanged';
  is Cavil::Model::Fingerprints::_fp_bigint('18446744073709551615'), -1, 'the top uint64 maps to -1';
  is Cavil::Model::Fingerprints::_fp_bigint('9223372036854775808'), '-9223372036854775808',
    '2^63 maps to the min int64';
  isnt Cavil::Model::Fingerprints::_fp_bigint('9223372036854775808'),
    Cavil::Model::Fingerprints::_fp_bigint('9223372036854775809'), 'adjacent values stay distinct';
};

done_testing;
