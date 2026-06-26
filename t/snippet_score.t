# Copyright (C) 2026 SUSE LLC
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

subtest 'score_text: ctx path, bag fallback, and no-scorer' => sub {
  $patterns->rebuild_similarity_data;
  my $ctx = $patterns->similarity_context;
  ok $ctx, 'similarity context is available after a rebuild';

  # Relax the required-phrase gate (this tiny fixture corpus has only low IDF values - the gate itself
  # is covered in t/patterns_similarity.t) so the matching license is selected deterministically.
  my $relaxed = {%$ctx, distinctive_idf => 0, min_distinctive => 1};
  my $scored  = $patterns->score_text($gfdl->{pattern}, $relaxed);
  is $scored->{score_version}, SNIPPET_SCORE_VERSION, 'ctx path stamps the current score version';
  is $scored->{like_pattern},  $gfdl->{id},           'and picks the matching license pattern';
  ok $scored->{likelyness} > 0.5, 'with a healthy similarity';

  # Plain Spooky bag (no signatures): stamps version 0 so fold-in will not trust it.
  my $bag  = Spooky::Patterns::XS::init_bag_of_patterns;
  my %pats = map { $_->{id} => $_->{pattern} } @{$db->select('license_patterns', 'id,pattern')->hashes->to_array};
  $bag->set_patterns(\%pats);
  my $fallback = $patterns->score_text($gfdl->{pattern}, undef, $bag);
  is $fallback->{score_version}, 0, 'bag fallback stamps version 0';
  ok $fallback->{like_pattern}, 'but still records a closest pattern';

  is $patterns->score_text($gfdl->{pattern}, undef, undef), undef, 'with neither scorer it is a no-op';
};

subtest 'score_package_snippets: scores stale, skips current, re-scores stuck rows' => sub {
  $patterns->rebuild_similarity_data;

  my $stale = $add_snippet->(text => $gfdl->{pattern});    # version 0, no like_pattern yet

  # The stuck-snippet bug: classified before signatures existed -> version 0 but like_pattern already
  # set. The old pattern_stats (WHERE like_pattern IS NULL) skipped these forever; scoping by version
  # must re-score it.
  my $stuck = $add_snippet->(text => $gfdl->{pattern}, like_pattern => $gfdl->{id});

  # A snippet already at the current version must be left untouched.
  my $fresh = $add_snippet->(text => $gfdl->{pattern});
  $db->update('snippets', {score_version => SNIPPET_SCORE_VERSION}, {id => $fresh});

  $patterns->score_package_snippets(1);

  my $version = sub ($id) { $db->select('snippets', 'score_version', {id => $id})->hash->{score_version} };
  is $version->($stale), SNIPPET_SCORE_VERSION, 'a stale (version 0) snippet is scored to the current version';
  is $version->($stuck), SNIPPET_SCORE_VERSION, 'a stuck version-0 row with a like_pattern is re-scored too';
  is $version->($fresh), SNIPPET_SCORE_VERSION, 'a current-version snippet keeps the current version (skipped)';
};

subtest 'score_package_snippets: scoped to the package, no-op without signatures' => sub {
  my $ct = Cavil::Test->new(online => $ENV{TEST_ONLINE}, schema => 'snippet_score_nosig_test');
  my $tt = Test::Mojo->new(Cavil => $ct->default_config);
  my $a  = $tt->app;
  $ct->package_with_snippets_fixtures($a);
  $a->minion->enqueue(unpack => [1]);
  $a->minion->perform_jobs;
  my $d = $a->pg->db;

  # Pattern creation auto-rebuilds signatures, so drop them to exercise the "no scorer" early return.
  $ct->cache_dir->child('cavil.license.signatures')->remove;
  ok !$a->patterns->similarity_context, 'no similarity context once the signatures are gone';

  my $f   = $d->query('SELECT id FROM matched_files WHERE package = 1 LIMIT 1')->hash->{id};
  my $sid = $d->insert(
    'snippets',
    {hash      => 'nosig-1', text => 'whatever', package => 1, score_version => 0},
    {returning => 'id'}
  )->hash->{id};
  $d->insert('file_snippets', {package => 1, file => $f, snippet => $sid, sline => 1, eline => 2});

  $a->patterns->score_package_snippets(1);
  is $d->select('snippets', 'score_version', {id => $sid})->hash->{score_version}, 0,
    'the stale snippet is left unscored without signatures';
};

subtest 'analyze wires scoring: a stale snippet is self-healed when its package is analyzed' => sub {
  $app->patterns->rebuild_similarity_data;
  my $sid = $add_snippet->(text => $gfdl->{pattern});
  is $db->select('snippets', 'score_version', {id => $sid})->hash->{score_version}, 0, 'starts unscored';

  $app->minion->enqueue(analyze => [1]);
  $app->minion->perform_jobs;
  is $app->minion->jobs({states => ['failed']})->total, 0, 'no failed jobs';

  is $db->select('snippets', 'score_version', {id => $sid})->hash->{score_version}, SNIPPET_SCORE_VERSION,
    'analyze scored the stale snippet to the current version';
};

# The license pick is by license, but the attributed pattern must be the closest one *within* that
# license - not an arbitrary representative - so the stored like_pattern carries the right risk. This is
# the grab-bag case (e.g. "Any CLA"), where patterns of one license span very different risk levels.
subtest 'attributes the closest pattern within the license, with its real risk' => sub {

  # Two members of one license at different risk and with disjoint wording. The first created is the
  # arbitrary representative the old scorer always returned for this license.
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

  $patterns->rebuild_similarity_data;
  my $ctx     = $patterns->similarity_context;
  my $relaxed = {%$ctx, distinctive_idf => 0, min_distinctive => 1};    # tiny corpus: keep the gate out
  my $risk_of = sub ($id) { $db->select('license_patterns', 'risk', {id => $id})->hash->{risk} };

  my $hi = $patterns->score_text('november oscar papa quebec romeo sierra tango', $relaxed);
  is $hi->{like_pattern},   $high->{id}, 'a snippet matching the high-risk member is attributed to it';
  isnt $hi->{like_pattern}, $low->{id},  'not the arbitrary representative (the first pattern of the license)';
  is $risk_of->($hi->{like_pattern}), 5, 'so the stored pattern carries the right (high) risk';

  my $lo = $patterns->score_text('alpha bravo charlie delta echo foxtrot golf', $relaxed);
  is $lo->{like_pattern},             $low->{id}, 'a snippet matching the low-risk member is attributed to it';
  is $risk_of->($lo->{like_pattern}), 0,          'with the right (low) risk';
};

done_testing;
