# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Mojo::Base -strict, -signatures;

use FindBin;
use lib "$FindBin::Bin/lib";

use Test::More;
use Test::Mojo;
use Cavil::Test;

plan skip_all => 'set TEST_ONLINE to enable this test' unless $ENV{TEST_ONLINE};

my $cavil_test = Cavil::Test->new(online => $ENV{TEST_ONLINE}, schema => 'audit_log_corpus_test');
my $t          = Test::Mojo->new(Cavil => $cavil_test->default_config);
$cavil_test->mojo_fixtures($t->app);
my $app = $t->app;
my $db  = $app->pg->db;

my $corpus = q{SELECT * FROM audit_events WHERE type NOT LIKE 'review.%' AND type NOT LIKE 'limitation.%' ORDER BY id};
my $since  = sub ($n) { my $e = $db->query($corpus)->expand->hashes; [@$e[$n .. $#$e]] };
my $count  = sub { $db->query($corpus)->hashes->size };
my $decide = sub ($kind, $form, $snippet = undef) {
  $t->post_ok('/snippet/batch_decision' => json =>
      {actions => [{kind => $kind, formData => $form, defined $snippet ? (snippetId => $snippet) : ()}]})
    ->status_is(200)
    ->json_is('/ok', 1);
};

$app->minion->enqueue(unpack => [1]);
$app->minion->perform_jobs;
$t->get_ok('/login')->status_is(302);
my $tester = $app->users->find(login => 'tester')->{id};
my $text   = 'An audited license text for testing';
my $id;

subtest 'Pattern created in the license editor' => sub {
  my $n = $count->();
  $t->post_ok('/licenses/create_pattern' => form => {pattern => $text, license => 'MIT', risk => 2})->status_is(302);
  $id = $db->select('license_patterns', ['id', 'owner'], {pattern => $text})->hash->{id};
  is $app->patterns->find($id)->{owner}, $tester, 'the pattern has an owner now';

  my $e = $since->($n);
  is scalar @$e,     1,                 'one event';
  is $e->[0]{type},  'pattern.created', 'right type';
  is $e->[0]{actor}, $tester,           'by the curator';
  is_deeply $e->[0]{data}, {pattern => $id, license => 'MIT', risk => 2, text => $text}, 'what the pattern said';
};

subtest 'Only what changed is recorded' => sub {
  my $n = $count->();
  $t->post_ok("/licenses/pattern/$id.json" => form => {pattern => $text, license => 'MIT', risk => 3})->status_is(200);
  $t->post_ok("/licenses/pattern/$id.json" => form => {pattern => $text, license => 'MIT', risk => 3})->status_is(200);
  $t->post_ok("/licenses/pattern/$id.json" => form => {pattern => "$text, revised", license => 'MIT', risk => 3})
    ->status_is(200);

  my $e = $since->($n);
  is scalar @$e, 2, 'saving without changes records nothing';
  is_deeply [map { [$_->{type}, $_->{actor}, $_->{data}{changes}] } @$e],
    [['pattern.updated', $tester, {risk => [2, 3]}], ['pattern.updated', $tester, {text => [$text, "$text, revised"]}]],
    'one field at a time';
};

subtest 'A bulk license edit is one event' => sub {
  my $n = $count->();
  $t->post_ok('/licenses/meta/MIT' => form => {license => 'MIT', new_license => 'MIT-audited', spdx => 'MIT'})
    ->status_is(200);
  $t->post_ok('/licenses/update_patterns' => form => {license => 'MIT-audited', spdx => 'BSD-2-Clause'})
    ->status_is(302);

  is_deeply [map { [$_->{type}, $_->{actor}, $_->{data}] } @{$since->($n)}],
    [
    [
      'license.updated', $tester,
      {license => 'MIT', patterns => 1, changes => {license => ['MIT', 'MIT-audited'], spdx => ['', 'MIT']}}
    ],
    [
      'license.updated', $tester,
      {license => 'MIT-audited', patterns => 1, changes => {spdx => ['MIT', 'BSD-2-Clause']}}
    ]
    ],
    'the rename and both SPDX changes';
};

subtest 'A removed pattern stays readable' => sub {
  my $n = $count->();
  $t->delete_ok("/licenses/remove_pattern/$id")->status_is(200);
  my $e = $since->($n);
  is_deeply [map { [$_->{type}, $_->{actor}, $_->{data}] } @$e],
    [['pattern.removed', $tester, {pattern => $id, license => 'MIT-audited', risk => 3, text => "$text, revised"}]],
    'the full pattern';
};

subtest 'Accepted proposals name who proposed them' => sub {
  my $n       = $count->();
  my $snippet = $db->query('SELECT id FROM snippets ORDER BY id LIMIT 1')->array->[0];
  my $hash    = '39e8204ddebdc31a4d0e77aa647f4241';
  $decide->(
    'create-pattern', {license => 'MIT', pattern => 'Proposed license text', risk => 2, contributor => 'tester'},
    $snippet
  );
  $decide->('create-ignore', {hash => $hash, from => 'perl-Mojolicious', contributor => 'tester'}, $snippet);
  $decide->('create-ignore', {hash => $hash, from => 'perl-Mojolicious', contributor => 'tester'}, $snippet);
  $decide->('create-glob',   {glob => 'audited/*.txt', package => 1, contributor => 'tester'});

  my $e = $since->($n);
  is_deeply [map { [$_->{type}, $_->{actor}, $_->{package_name}, $_->{data}{contributor}] } @$e],
    [
    ['pattern.created',     $tester, undef,              'tester'],
    ['ignored_match.added', $tester, 'perl-Mojolicious', 'tester'],
    ['ignored_file.added',  $tester, undef,              'tester']
    ],
    'an ignore that already exists records nothing';
  is $e->[1]{data}{hash}, $hash,           'the ignored match';
  is $e->[2]{data}{glob}, 'audited/*.txt', 'the glob';
};

subtest 'Ignores added and removed directly' => sub {
  my $n = $count->();
  $t->post_ok('/ignored-files' => form => {glob => 'direct/*.log'})->status_is(200);
  my $glob = $db->select('ignored_files', 'id', {glob => 'direct/*.log'})->hash->{id};
  $t->delete_ok("/ignored-files/$glob")->status_is(200);
  my $match = $db->select('ignored_lines', 'id', {packname => 'perl-Mojolicious'})->hash->{id};
  $t->delete_ok("/ignored-matches/$match")->status_is(200);

  is_deeply [map { [$_->{type}, $_->{actor}, $_->{package_name}, $_->{data}] } @{$since->($n)}],
    [
    ['ignored_file.added',    $tester, undef,              {glob => 'direct/*.log'}],
    ['ignored_file.removed',  $tester, undef,              {glob => 'direct/*.log'}],
    ['ignored_match.removed', $tester, 'perl-Mojolicious', {hash => '39e8204ddebdc31a4d0e77aa647f4241'}]
    ],
    'by the curator';
};

subtest 'A license merged into another records the patterns it brought into line' => sub {
  my $n = $count->();
  $t->post_ok('/licenses/meta/Artistic-2.0' => form =>
      {license => 'Artistic-2.0', new_license => 'Apache-2.0', spdx => 'Apache-2.0 OR Artistic-2.0'})->status_is(200);
  my $e = $since->($n);
  is scalar @$e, 1, 'one event';
  is_deeply $e->[0]{data},
    {
    license  => 'Artistic-2.0',
    patterns => 1,
    changes  => {license => ['Artistic-2.0', 'Apache-2.0'], spdx => ['Artistic-2.0', 'Apache-2.0 OR Artistic-2.0']},
    merged   => {patterns => 2, spdx => ['Apache-2.0', 'Apache-2.0 OR Artistic-2.0']}
    },
    'the existing Apache-2.0 patterns changed too';
};

subtest 'A pattern no longer limited to a package stays filed under it' => sub {
  my $n = $count->();
  $t->post_ok('/licenses/create_pattern' => form =>
      {pattern => 'Scoped audited text', license => 'MIT', risk => 1, packname => 'perl-Mojolicious'})->status_is(302);
  my $scoped = $db->select('license_patterns', 'id', {pattern => 'Scoped audited text'})->hash->{id};
  $t->post_ok(
    "/licenses/pattern/$scoped.json" => form => {pattern => 'Scoped audited text', license => 'MIT', risk => 1})
    ->status_is(200);
  is_deeply [map { [$_->{type}, $_->{package_name}, $_->{data}{changes}] } @{$since->($n)}],
    [
    ['pattern.created', 'perl-Mojolicious', undef],
    ['pattern.updated', 'perl-Mojolicious', {packname => ['perl-Mojolicious', '']}]
    ],
    'filed under the package it was limited to';
};

subtest 'A snippet marked as not legal text everywhere' => sub {
  my $n       = $count->();
  my $snippet = $db->query('SELECT id, hash FROM snippets ORDER BY id DESC LIMIT 1')->hash;
  $decide->('mark-non-license', {hash => $snippet->{hash}, contributor => 'tester'}, $snippet->{id});
  $decide->('mark-non-license', {hash => $snippet->{hash}},                          $snippet->{id});
  is_deeply [map { [$_->{type}, $_->{actor}, $_->{data}] } @{$since->($n)}],
    [['snippet.non_license', $tester, {hash => $snippet->{hash}, contributor => 'tester'}]],
    'with the proposer, and only once';
};

subtest 'A change that fails leaves no event' => sub {
  my $n = $count->();
  $t->post_ok('/ignored-files' => form => {glob => 'audited/*.txt'})->status_is(500);
  is $count->(), $n, 'the duplicate glob was rolled back with its event';
};

subtest 'Values keep their types' => sub {
  is $db->query(
    q{SELECT count(*) FROM audit_events
      WHERE jsonb_typeof(data->'risk') <> 'number'
        OR jsonb_typeof(data->'changes'->'risk'->0) NOT IN ('number', 'null')
        OR jsonb_typeof(data->'changes'->'risk'->1) NOT IN ('number', 'null')}
  )->array->[0], 0, 'risk is always a number';
};

subtest 'Command line maintenance records nothing' => sub {
  my $n = $count->();
  open my $out, '>', \my $buffer;
  local *STDOUT = $out;
  $app->start('patterns', '--fix-risk', 4, '-l', 'Apache-2.0');
  is $db->query('SELECT DISTINCT risk FROM license_patterns WHERE license = ?', 'Apache-2.0')->array->[0], 4,
    'risk fixed';
  is $count->(), $n, 'no event';
};

subtest 'Categories' => sub {
  $t->post_ok('/reviews/notes/1' => form => {body => 'Only with approval', limitation => 1})->status_is(200);
  my $all  = $db->query('SELECT type FROM audit_events')->hashes;
  my %only = (
    patterns    => qr/^(pattern|license)\./,
    ignored     => qr/^(ignored_match|ignored_file|snippet)\./,
    limitations => qr/^limitation\./,
    reviews     => qr/^review\./
  );
  for my $category (sort keys %only) {
    my $expected = grep { $_->{type} =~ $only{$category} } @$all;
    my $res      = $t->get_ok("/pagination/audit?limit=100&category=$category")->status_is(200)->tx->res->json;
    is $res->{total}, $expected, "every $category event";
    ok !grep({ $_->{type} !~ $only{$category} } @{$res->{page}}), "only $category";
  }
  ok $t->get_ok('/pagination/audit?category=patterns')->tx->res->json('/total') > 10, 'patterns are there';
  is $t->get_ok('/pagination/audit?category=limitations')->tx->res->json('/total'), 1, 'the limitation is there';
  $t->get_ok('/pagination/audit?category=nonsense')->status_is(400);
};

done_testing;
