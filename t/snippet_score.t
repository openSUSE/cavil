# SPDX-FileCopyrightText: 2026 SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Mojo::Base -strict, -signatures;

use FindBin;
use lib "$FindBin::Bin/lib";

use Test::More;
use Test::Mojo;
use Cavil::Test;
use Cavil::Util qw(SNIPPET_SCORE_VERSION);
use Spooky::Patterns::XS;

plan skip_all => 'set TEST_ONLINE to enable this test' unless $ENV{TEST_ONLINE};

# Build a package (id 1) with real matched_files, then drive snippets through the scorer directly.
my $cavil_test = Cavil::Test->new(online => $ENV{TEST_ONLINE}, schema => 'snippet_score_test');
my $t          = Test::Mojo->new(Cavil => $cavil_test->default_config);
my $app        = $t->app;
$cavil_test->package_with_snippets_fixtures($app);
$app->minion->enqueue(unpack => [1]);
$app->minion->perform_jobs;
my $db       = $app->pg->db;
my $patterns = $app->patterns;

# The similarity tables are maintained incrementally as patterns are created (sync_pattern_shingles +
# triggers), so the fixtures above already populated them - no separate build step. The required-phrase
# gate only fires a confident match when a shingle is distinctive (IDF >= 4), which needs a realistic
# number of licenses in the corpus; the fixture has a handful, so seed enough padding licenses that the
# *production* gate (not a relaxed one) can accept the deterministic fragments below.
$patterns->create(pattern => "seed padding license number $_ alpha beta gamma delta", license => "Seed-Padding-$_")
  for 1 .. 45;

# A pattern whose text we can reuse verbatim as a snippet body for a deterministic match.
my $gfdl = $db->query("SELECT id, pattern FROM license_patterns WHERE license = 'GFDL-1.1-or-later' LIMIT 1")->hash;
my $file = $db->query('SELECT id FROM matched_files WHERE package = 1 LIMIT 1')->hash->{id};

# Add an occurrence with an explicit snippet body, starting unscored (score_version 0).
my $n           = 0;
my $add_snippet = sub (%o) {
  $n++;
  my $sid = $db->insert(
    'snippets',
    {hash      => "score-$n", text => $o{text}, package => 1, score_version => 0, like_pattern => $o{like_pattern}},
    {returning => 'id'}
  )->hash->{id};
  $db->insert('file_snippets', {package => 1, file => $file, snippet => $sid, sline => $n * 10, eline => $n * 10 + 4});
  return $sid;
};

subtest 'score_snippets: batched winner, likelyness and closest pattern' => sub {

  # score_snippets reads only the pattern tables, so it can score ad-hoc rows (no snippet insert needed).
  my $scores = $patterns->score_snippets([{id => 101, text => $gfdl->{pattern}}]);
  my $scored = $scores->{101};
  is $scored->{score_version}, SNIPPET_SCORE_VERSION, 'stamps the current score version';
  is $scored->{like_pattern},  $gfdl->{id},           'attributes the snippet to the matching license pattern';
  ok $scored->{likelyness} > 0.5, 'with a healthy similarity';

  # Gibberish shares no distinctive shingle with any license: no confident winner, but still stamped.
  my $miss = $patterns->score_snippets([{id => 102, text => 'zzq wxq vkq jpq flq'}])->{102};
  is $miss->{likelyness},    0,                     'gibberish gets no confident match';
  is $miss->{like_pattern},  undef,                 'and no attributed pattern';
  is $miss->{score_version}, SNIPPET_SCORE_VERSION, 'but is still stamped current (so it is not rescored forever)';

  # A whole batch is scored from one working-set load; each row keyed by its id.
  my $batch = $patterns->score_snippets([{id => 201, text => $gfdl->{pattern}}, {id => 202, text => 'nothing here'}]);
  is $batch->{201}{like_pattern}, $gfdl->{id}, 'first row matches';
  is $batch->{202}{likelyness},   0,           'second row does not';
};

subtest 'score_snippets: closest pattern within the license carries the right risk' => sub {

  # Two members of one license at different risk and with disjoint wording; the license pick is by the
  # combined signature, but the attributed pattern must be the closest *member*, not an arbitrary one.
  my $low = $app->patterns->create(
    pattern => 'alpha bravo charlie delta echo foxtrot golf',
    license => 'GrabBag-Test',
    risk    => 0
  );
  my $high = $app->patterns->create(
    pattern => 'november oscar papa quebec romeo sierra tango',
    license => 'GrabBag-Test',
    risk    => 5
  );
  my $risk_of = sub ($id) { $db->select('license_patterns', 'risk', {id => $id})->hash->{risk} };

  my $hi = $patterns->score_snippets([{id => 301, text => 'november oscar papa quebec romeo sierra tango'}])->{301};
  is $hi->{like_pattern},             $high->{id}, 'a snippet matching the high-risk member is attributed to it';
  isnt $hi->{like_pattern},           $low->{id},  'not the other (arbitrary) member of the same license';
  is $risk_of->($hi->{like_pattern}), 5,           'so the stored pattern carries the right (high) risk';

  my $lo = $patterns->score_snippets([{id => 302, text => 'alpha bravo charlie delta echo foxtrot golf'}])->{302};
  is $lo->{like_pattern},             $low->{id}, 'a snippet matching the low-risk member is attributed to it';
  is $risk_of->($lo->{like_pattern}), 0,          'with the right (low) risk';
};

subtest 'bag_score: bootstrapping fallback stamps version 0' => sub {
  my $bag  = Spooky::Patterns::XS::init_bag_of_patterns;
  my %pats = map { $_->{id} => $_->{pattern} } @{$db->select('license_patterns', 'id,pattern')->hashes->to_array};
  $bag->set_patterns(\%pats);

  my $fallback = $patterns->bag_score($bag, $gfdl->{pattern});
  is $fallback->{score_version}, 0, 'bag fallback stamps version 0 so fold-in will not trust it';
  ok $fallback->{like_pattern}, 'but still records a closest pattern';
};

subtest 'score_package_snippets: scores stale, skips current, re-scores stuck rows' => sub {
  my $stale = $add_snippet->(text => $gfdl->{pattern});    # version 0, no like_pattern yet

  # The stuck-snippet bug: classified before the tables were populated -> version 0 but like_pattern
  # already set. Scoping by score_version (not "like_pattern IS NULL") must re-score it.
  my $stuck = $add_snippet->(text => $gfdl->{pattern}, like_pattern => $gfdl->{id});

  # A snippet already at the current version must be left untouched.
  my $fresh = $add_snippet->(text => $gfdl->{pattern});
  $db->update('snippets', {score_version => SNIPPET_SCORE_VERSION}, {id => $fresh});

  $patterns->score_package_snippets(1);

  my $row = sub ($id) { $db->select('snippets', ['score_version', 'like_pattern'], {id => $id})->hash };
  is $row->($stale)->{score_version}, SNIPPET_SCORE_VERSION, 'a stale (version 0) snippet is scored to current';
  is $row->($stale)->{like_pattern},  $gfdl->{id},           'and attributed end-to-end through the package flow';
  is $row->($stuck)->{score_version}, SNIPPET_SCORE_VERSION, 'a stuck version-0 row with a like_pattern is re-scored';
  is $row->($fresh)->{score_version}, SNIPPET_SCORE_VERSION, 'a current-version snippet is skipped (kept current)';
};

subtest 'score_package_snippets: scoped to the package, no-op without similarity data' => sub {
  my $ct = Cavil::Test->new(online => $ENV{TEST_ONLINE}, schema => 'snippet_score_nosig_test');
  my $tt = Test::Mojo->new(Cavil => $ct->default_config);
  my $a  = $tt->app;
  $ct->package_with_snippets_fixtures($a);
  $a->minion->enqueue(unpack => [1]);
  $a->minion->perform_jobs;
  my $d = $a->pg->db;

  # Emptying pattern_shingles cascades through the triggers to shingle_license, so the scorer sees no
  # data at all - the bootstrapping state, before the backfill has run.
  $d->query('DELETE FROM pattern_shingles');
  ok !$d->query('SELECT 1 FROM shingle_license LIMIT 1')->rows, 'no similarity data once the tables are cleared';

  my $f   = $d->query('SELECT id FROM matched_files WHERE package = 1 LIMIT 1')->hash->{id};
  my $sid = $d->insert(
    'snippets',
    {hash      => 'nosig-1', text => 'whatever', package => 1, score_version => 0},
    {returning => 'id'}
  )->hash->{id};
  $d->insert('file_snippets', {package => 1, file => $f, snippet => $sid, sline => 1, eline => 2});

  $a->patterns->score_package_snippets(1);
  is $d->select('snippets', 'score_version', {id => $sid})->hash->{score_version}, 0,
    'the stale snippet is left unscored without similarity data';
};

subtest 'analyze wires scoring: a stale snippet is self-healed when its package is analyzed' => sub {
  my $sid = $add_snippet->(text => $gfdl->{pattern});
  is $db->select('snippets', 'score_version', {id => $sid})->hash->{score_version}, 0, 'starts unscored';

  $app->minion->enqueue(analyze => [1]);
  $app->minion->perform_jobs;
  is $app->minion->jobs({states => ['failed']})->total, 0, 'no failed jobs';

  is $db->select('snippets', 'score_version', {id => $sid})->hash->{score_version}, SNIPPET_SCORE_VERSION,
    'analyze scored the stale snippet to the current version';
};

done_testing;
