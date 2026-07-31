# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Mojo::Base -strict, -signatures;

use FindBin;
use lib "$FindBin::Bin/lib";

use Test::More;
use Test::Mojo;
use Cavil::Test;
use Cavil::Util qw(incoming_priority PRIORITY_INCOMING PRIORITY_SWEEP PRIORITY_UPKEEP PRIORITY_WAITING);

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

  # The review priority a request carries moves it around inside the band and nowhere else, so an urgent
  # request is handled first among the packages arriving with it, and a product import at the bottom of the
  # scale is still an arriving package rather than a piece of upkeep
  $form->{rev}      = 'def456';
  $form->{priority} = 10;
  $t->post_ok('/packages' => {Authorization => 'Token test_token'} => form => $form)->status_is(200);
  $form->{rev}      = 'fed789';
  $form->{priority} = 1;
  $t->post_ok('/packages' => {Authorization => 'Token test_token'} => form => $form)->status_is(200);
  is_deeply waiting('git_import'), [[PRIORITY_INCOMING, 3], [PRIORITY_INCOMING + 5, 4], [PRIORITY_INCOMING - 4, 5]],
    'all three are in the incoming band, the urgent one at the top of it';
  ok PRIORITY_INCOMING - 4 > PRIORITY_UPKEEP + 7, 'even the lowest of them outranks any build the upkeep band can run';

  # None of them can be downloaded here, and the packages are not part of the rest of this test
  my $imports = $minion->jobs({tasks => ['git_import']});
  while (my $info = $imports->next) { $minion->backend->remove_job($info->{id}) }
  $pkgs->update({id => $_, obsolete => 1}) for 3, 4, 5;
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
    is $err, undef, "job @{[$job->task]} was successful";
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

subtest 'A pattern fan-out never gets in front of a package arriving while it runs' => sub {
  drain();

  # What went wrong in production: a batch of new patterns was accepted, every package they touched was
  # queued for a rebuild, and rebuilding things the size of chromium takes hours. Everything arriving in the
  # meantime was stuck behind them - including the product imports that come in at the very bottom of the
  # review priority scale, which is where most of the archive arrives from.
  my $pid
    = $app->pg->db->query(
    'SELECT pattern FROM pattern_matches GROUP BY pattern ORDER BY COUNT(DISTINCT package) DESC, pattern LIMIT 1')
    ->array->[0];
  ok $pid, 'the packages match a pattern somebody could curate';
  my $pattern = $app->patterns->find($pid);
  $t->post_ok("/licenses/update_pattern/$pid" => form =>
      {license => $pattern->{license}, pattern => "$pattern->{pattern} (revised)", risk => $pattern->{risk}})
    ->status_is(302);
  is run_task('pattern_stats'),         1, 'the tf-idf bag is rebuilt';
  is run_task('reindex_matched_later'), 1, 'the fan-out ran';
  my $fanout = @{waiting('index_later')};
  ok $fanout > 1, 'more than one package is being rebuilt because of the pattern';
  is run_task('index_later'), $fanout, 'every one of them is queued';

  # A product import turns up while they are queued, at the lowest review priority there is
  my $form
    = {type => 'git', api => 'https://src.opensuse.org', package => 'perl-Mojolicious', rev => '0ff1ce', priority => 1};
  $t->post_ok('/packages' => {Authorization => 'Token test_token'} => form => $form)->status_is(200);
  is_deeply waiting('git_import'), [[incoming_priority(1), 6]], 'the import is in the incoming band';

  my $worker = $minion->worker->register;
  ok my $import = $worker->dequeue(0), 'a worker picks up the next job';
  is $import->task, 'git_import', 'the arriving package goes first, ahead of every rebuild the pattern caused';

  # Nothing to download here, and the package is not part of the rest of this test
  $import->finish;
  $pkgs->update({id => 6, obsolete => 1});

  # And the rebuilds cannot climb into the band it came in at, however many jobs they take to finish
  my $highest = 0;
  while (my $job = $worker->dequeue(0)) {
    my $prio = $job->info->{priority};
    $highest = $prio if $prio > $highest;
    my $err = $job->execute;
    $err ? $job->fail($err) : $job->finish;
    is $err, undef, "job @{[$job->task]} was successful";
  }
  $worker->unregister;

  is $highest, PRIORITY_UPKEEP + 4, 'the tallest rebuild climbed four steps above the upkeep band';
  ok $highest < incoming_priority(1), 'and stayed below the package that arrived in the middle of it';
};

done_testing;
