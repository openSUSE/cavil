# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Mojo::Base -strict, -signatures;

use FindBin;
use lib "$FindBin::Bin/lib";

use Test::More;
use Test::Mojo;
use Cavil::Test;
use Cavil::Util qw(PRIORITY_INCOMING PRIORITY_SWEEP PRIORITY_UPKEEP PRIORITY_WAITING);

plan skip_all => 'set TEST_ONLINE to enable this test' unless $ENV{TEST_ONLINE};

# The job queue runs the highest priority first and breaks ties in arrival order, so the band a build
# starts at is the whole difference between a reviewer getting their report in a minute and getting it
# after a sweep of the archive. These tests come in through the entry points that set a band - the Bot
# API, the Reindex button, a batch of new patterns, the weekly sweep - and check where each of them
# actually puts the package.
my $cavil_test = Cavil::Test->new(online => $ENV{TEST_ONLINE}, schema => 'job_priorities_test');
my $config     = $cavil_test->default_config;
my $t          = Test::Mojo->new(Cavil => $config);
my $app        = $t->app;
$cavil_test->mojo_fixtures($app);

my $minion = $app->minion;
my $pkgs   = $app->packages;

# The waiting jobs of one task, oldest first, as [priority, package id] pairs
sub waiting ($task) {
  my $jobs = $minion->jobs({tasks => [$task], states => ['inactive']});
  my @queued;
  while (my $info = $jobs->next) { unshift @queued, [$info->{priority}, $info->{args}[0]] }
  return \@queued;
}

sub drain () { $minion->perform_jobs }

# Run just the queued jobs of one task, so the jobs they enqueue can be looked at before they run too
sub run_task ($task) {
  my $worker = $minion->worker->register;
  my $ran    = 0;
  while (my $info = $minion->jobs({tasks => [$task], states => ['inactive']})->next) {
    last unless my $job = $worker->dequeue(0, {id => $info->{id}});
    my $err = $job->execute;
    $err ? $job->fail($err) : $job->finish;
    is $err, undef, "job $task was successful";
    $ran++;
  }
  $worker->unregister;
  return $ran;
}

subtest 'A package coming in through the Bot API starts at the incoming band' => sub {
  my $form = {type => 'git', api => 'https://src.opensuse.org', package => 'perl-Mojolicious', rev => 'abc123'};
  $t->post_ok('/packages' => {Authorization => 'Token test_token'} => form => $form)->status_is(200);
  is_deeply waiting('git_import'), [[PRIORITY_INCOMING, 3]], 'imported at the incoming band';

  # A request that says it is urgent carries its own review priority all the way into the queue
  $form->{rev}      = 'def456';
  $form->{priority} = 10;
  $t->post_ok('/packages' => {Authorization => 'Token test_token'} => form => $form)->status_is(200);
  is_deeply waiting('git_import'), [[PRIORITY_INCOMING, 3], [10, 4]], 'the urgent request outranks the ordinary one';

  # Neither of them can be downloaded here, and the packages are not part of the rest of this test
  my $imports = $minion->jobs({tasks => ['git_import']});
  while (my $info = $imports->next) { $minion->backend->remove_job($info->{id}) }
  $pkgs->update({id => $_, obsolete => 1}) for 3, 4;
};

subtest 'Every step of a build outranks the step before it' => sub {
  ok $pkgs->unpack(1, PRIORITY_INCOMING), 'unpack enqueued at the incoming band';

  my %highest;
  my $worker = $minion->worker->register;
  while (my $job = $worker->dequeue(0)) {
    my $prio = $job->info->{priority};
    $highest{$job->task} = $prio if !exists $highest{$job->task} || $prio > $highest{$job->task};
    my $err = $job->execute;
    $err ? $job->fail($err) : $job->finish;
    is $err, undef, 'job @{[$job->task]} was successful';
  }
  $worker->unregister;

  is $highest{unpack},      PRIORITY_INCOMING,     'the unpack is the band itself';
  is $highest{index},       PRIORITY_INCOMING + 1, 'indexing is a step above it';
  is $highest{index_batch}, PRIORITY_INCOMING + 2, 'the batches are a step above that';
  is $highest{indexed},     PRIORITY_INCOMING + 3, 'and so on to the report';
  is $highest{analyze},     PRIORITY_INCOMING + 4, 'the analyze that promotes the report';
  is $highest{analyzed},    PRIORITY_INCOMING + 5, 'and the auto-acceptance check behind it';

  ok $pkgs->find(1)->{indexed}, 'package has a report now';
};

subtest 'The Reindex button puts the reviewer in front of the incoming queue' => sub {
  $t->get_ok('/login')->status_is(302);

  # A backlog of imports is what a reviewer would otherwise be stuck behind
  ok $pkgs->unpack(2, PRIORITY_INCOMING), 'an import is already queued';

  $t->post_ok('/reviews/reindex/1')->status_is(200)->json_is('/ok' => 1)->json_is('/queued' => 'now');
  is_deeply waiting('index'), [[PRIORITY_WAITING, 1]], 'the rebuild is at the waiting band';

  drain();
};

subtest 'A rebuild that has to wait its turn keeps the band it was asked for' => sub {
  ok my $guard = $pkgs->claim_guard(1, 999999), 'something else has the package';

  is $pkgs->reindex(1, PRIORITY_WAITING), 'later', 'the rebuild cannot start yet';
  is_deeply waiting('index'), [], 'and nothing is queued for it';

  # The weekly sweep coming along in the meantime must not pull the reviewer's rebuild down with it
  is $pkgs->reindex(1, PRIORITY_SWEEP), 'later', 'the sweep finds the package busy too';

  undef $guard;
  $pkgs->hand_back(1, 999999);
  is_deeply waiting('index'), [[PRIORITY_WAITING, 1]], 'the rebuild runs at the band the reviewer asked for';
  is $pkgs->find(1)->{reindex_requested}, undef, 'and the request is settled';

  drain();
};

subtest 'A request that outranks a queued rebuild moves it up' => sub {
  ok $pkgs->reindex(1, PRIORITY_SWEEP), 'the sweep got there first';
  is_deeply waiting('index'), [[PRIORITY_SWEEP, 1]], 'queued at the sweep band';

  # There is no second rebuild to enqueue - the one that is waiting does the same work - but leaving it
  # where the sweep put it would cost the reviewer the whole archive's worth of queue
  is $pkgs->reindex(1, PRIORITY_WAITING), 'now', 'the reviewer asks for the same rebuild';
  is_deeply waiting('index'), [[PRIORITY_WAITING, 1]], 'the queued rebuild is moved up instead of duplicated';

  # And it does not slide back down again when the sweep comes round once more
  is $pkgs->reindex(1, PRIORITY_SWEEP), 'now', 'the sweep asks again';
  is_deeply waiting('index'), [[PRIORITY_WAITING, 1]], 'the rebuild stays where the reviewer put it';

  drain();
};

subtest 'The weekly sweep goes in at the bottom' => sub {
  $minion->enqueue('reindex_all');
  is run_task('reindex_all'), 1, 'the sweep ran';

  # Turning tens of thousands of packages into rebuilds is left to the queue, one helper job each, and
  # those helpers sit below the rebuilds they produce so a package already being rebuilt is finished first
  is_deeply [map { $_->[0] } @{waiting('index_later')}], [PRIORITY_SWEEP - 1, PRIORITY_SWEEP - 1],
    'a helper job per package, one below the sweep band';

  is run_task('index_later'), 2, 'both helpers ran';
  is_deeply [sort map { $_->[0] } @{waiting('index')}], [PRIORITY_SWEEP, PRIORITY_SWEEP],
    'both packages are queued at the sweep band';

  drain();
};

subtest 'New patterns rebuild the report they came from first' => sub {
  drain();
  my $snippet_id
    = $app->pg->db->query('SELECT snippet FROM file_snippets WHERE package = 1 ORDER BY snippet LIMIT 1')->array->[0];
  ok $snippet_id, 'package 1 has a snippet to decide on';
  my $affected = $app->snippets->packages_for_snippet($snippet_id);
  is_deeply [sort { $a <=> $b } @$affected], [1, 2], 'both packages share it';

  $t->post_ok(
    '/snippet/batch_decision' => json => {
      report  => 1,
      actions => [
        {
          kind      => 'create-pattern',
          snippetId => $snippet_id,
          formData  => {license => 'MIT', pattern => 'Some unmistakable license text', risk => 5}
        }
      ]
    }
  )->status_is(200)->json_is('/ok' => 1);

  is_deeply waiting('index'), [[PRIORITY_WAITING, 1], [PRIORITY_UPKEEP, 2]],
    'the report the reviewer submitted from is rebuilt first, the other package as upkeep';

  drain();
};

subtest 'Curating a pattern from the license editor is upkeep for everybody' => sub {
  my $pattern = $app->patterns->create(pattern => 'Another unmistakable license text', license => 'MIT');
  ok my $id = $pattern->{id}, 'pattern created';
  drain();

  $t->post_ok("/licenses/update_pattern/$id" => form =>
      {license => 'MIT', pattern => 'Another unmistakable license text, revised', risk => 5})->status_is(302);

  # Finding out which packages a pattern matches is a job of its own, and it has to sit below the
  # rebuilds it produces so a package that is already being rebuilt is finished first
  is_deeply [map { $_->[0] } @{waiting('reindex_matched_later')}], [PRIORITY_UPKEEP - 1],
    'the fan-out job is one below the upkeep band';

  drain();
};

done_testing;
