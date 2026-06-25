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

my $fold     = $occ->($snip->(likelyness => 0.99, second_match => 0,    score_version => $V, like_pattern => $gpl));
my $clear    = $occ->($snip->(likelyness => 0.99, second_match => 0.99, score_version => $V, like_pattern => $gpl));
my $overlap  = $occ->($snip->(), overlap => $gpl);
my $guard    = $occ->($snip->(likelyness => 0.92, score_version => $V, like_pattern => $apache), overlap => $gpl);
my $nonlegal = $occ->($snip->(legal      => 0),                                                  overlap => $gpl);
my $none     = $occ->($snip->());

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

is $res->($fold),     'fold',    'confident, low-risk, wide-margin snippet -> fold';
is $res->($clear),    'clear',   'high-similarity zero-margin snippet -> clear';
is $res->($overlap),  'overlap', 'unscored snippet over a real license match -> overlap';
is $res->($guard),    undef,     'snippet resembling a different license (>= guard) is kept';
is $res->($nonlegal), undef,     'non-legal text is never resolved';
is $res->($none),     undef,     'no overlap and not similar enough -> unresolved';

is $res->($shared_ov), 'overlap', 'per occurrence: overlaps a match in this file -> overlap';
is $res->($shared_no), undef,     'per occurrence: same snippet, no match in this file -> unresolved';

is $res->($ignored_f), undef, 'a would-fold snippet that is ignored is never resolved';

subtest 'disabling the feature clears all resolutions' => sub {
  my $off = Test::Mojo->new(Cavil => {%$config, snippet_fold => {%{$config->{snippet_fold}}, enabled => 0}})->app;
  $off->snippets->resolve_snippets(1);
  is $db->query("SELECT count(*) n FROM file_snippets WHERE package = 1 AND resolution IS NOT NULL")->hash->{n}, 0,
    'nothing is resolved when the feature is disabled';
};

done_testing;
