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

plan skip_all => 'set TEST_ONLINE to enable this test' unless $ENV{TEST_ONLINE};

# resolve_snippets is the single source of truth for the fold/clear/overlap decision; it writes
# file_snippets.resolution which every consumer then reads. This pins its behaviour for every case.
my $V = SNIPPET_SCORE_VERSION;

my $ct     = Cavil::Test->new(online => $ENV{TEST_ONLINE}, schema => 'snippet_resolve_test');
my $config = {
  %{$ct->default_config},
  snippet_fold => {
    enabled         => 1,
    threshold       => 0.95,
    min_margin      => 0.15,
    max_risk        => 5,
    clear_threshold => 0.95,
    overlap_clear   => 1,
    overlap_guard   => 0.9
  }
};
my $app = Test::Mojo->new(Cavil => $config)->app;
$ct->package_with_snippets_fixtures($app);
$app->minion->enqueue(unpack => [1]);
$app->minion->perform_jobs;
my $db = $app->pg->db;

my $gpl    = $db->query("SELECT id FROM license_patterns WHERE license = 'GPL' LIMIT 1")->hash->{id};
my $apache = $app->patterns->create(pattern => 'a distinct apache resolve marker text', license => 'Apache-2.0')->{id};
$db->query('UPDATE license_patterns SET risk = 4 WHERE id = ?', $apache);

# A grab-bag marker: overlap-clear must NOT count it as coverage (a real, possibly novel license can
# sit right next to a retained BSD/MIT warranty/CLA tail - the open-webui custom relicense case)
my $anycla = $app->patterns->create(pattern => 'a distinct any cla overlap marker text', license => 'Any CLA')->{id};
is $db->select('license_patterns', 'catch_all', {id => $anycla})->hash->{catch_all}, 1,
  'an "Any ..." marker is catch_all';

my $mf = $db->query('SELECT id FROM matched_files WHERE package = 1 LIMIT 1')->hash->{id};

# Control the occurrences ourselves (drop the fixture's, which are unscored noise)
$db->query('DELETE FROM file_snippets WHERE package = 1');

my $n    = 0;
my $snip = sub (%o) {
  $n++;
  return $db->insert(
    'snippets',
    {
      hash          => "res-$n",
      text          => "resolve snippet $n",
      package       => 1,
      classified    => 1,
      license       => (exists $o{legal} ? $o{legal} : 1),
      approved      => 0,
      confidence    => 100,
      likelyness    => $o{likelyness}    // 0,
      second_match  => $o{second_match}  // 0,
      score_version => $o{score_version} // 0,
      like_pattern  => $o{like_pattern}
    },
    {returning => 'id'}
  )->hash->{id};
};

my $line = 0;
my $occ  = sub ($sid, %o) {
  $line += 100;
  my $fid = $db->insert(
    'file_snippets',
    {package   => 1, file => $mf, snippet => $sid, sline => $line, eline => $line + 5},
    {returning => 'id'}
  )->hash->{id};
  $db->insert('pattern_matches',
    {package => 1, file => $mf, pattern => $o{overlap}, sline => $line + 1, eline => $line + 1, ignored => 0})
    if $o{overlap};
  return $fid;
};

my $fold      = $occ->($snip->(likelyness => 0.99, second_match => 0,    score_version => $V, like_pattern => $gpl));
my $clear     = $occ->($snip->(likelyness => 0.99, second_match => 0.99, score_version => $V, like_pattern => $gpl));
my $overlap   = $occ->($snip->(),                                                                 overlap => $gpl);
my $catchonly = $occ->($snip->(),                                                                 overlap => $anycla);
my $guard     = $occ->($snip->(likelyness => 0.92, score_version => $V, like_pattern => $apache), overlap => $gpl);
my $nonlegal  = $occ->($snip->(legal => 0),                                                       overlap => $gpl);
my $none      = $occ->($snip->());

# Same snippet in two files: overlaps a match in one, not the other (the per-occurrence case)
my $shared    = $snip->();
my $shared_ov = $occ->($shared, overlap => $gpl);
my $shared_no = $occ->($shared);

# A snippet that would fold but the reviewer has ignored -> never resolved
my $ignored_sid = $snip->(likelyness => 0.99, second_match => 0, score_version => $V, like_pattern => $gpl);
my $ignored_f   = $occ->($ignored_sid);
$app->packages->ignore_line(
  {
    hash        => $db->select('snippets', 'hash', {id => $ignored_sid})->hash->{hash},
    package     => 'package-with-snippets',
    owner       => undef,
    contributor => undef
  }
);

$app->snippets->resolve_snippets(1);

my $res = sub ($fid) { $db->select('file_snippets', 'resolution', {id => $fid})->hash->{resolution} };

is $res->($fold),      'fold',    'confident, low-risk, wide-margin snippet -> fold';
is $res->($clear),     'clear',   'high-similarity zero-margin snippet -> clear';
is $res->($overlap),   'overlap', 'unscored snippet over a real license match -> overlap';
is $res->($catchonly), undef,     'overlaps only a catch_all marker -> kept for review (not overlap-cleared)';
is $res->($guard),     undef,     'snippet resembling a different license (>= guard) is kept';
is $res->($nonlegal),  undef,     'non-legal text is never resolved';
is $res->($none),      undef,     'no overlap and not similar enough -> unresolved';

is $res->($shared_ov), 'overlap', 'per occurrence: overlaps a match in this file -> overlap';
is $res->($shared_no), undef,     'per occurrence: same snippet, no match in this file -> unresolved';

is $res->($ignored_f), undef, 'a would-fold snippet that is ignored is never resolved';

subtest 'covered: a concrete license already on the file/directory clears the fragment' => sub {

  # A concrete low-risk (MIT, risk 2) closest license for the fragments, a high-risk one for the guard,
  # and a catch_all marker that must NOT count as coverage.
  my $mit = $app->patterns->create(pattern => 'a distinct mit cover marker text', license => 'MIT')->{id};
  $db->query('UPDATE license_patterns SET risk = 2 WHERE id = ?', $mit);
  my $agpl
    = $app->patterns->create(pattern => 'a distinct agpl cover marker text', license => 'AGPL-3.0-or-later')->{id};
  $db->query('UPDATE license_patterns SET risk = 6 WHERE id = ?', $agpl);
  my $anyperm
    = $app->patterns->create(pattern => 'a distinct any permissive cover marker', license => 'Any Permissive')->{id};

  is $db->select('license_patterns', 'catch_all', {id => $anyperm})->hash->{catch_all}, 1,
    'create() flags an "Any ..." license as catch_all';
  is $db->select('license_patterns', 'catch_all', {id => $mit})->hash->{catch_all}, 0,
    'a real license is not catch_all';

  my $mkfile = sub ($name) {
    return $db->insert('matched_files', {package => 1, filename => $name, mimetype => 'text/plain'},
      {returning => 'id'})->hash->{id};
  };
  my $match = sub ($fid, $pid) {
    $db->insert('pattern_matches',
      {package => 1, file => $fid, pattern => $pid, sline => 50, eline => 50, ignored => 0});
  };
  my $cocc = sub ($fid, $sid) {
    return $db->insert(
      'file_snippets',
      {package   => 1, file => $fid, snippet => $sid, sline => 10, eline => 15},
      {returning => 'id'}
    )->hash->{id};
  };

  # File scope: a file that already carries a concrete Apache-2.0 (risk 4) match
  my $file_a = $mkfile->('coverage/withmatch.txt');
  $match->($file_a, $apache);
  my $cov  = $cocc->($file_a, $snip->(score_version => $V, like_pattern => $mit));     # risk 2 <= 4  -> covered
  my $high = $cocc->($file_a, $snip->(score_version => $V, like_pattern => $agpl));    # risk 6 > 4   -> kept

  # A file (in its own directory) whose ONLY match is a catch_all marker -> not real coverage (the
  # "real license behind a weak marker" case), so the fragment is kept at both file and directory scope.
  my $file_b = $mkfile->('coverage-weak/weakonly.txt');
  $match->($file_b, $anyperm);
  my $weak = $cocc->($file_b, $snip->(score_version => $V, like_pattern => $mit));

  # Directory scope: the concrete match lives in a sibling file in the same directory
  my $file_c = $mkfile->('coverage/dir/source.js');
  $match->($file_c, $apache);
  my $file_d  = $mkfile->('coverage/dir/source.js.map');
  my $sibling = $cocc->($file_d, $snip->(score_version => $V, like_pattern => $mit));

  my $res = sub ($fid) { $db->select('file_snippets', 'resolution', {id => $fid})->hash->{resolution} };

  subtest 'cover_scope => file' => sub {
    my $fapp
      = Test::Mojo->new(Cavil => {%$config, snippet_fold => {%{$config->{snippet_fold}}, cover_scope => 'file'}})->app;
    $fapp->snippets->resolve_snippets(1);
    is $res->($cov),     'covered', 'lower-risk fragment in a concretely-licensed file -> covered';
    is $res->($high),    undef,     'higher-risk fragment than the coverage -> kept';
    is $res->($weak),    undef,     'only a catch_all marker covers the file -> kept';
    is $res->($sibling), undef,     'file scope does not reach a sibling file -> kept';
  };

  subtest 'cover_scope => dir' => sub {
    my $dapp
      = Test::Mojo->new(Cavil => {%$config, snippet_fold => {%{$config->{snippet_fold}}, cover_scope => 'dir'}})->app;
    $dapp->snippets->resolve_snippets(1);
    is $res->($sibling), 'covered', 'directory scope reaches a concrete match in a sibling file -> covered';
    is $res->($high),    undef,     'directory scope still keeps a higher-risk fragment';
    is $res->($weak),    undef,     'directory scope still ignores catch_all-only coverage';
  };
};

subtest 'disabling the feature clears all resolutions' => sub {
  my $off = Test::Mojo->new(Cavil => {%$config, snippet_fold => {%{$config->{snippet_fold}}, enabled => 0}})->app;
  $off->snippets->resolve_snippets(1);
  is $db->query("SELECT count(*) n FROM file_snippets WHERE package = 1 AND resolution IS NOT NULL")->hash->{n}, 0,
    'nothing is resolved when the feature is disabled';
};

done_testing;
