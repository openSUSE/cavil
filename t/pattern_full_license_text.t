# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Mojo::Base -strict, -signatures;

use FindBin;
use lib "$FindBin::Bin/lib";

use Test::More;
use Test::Mojo;
use Cavil::Test;

plan skip_all => 'set TEST_ONLINE to enable this test' unless $ENV{TEST_ONLINE};

my $cavil_test = Cavil::Test->new(online => $ENV{TEST_ONLINE}, schema => 'pattern_full_license_text_test');
my $t          = Test::Mojo->new(Cavil => $cavil_test->default_config);
$cavil_test->no_fixtures($t->app);
my $patterns = $t->app->patterns;
my $db       = $t->app->pg->db;

sub flagged ($license) {
  return $db->query('SELECT id FROM license_patterns WHERE license = ? AND full_license_text ORDER BY id', $license)
    ->arrays->flatten->to_array;
}

subtest 'Exactly one pattern per license can be the full text' => sub {
  my $first
    = $patterns->create(pattern => 'First fixture terms, at length', license => 'Fixture-1.0', full_license_text => 1)
    ->{id};
  my $second = $patterns->create(
    pattern           => 'Second fixture terms, also at length',
    license           => 'Fixture-1.0',
    full_license_text => 1
  )->{id};
  ok $first && $second, 'both patterns were created';
  is_deeply flagged('Fixture-1.0'), [$second], 'flagging the second cleared the first';

  is $db->query('SELECT COUNT(*) FROM license_patterns WHERE license = ?', 'Fixture-1.0')->array->[0], 2,
    'and no pattern was removed';

  $patterns->update(
    $first,
    pattern           => 'First fixture terms, at length',
    license           => 'Fixture-1.0',
    risk              => 5,
    full_license_text => 1
  );
  is_deeply flagged('Fixture-1.0'), [$first], 'an update moves the claim back';

  $patterns->create(pattern => 'Other fixture terms entirely', license => 'Fixture-2.0', full_license_text => 1);
  is scalar @{flagged('Fixture-2.0')}, 1, 'another license keeps its own';
  is_deeply flagged('Fixture-1.0'), [$first], 'and does not disturb the first';
};

# The text is printed verbatim, so a wildcard would ship as part of the license
subtest 'A pattern with a skip cannot be the full text' => sub {
  my $result = $patterns->create(
    pattern           => 'Terms with a hole Copyright $SKIP12 and more terms after it',
    license           => 'Fixture-3.0',
    full_license_text => 1
  );
  like $result->{error}, qr/\$SKIP/, 'refused with a reason a curator can act on';
  is_deeply flagged('Fixture-3.0'), [], 'and nothing was flagged';

  my $id = $patterns->create(
    pattern => 'Terms with a hole Copyright $SKIP12 and more terms after it',
    license => 'Fixture-3.0'
  )->{id};
  ok $id, 'the pattern itself is still allowed';

  my $update = $patterns->update(
    $id,
    pattern           => 'Terms with a hole Copyright $SKIP12 and more terms after it',
    license           => 'Fixture-3.0',
    risk              => 5,
    full_license_text => 1
  );
  like $update->{error}, qr/\$SKIP/, 'and an update cannot sneak the claim in either';
  is_deeply flagged('Fixture-3.0'), [], 'still nothing flagged';
};

# A grab-bag marker has no text to reproduce
subtest 'A catch-all license cannot carry a full text' => sub {
  my $result = $patterns->create(
    pattern           => 'Some permissive sounding fixture text here',
    license           => 'Any Permissive',
    full_license_text => 1
  );
  like $result->{error}, qr/catch-all/i, 'refused';
  is_deeply flagged('Any Permissive'), [], 'and nothing was flagged';
};

# "backfill-catch-all" re-derives catch_all from the name, long after a text was curated
subtest 'A license that becomes a catch-all stops offering its text' => sub {
  my $id = $patterns->create(
    pattern           => 'Terms for a license that is about to be renamed',
    license           => 'Later-1.0',
    full_license_text => 1
  )->{id};
  ok $patterns->full_license_texts(['Later-1.0'])->{'Later-1.0'}, 'the text is offered while the name is concrete';

  $db->query('UPDATE license_patterns SET catch_all = true WHERE id = ?', $id);
  is_deeply $patterns->full_license_texts(['Later-1.0']), {}, 'and withdrawn once the name marks nothing';
};

subtest 'The curated texts of several licenses come back in one lookup' => sub {
  my $texts = $patterns->full_license_texts(['Fixture-1.0', 'Fixture-2.0', 'Fixture-3.0', 'Nothing-Here']);
  is_deeply [sort keys %$texts], ['Fixture-1.0', 'Fixture-2.0'], 'only the licenses that have one';
  is $texts->{'Fixture-1.0'}, 'First fixture terms, at length', 'with the pattern text itself';
  is_deeply $patterns->full_license_texts([]), {}, 'and an empty list needs no query';
};

# The refusal has to reach the curator, not just the model
subtest 'The refusal is surfaced by the web interface' => sub {
  $t->get_ok('/login')->status_is(302);

  my $id = $patterns->create(pattern => 'Web terms without a hole in them', license => 'Fixture-4.0')->{id};
  $t->post_ok("/licenses/pattern/$id.json" => form =>
      {pattern => 'Web terms with $SKIP4 a hole in them', license => 'Fixture-4.0', risk => 5, full_license_text => 1})
    ->status_is(400)
    ->json_like('/error' => qr/\$SKIP/);
  is_deeply flagged('Fixture-4.0'), [], 'nothing was flagged';

  $t->post_ok("/licenses/pattern/$id.json" => form =>
      {pattern => 'Web terms without a hole in them', license => 'Fixture-4.0', risk => 5, full_license_text => 1})
    ->status_is(200);
  is_deeply flagged('Fixture-4.0'), [$id], 'and the claim is recorded';
};

# Smart edit inserts a $SKIP10, so refusing only at accept time would surface it to an admin, hours later
subtest 'A proposal cannot carry the claim with a skip either' => sub {
  my $result = $patterns->propose_create(
    pattern           => 'Proposed terms with $SKIP10 in them',
    license           => 'Fixture-1.0',
    risk              => 5,
    full_license_text => 1,
    snippet           => 1
  );
  like $result->{error}, qr/\$SKIP/, 'refused before it becomes a proposal';
  is $t->app->pg->db->query("SELECT COUNT(*) FROM proposed_changes WHERE action = 'create_pattern'")->array->[0], 0,
    'and nothing was queued for an admin to trip over later';
};

# Sync ignores every conflict, so a colliding claim must not take the whole pattern down with it
subtest 'An imported claim displaces the local one instead of being dropped' => sub {
  my $existing = flagged('Fixture-1.0')->[0];
  ok $existing, 'the license already has a claim locally';

  my $id = $patterns->insert_pattern(
    {
      license           => 'Fixture-1.0',
      pattern           => 'Imported terms for the same license, at length',
      risk              => 5,
      full_license_text => 1
    }
  );
  ok $id, 'the incoming pattern was imported rather than skipped';
  is_deeply flagged('Fixture-1.0'), [$id], 'and it holds the claim';
};

done_testing;
