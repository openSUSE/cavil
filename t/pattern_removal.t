# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Mojo::Base -strict, -signatures;

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

my $app      = $t->app;
my $db       = $app->pg->db;
my $minion   = $app->minion;
my $patterns = $app->patterns;
my $matcher  = $app->patterns->matcher_cache_file;
my $bag      = $app->patterns->bag_cache_file;

# Fully index the package through the normal job chain so we have real matches to work with
$minion->enqueue(unpack => [1]);
$minion->perform_jobs;
ok -f $matcher, 'matcher cache built by indexing';
ok -f $bag,     'pattern bag built by stats job';
is $minion->backend->list_jobs(0, 100, {states => ['failed']})->{total}, 0, 'no failed jobs after indexing';

$t->get_ok('/login')->status_is(302);

sub rows_for ($license) {
  $db->query(
    'SELECT id, license, risk, spdx, catch_all, full_license_text FROM license_patterns WHERE license = ?
    ORDER BY id', $license
  )->hashes->to_array;
}

sub sl_count ($license) {
  $db->query('SELECT COUNT(*) AS c FROM shingle_license WHERE license = ?', $license)->hash->{c};
}

sub inactive_reindex_ids () {
  my $jobs = $minion->backend->list_jobs(0, 100, {tasks => ['index_later'], states => ['inactive']});
  return [sort map { $_->{args}[0] } @{$jobs->{jobs}}];
}

# The bulk license/risk/spdx edit runs before the removal subtests below because those delete pattern id 1
# (the Apache-2.0 global pattern), which these need intact and matched.
subtest 'Bulk edit renames, sets risk, clears spdx, and reindexes affected packages' => sub {
  my $affected = [
    map { $_->{package} } $db->query(
      "SELECT DISTINCT package FROM pattern_matches WHERE pattern IN
       (SELECT id FROM license_patterns WHERE license = 'Apache-2.0')"
    )->hashes->each
  ];
  ok scalar @$affected > 0, 'Apache-2.0 matched at least one package';

  $t->post_ok('/licenses/meta/Apache-2.0' => form =>
      {license => 'Apache-2.0', new_license => 'Apache-Fixed', risk => 4, spdx => ''})
    ->status_is(200)
    ->json_is('/updated' => 2)
    ->json_is('/renamed' => Mojo::JSON::true)
    ->json_is('/license' => 'Apache-Fixed')
    ->json_is('/spdx'    => '');

  my $after = rows_for('Apache-Fixed');
  is scalar @$after, 2, 'both patterns renamed';
  is_deeply [map { $_->{risk} } @$after], [4, 4], 'risk flattened to the chosen value';
  is $after->[0]{spdx},                '', 'spdx cleared';
  is scalar @{rows_for('Apache-2.0')}, 0,  'nothing left under the old name';

  is_deeply inactive_reindex_ids(), $affected, 'every affected package queued for reindex';
  $minion->perform_jobs;
  is $minion->backend->list_jobs(0, 100, {states => ['failed']})->{total}, 0, 'queued reindex finished cleanly';
};

subtest 'Bulk edit: spdx-only change keeps the name and does not flatten risk' => sub {
  $t->post_ok('/licenses/meta/Apache-Fixed' => form =>
      {license => 'Apache-Fixed', new_license => 'Apache-Fixed', spdx => 'Apache-2.0'})
    ->status_is(200)
    ->json_is('/renamed' => Mojo::JSON::false)
    ->json_is('/spdx'    => 'Apache-2.0');
  is $db->query("SELECT COUNT(DISTINCT spdx) AS c FROM license_patterns WHERE license = 'Apache-Fixed'")->hash->{c}, 1,
    'spdx uniform across the license';
};

subtest 'Bulk edit: the empty-license bucket cannot be bulk-edited' => sub {
  $t->post_ok('/licenses/meta/' => form => {license => '', new_license => 'Something', spdx => ''})->status_is(400);
};

subtest 'Bulk edit: an invalid spdx expression is rejected' => sub {
  $t->post_ok('/licenses/meta/Artistic-2.0' => form => {license => 'Artistic-2.0', spdx => 'not a license ('})
    ->status_is(400);
};

subtest 'Bulk edit: an out-of-range risk is rejected' => sub {
  $t->post_ok('/licenses/meta/Artistic-2.0' => form => {license => 'Artistic-2.0', risk => 42, spdx => ''})
    ->status_is(400);
};

subtest 'Bulk edit model: no-op when the license has no patterns' => sub {
  is $patterns->update_license_meta('Does-Not-Exist', license => 'Whatever', spdx => '')->{updated}, 0,
    'nothing updated';
};

subtest 'Bulk edit model: rename resyncs the shingle index and re-derives catch_all' => sub {
  ok sl_count('Apache-Fixed') > 0, 'source has shingle_license rows';
  is rows_for('Apache-Fixed')->[0]{catch_all}, 0, 'not a catch-all before';

  # "*-Unspecified" is a catch-all name, so catch_all must flip on the rename.
  my $result = $patterns->update_license_meta('Apache-Fixed', license => 'Apache-Unspecified', spdx => '');
  is $result->{updated}, 2, 'both patterns moved';

  is sl_count('Apache-Fixed'), 0, 'shingle index no longer references the old name';
  ok sl_count('Apache-Unspecified') > 0, 'shingle index moved to the new name';
  is_deeply [map { $_->{catch_all} } @{rows_for('Apache-Unspecified')}], [1, 1], 'catch_all derived from the new name';
};

subtest 'Bulk edit model: a passed risk flattens, an omitted risk leaves mixed risks untouched' => sub {
  my $ids = [map { $_->{id} } @{rows_for('Apache-Unspecified')}];
  $db->query('UPDATE license_patterns SET risk = 2 WHERE id = ?', $ids->[0]);
  $db->query('UPDATE license_patterns SET risk = 8 WHERE id = ?', $ids->[1]);

  $patterns->update_license_meta('Apache-Unspecified', license => 'Apache-Unspecified', spdx => '');
  is_deeply [sort { $a <=> $b } map { $_->{risk} } @{rows_for('Apache-Unspecified')}], [2, 8],
    'risks preserved when no risk is passed';

  $patterns->update_license_meta('Apache-Unspecified', license => 'Apache-Unspecified', risk => 7, spdx => '');
  is_deeply [map { $_->{risk} } @{rows_for('Apache-Unspecified')}], [7, 7],
    'both patterns flattened when a risk is set';
};

subtest 'Bulk edit model: merge keeps spdx uniform across the destination license' => sub {

  # SUSE-NotALicense has an empty spdx; merge it into Artistic-2.0 (spdx already set).
  ok scalar @{rows_for('SUSE-NotALicense')} > 0, 'source exists';
  ok scalar @{rows_for('Artistic-2.0')} > 0,     'destination exists';

  $patterns->update_license_meta('SUSE-NotALicense', license => 'Artistic-2.0', spdx => 'Artistic-2.0');
  is scalar @{rows_for('SUSE-NotALicense')}, 0, 'source name emptied';
  my @spdx = map { $_->{spdx} } @{rows_for('Artistic-2.0')};
  ok scalar(@spdx) >= 2, 'destination now holds both licenses worth of patterns';
  is_deeply [grep { $_ ne 'Artistic-2.0' } @spdx], [], 'every pattern shares the one spdx after the merge';
};

subtest 'Bulk edit model: merging two full-license-text patterns does not violate the unique index' => sub {
  $patterns->create(
    pattern           => 'FULL TEXT of licence FOO here',
    license           => 'FullText-A',
    risk              => 5,
    full_license_text => 1
  );
  $patterns->create(
    pattern           => 'FULL TEXT of licence BAR here',
    license           => 'FullText-B',
    risk              => 5,
    full_license_text => 1
  );

  is $patterns->update_license_meta('FullText-A', license => 'FullText-B', spdx => '')->{updated}, 1,
    'the source pattern moved';
  is $db->query("SELECT COUNT(*) AS c FROM license_patterns WHERE license = 'FullText-B' AND full_license_text")
    ->hash->{c}, 1, 'exactly one full-license-text pattern survives in the destination';
};

# Drain any reindex jobs the bulk-edit subtests queued so the removal assertions below start from a clean
# queue (they count enqueued reindex jobs).
$minion->perform_jobs;
is $minion->backend->list_jobs(0, 100, {states => ['failed']})->{total}, 0, 'no failed jobs after the bulk edits';

subtest 'Removing a pattern cleans up and reindexes the affected packages' => sub {

  # Pattern 1 ("You may obtain a copy of the License at") is unspecific and matched the package
  my $pid     = 1;
  my $matches = $db->query('SELECT COUNT(*) AS c FROM pattern_matches WHERE pattern = ?', $pid)->hash->{c};
  ok $matches > 0, 'pattern has matches before removal';
  my $affected = [map { $_->{package} }
      $db->query('SELECT DISTINCT package FROM pattern_matches WHERE pattern = ?', $pid)->hashes->each];
  is_deeply $affected, [1], 'exactly one affected package';

  # Remove the pattern through the real admin endpoint
  $t->delete_ok("/licenses/remove_pattern/$pid")->status_is(200)->json_is('' => 'ok');

  # The row and (via ON DELETE CASCADE) its matches are gone, with no dangling references left
  is $db->query('SELECT COUNT(*) AS c FROM license_patterns WHERE id = ?', $pid)->hash->{c}, 0, 'pattern removed';
  is $db->query('SELECT COUNT(*) AS c FROM pattern_matches WHERE pattern = ?', $pid)->hash->{c}, 0,
    'matches cascaded away';

  # Caches were expired (and only after the row was gone, so a rebuild cannot re-add the pattern)
  ok !-f $matcher, 'matcher cache expired on removal';
  ok !-f $bag,     'pattern bag expired on removal';

  # The affected package was queued for reindexing and a stats recalculation was scheduled
  my $later = $minion->backend->list_jobs(0, 10, {tasks => ['index_later'], states => ['inactive']});
  is $later->{total}, 1, 'one reindex job enqueued for the affected package';
  is_deeply $later->{jobs}[0]{args}, [1], 'reindex targets the affected package';
  ok $minion->backend->list_jobs(0, 10, {tasks => ['pattern_stats'], states => ['inactive']})->{total},
    'pattern stats recalculation scheduled';

  # The queued reindex (and cache rebuild) completes cleanly
  $minion->perform_jobs;
  is $minion->backend->list_jobs(0, 100, {states => ['failed']})->{total}, 0, 'reindex finished without failures';
  ok -f $matcher, 'matcher cache rebuilt without the removed pattern';
};

subtest 'Indexer skips matches for a pattern removed mid-flight (stale cache)' => sub {

  # Pick an unspecific pattern that currently matches the package and is therefore baked into
  # the on-disk matcher cache
  my $victim = $db->query(
    q{SELECT lp.id FROM license_patterns lp JOIN pattern_matches pm ON pm.pattern = lp.id
       WHERE lp.packname = '' GROUP BY lp.id ORDER BY lp.id LIMIT 1}
  )->hash->{id};
  ok $victim,     'found an unspecific pattern with matches';
  ok -f $matcher, 'matcher cache present and still references it';

  # Simulate the race: the pattern is deleted from the database (as the cascade would do during a
  # concurrent removal) while the matcher cache - and any in-flight matcher loaded from it - still
  # contains it. Crucially we do NOT expire the cache here.
  $db->delete('license_patterns', {id => $victim});
  ok -f $matcher, 'matcher cache deliberately left stale';

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
