# Copyright (C) 2018-2020 SUSE LLC
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

use Mojo::Base -strict;

use FindBin;
use lib "$FindBin::Bin/lib";

use Test::More;
use Test::Mojo;
use Cavil::Test;

plan skip_all => 'set TEST_ONLINE to enable this test' unless $ENV{TEST_ONLINE};

my $cavil_test = Cavil::Test->new(online => $ENV{TEST_ONLINE}, schema => 'pattern_removal_test');
my $config     = $cavil_test->default_config;
my $t          = Test::Mojo->new(Cavil => $config);
$cavil_test->mojo_fixtures($t->app);

my $app    = $t->app;
my $db     = $app->pg->db;
my $minion = $app->minion;
my $cache  = $cavil_test->cache_dir;

# Fully index the package through the normal job chain so we have real matches to work with
$minion->enqueue(unpack => [1]);
$minion->perform_jobs;
ok -f $cache->child('cavil.tokens'),      'token cache built by indexing';
ok -f $cache->child('cavil.pattern.bag'), 'pattern bag built by stats job';
is $minion->backend->list_jobs(0, 100, {states => ['failed']})->{total}, 0, 'no failed jobs after indexing';

subtest 'Removing a pattern cleans up and reindexes the affected packages' => sub {

  # Pattern 1 ("You may obtain a copy of the License at") is unspecific and matched the package
  my $pid     = 1;
  my $matches = $db->query('SELECT COUNT(*) AS c FROM pattern_matches WHERE pattern = ?', $pid)->hash->{c};
  ok $matches > 0, 'pattern has matches before removal';
  my $affected = [map { $_->{package} }
      $db->query('SELECT DISTINCT package FROM pattern_matches WHERE pattern = ?', $pid)->hashes->each];
  is_deeply $affected, [1], 'exactly one affected package';

  # Remove the pattern through the real admin endpoint
  $t->get_ok('/login')->status_is(302);
  $t->delete_ok("/licenses/remove_pattern/$pid")->status_is(200)->json_is('' => 'ok');

  # The row and (via ON DELETE CASCADE) its matches are gone, with no dangling references left
  is $db->query('SELECT COUNT(*) AS c FROM license_patterns WHERE id = ?', $pid)->hash->{c}, 0, 'pattern removed';
  is $db->query('SELECT COUNT(*) AS c FROM pattern_matches WHERE pattern = ?', $pid)->hash->{c}, 0,
    'matches cascaded away';

  # Caches were expired (and only after the row was gone, so a rebuild cannot re-add the pattern)
  ok !-f $cache->child('cavil.tokens'),      'token cache expired on removal';
  ok !-f $cache->child('cavil.pattern.bag'), 'pattern bag expired on removal';

  # The affected package was queued for reindexing and a stats recalculation was scheduled
  my $later = $minion->backend->list_jobs(0, 10, {tasks => ['index_later'], states => ['inactive']});
  is $later->{total}, 1, 'one reindex job enqueued for the affected package';
  is_deeply $later->{jobs}[0]{args}, [1], 'reindex targets the affected package';
  ok $minion->backend->list_jobs(0, 10, {tasks => ['pattern_stats'], states => ['inactive']})->{total},
    'pattern stats recalculation scheduled';

  # The queued reindex (and cache rebuild) completes cleanly
  $minion->perform_jobs;
  is $minion->backend->list_jobs(0, 100, {states => ['failed']})->{total}, 0, 'reindex finished without failures';
  ok -f $cache->child('cavil.tokens'), 'token cache rebuilt without the removed pattern';
};

subtest 'Indexer skips matches for a pattern removed mid-flight (stale cache)' => sub {

  # Pick an unspecific pattern that currently matches the package and is therefore baked into
  # the on-disk token cache
  my $victim = $db->query(
    q{SELECT lp.id FROM license_patterns lp JOIN pattern_matches pm ON pm.pattern = lp.id
       WHERE lp.packname = '' GROUP BY lp.id ORDER BY lp.id LIMIT 1}
  )->hash->{id};
  ok $victim,                          'found an unspecific pattern with matches';
  ok -f $cache->child('cavil.tokens'), 'token cache present and still references it';

  # Simulate the race: the pattern is deleted from the database (as the cascade would do during a
  # concurrent removal) while the token cache - and any in-flight matcher loaded from it - still
  # contains it. Crucially we do NOT expire the cache here.
  $db->delete('license_patterns', {id => $victim});
  ok -f $cache->child('cavil.tokens'), 'token cache deliberately left stale';

  # Reindexing must not blow up with a foreign key violation on the now-missing pattern
  $minion->enqueue(index_later => [1]);
  $minion->perform_jobs;
  is $minion->backend->list_jobs(0, 100, {states => ['failed']})->{total}, 0,
    'reindex with a stale cache finished without failures';

  # And it must not have written any matches for the pattern that no longer exists
  is $db->query('SELECT COUNT(*) AS c FROM pattern_matches WHERE pattern = ?', $victim)->hash->{c}, 0,
    'no dangling matches written for the removed pattern';
};

done_testing;
