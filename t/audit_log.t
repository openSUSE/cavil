# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Mojo::Base -strict, -signatures;

use FindBin;
use lib "$FindBin::Bin/lib";

use Test::More;
use Test::Mojo;
use Cavil::Test;

plan skip_all => 'set TEST_ONLINE to enable this test' unless $ENV{TEST_ONLINE};

my $cavil_test = Cavil::Test->new(online => $ENV{TEST_ONLINE}, schema => 'audit_log_test');
my $config     = $cavil_test->default_config;
$config->{acceptable_packages} = ['perl-Mojolicious'];
my $t = Test::Mojo->new(Cavil => $config);
$cavil_test->mojo_fixtures($t->app);
my $app  = $t->app;
my $db   = $app->pg->db;
my $pkgs = $app->packages;
my $bot  = {Authorization => 'Token test_token'};

my $all
  = sub { $db->query("SELECT * FROM audit_events WHERE package_name = 'perl-Mojolicious' ORDER BY id")->expand->hashes };
my $since     = sub ($n) { my $e = $all->(); [@$e[$n .. $#$e]] };
my $decision  = sub ($e) { [$e->{type}, $e->{actor}, @{$e->{data}}{qw(from to result ai_assisted)}] };
my $set_roles = sub (@roles) { $db->update('bot_users', {roles => [@roles]}, {login => 'tester'}) };

$app->minion->enqueue(unpack => [$_]) for 1, 2;
$app->minion->perform_jobs;
my $checksum = $pkgs->find(1)->{checksum};
my $accepted = qr/Accepted because of package name/;

subtest 'Automatic acceptance' => sub {
  my $e = $db->query('SELECT * FROM audit_events WHERE package = 1')->expand->hashes;
  is $e->size,                1,                  'one event';
  is $e->[0]{package_name},   'perl-Mojolicious', 'package name';
  is $e->[0]{data}{checksum}, $checksum,          'decided against this report';
  is_deeply [@{$decision->($e->[0])}[0 .. 3]], ['review.decision', undef, 'new', 'acceptable'], 'by Cavil';
  like $e->[0]{data}{result}, $accepted, 'reason';
};

subtest 'Reindex without a decision records nothing' => sub {
  my $before = $all->()->size;
  is $pkgs->reindex(1), 'now', 'reindexing';
  $app->minion->perform_jobs;
  is $pkgs->find(1)->{state}, 'acceptable', 'still accepted';
  is $all->()->size,          $before,      'no new event';

  $t->post_ok('/packages/import/1' => $bot => form => {tags => 'CVE-2026-1'})->status_is(200);
  $t->post_ok('/packages/import/1' => $bot)->status_is(200);
  is_deeply $pkgs->find(1)->{tags}, ['CVE-2026-1'], 'a re-import that only tags still works';
  is $all->()->size, $before, 'and records nothing';
};

$t->get_ok('/login')->status_is(302);
my $tester = $app->users->find(login => 'tester')->{id};

subtest 'Manual decisions, also when the state stays the same' => sub {
  my $n = $all->()->size;
  $set_roles->('admin');
  $t->post_ok('/reviews/review_package/1' => form => {unacceptable => 1, comment => 'Nope'})->status_is(200);
  $t->post_ok('/reviews/review_package/1' => form => {unacceptable => 1, comment => 'Still nope'})->status_is(200);
  $set_roles->('lawyer');
  $t->post_ok('/reviews/review_package/1' => form => {acceptable => 1, comment => 'Fine'})->status_is(200);
  is_deeply [map { $decision->($_) } @{$since->($n)}],
    [
    ['review.decision', $tester, 'acceptable',   'unacceptable',         'Nope',       0],
    ['review.decision', $tester, 'unacceptable', 'unacceptable',         'Still nope', 0],
    ['review.decision', $tester, 'unacceptable', 'acceptable_by_lawyer', 'Fine',       0]
    ],
    'attributed to the reviewer';
};

subtest 'A stale AI flag is not carried into later decisions' => sub {
  my $n = $all->()->size;

  # Left behind by an earlier AI assistant decision
  $db->update('bot_packages', {ai_assisted => 1}, {id => 1});
  $t->post_ok('/packages/import/1' => $bot => form => {state => 'new'})->status_is(200);
  $app->minion->perform_jobs;
  $set_roles->('manager');
  $t->post_ok('/reviews/fasttrack_package/1' => form => {comment => 'Quick'})->status_is(200);

  my $e = $since->($n);
  is_deeply [map { $decision->($_) } @$e[0, 2]],
    [
    ['review.decision', undef,   'acceptable_by_lawyer', 'new',        undef,   0],
    ['review.decision', $tester, 'acceptable',           'acceptable', 'Quick', 0]
    ],
    'bot reopen by Cavil, fasttrack by the manager';
  is_deeply [@{$decision->($e->[1])}[0 .. 3, 5]], ['review.decision', undef, 'new', 'acceptable', 0],
    'automatic acceptance in between';
  is scalar @$e, 3, 'nothing else';
};

subtest 'Limitations and the reopen they cause' => sub {
  my $n = $all->()->size;
  $set_roles->('admin');
  $t->post_ok('/reviews/notes/1' => form => {body => 'Only with approval', limitation => 1})->status_is(200);
  my $note = $t->tx->res->json('/note/id');
  $t->patch_ok("/reviews/notes/$note" => form => {body => 'Only with approval, see ticket 42'})->status_is(200);
  $pkgs->rereview_limited(1);
  $app->minion->perform_jobs;
  $t->delete_ok("/reviews/notes/$note")->status_is(200);

  my $e = $since->($n);
  is_deeply [map { [$_->{type}, $_->{actor}, $_->{package}, $_->{data}] } @$e[0, 1, 3]],
    [
    ['limitation.added', $tester, undef, {note => $note, to => 'Only with approval'}],
    [
      'limitation.edited', $tester, undef,
      {note => $note, from => 'Only with approval', to => 'Only with approval, see ticket 42'}
    ],
    ['limitation.removed', $tester, undef, {note => $note, from => 'Only with approval, see ticket 42'}]
    ],
    'every change to the limitation, by whom';
  is_deeply $decision->($e->[2]), ['review.decision', undef, 'acceptable', 'new', undef, 0],
    'reopened by Cavil, not blamed on the previous reviewer';
  is scalar @$e, 4, 'nothing else';
};

subtest 'Obsoleting and restoring records nothing' => sub {
  my $n = $all->()->size;
  $pkgs->obsolete_if_unused(1);
  ok $pkgs->find(1)->{obsolete}, 'obsolete';
  $app->requests->add('obs#1', 1);
  ok !$pkgs->find(1)->{obsolete}, 'restored';
  is $all->()->size, $n, 'housekeeping, not a decision';
};

subtest 'Audit log page' => sub {
  for my $role (qw(user manager)) {
    $set_roles->($role);
    $t->get_ok('/audit')->status_is(403);
    $t->get_ok('/pagination/audit')->status_is(403);
    $t->get_ok('/reviews/meta/1')->status_is(200)->json_is('/can_view_audit', 0);
  }
  for my $role (qw(admin lawyer)) {
    $set_roles->($role);
    $t->get_ok('/audit')->status_is(200)->element_exists('#audit-log');
    $t->get_ok('/reviews/meta/1')->status_is(200)->json_is('/can_view_audit', 1);
  }

  my $total = $all->()->size;
  $t->get_ok('/pagination/audit?filter=perl-Mojolicious&limit=2')
    ->status_is(200)
    ->json_is('/total',               $total)
    ->json_is('/page/0/type',         'limitation.removed')
    ->json_is('/page/0/package',      undef)
    ->json_is('/page/0/package_name', 'perl-Mojolicious')
    ->json_is('/page/1/type',         'review.decision')
    ->json_is('/page/2',              undef);
  my $of_one = $db->query('SELECT count(*) FROM audit_events WHERE package = 1')->array->[0];
  $t->get_ok('/pagination/audit?filter=1')->status_is(200)->json_is('/total', $of_one);
  $t->get_ok('/pagination/audit?filter=Mojolicious')->status_is(200)->json_is('/total', 0);
  $t->get_ok('/pagination/audit?filter=99999999999999999999')->status_is(200)->json_is('/total', 0);
  $t->get_ok("/pagination/audit?filter=perl-Mojolicious&offset=$total")
    ->status_is(200)
    ->json_is('/total', $total)
    ->json_is('/page',  []);
};

subtest 'A decision made while the automatic review runs is kept' => sub {
  local $app->config->{acceptable_packages} = [];
  $set_roles->('lawyer');
  my $n    = $all->()->size;
  my $slow = \&Cavil::Task::Analyze::_smallest_delta;
  my $decided;
  no warnings 'redefine';
  local *Cavil::Task::Analyze::_smallest_delta = sub {
    $t->post_ok('/reviews/review_package/1' => form => {unacceptable => 1, comment => 'Meanwhile'})->status_is(200)
      unless $decided++;
    return $slow->(@_);
  };
  my $logs = $app->log->capture('trace');
  $app->minion->enqueue(analyzed => [1]);
  $app->minion->perform_jobs_in_foreground;

  ok $decided, 'decided during the delta search';
  my $pkg = $pkgs->find(1);
  is $pkg->{state},  'unacceptable', 'decision kept';
  is $pkg->{result}, 'Meanwhile',    'comment kept';
  like $logs, qr/Automatic review skipped, the package was reviewed meanwhile/, 'skip logged';
  is_deeply [map { $decision->($_) } @{$since->($n)}],
    [['review.decision', $tester, 'new', 'unacceptable', 'Meanwhile', 0]], 'only the human decision';
};

subtest 'A fasttrack does not overwrite a decision made meanwhile' => sub {
  $t->post_ok('/packages/import/1' => $bot => form => {state => 'new'})->status_is(200);
  $app->minion->perform_jobs;
  is $pkgs->find(1)->{state}, 'acceptable', 'accepted again';

  $set_roles->('manager');
  my $lookup = \&Cavil::Model::Notes::limitations;
  no warnings 'redefine';
  local *Cavil::Model::Notes::limitations = sub {
    $pkgs->update(
      {id => 1, state => 'unacceptable', result => 'Meanwhile', reviewing_user => $tester, review_timestamp => 1});
    return $lookup->(@_);
  };
  $t->post_ok('/reviews/fasttrack_package/1' => form => {comment => 'Quick'})
    ->status_is(409)
    ->json_is('/error', 'Package has been reviewed meanwhile');
  is $pkgs->find(1)->{result}, 'Meanwhile', 'decision kept';
};

subtest 'Purged ephemeral reviews leave no trace' => sub {
  $db->query("UPDATE bot_packages SET ephemeral = true, state = 'unacceptable' WHERE id = 2");
  ok $db->query('SELECT count(*) FROM audit_events WHERE package = 2')->array->[0], 'has events';
  $app->minion->enqueue(purge_batch => [2]);
  $app->minion->perform_jobs;
  ok !$pkgs->find(2), 'purged';
  is $db->query('SELECT count(*) FROM audit_events WHERE package = 2')->array->[0], 0, 'events gone';
};

done_testing;
