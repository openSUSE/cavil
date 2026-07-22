# SPDX-FileCopyrightText: 2026 SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Mojo::Base -strict, -signatures;

use FindBin;
use lib "$FindBin::Bin/lib";

use Test::More;
use Test::Mojo;
use Cavil::Test;

plan skip_all => 'set TEST_ONLINE to enable this test' unless $ENV{TEST_ONLINE};

my $cavil_test = Cavil::Test->new(online => $ENV{TEST_ONLINE}, schema => 'classify_autotrigger_test');
my $t          = Test::Mojo->new(Cavil => $cavil_test->default_config);
my $app        = $t->app;
$cavil_test->package_with_snippets_fixtures($app);
my $db     = $app->pg->db;
my $minion = $app->minion;

# Run just the analyze job for package 1, leaving whatever it enqueues (in particular a classify job)
# untouched in the queue - so we can observe the enqueue decision without ever running classify against a
# (non-existent) classifier server.
my $analyze_once = sub {
  my $id     = $minion->enqueue(analyze => [1]);
  my $worker = $minion->worker->register;
  if (my $job = $worker->dequeue(0, {id => $id})) { $job->perform }
  $worker->unregister;
};

subtest 'no classify job is enqueued without a configured classifier' => sub {
  $minion->enqueue(unpack => [1]);
  $minion->perform_jobs;    # unpack -> index (creates snippets) -> analyze
  ok $db->query('SELECT 1 FROM snippets WHERE classified = FALSE LIMIT 1')->rows,
    'indexing created unclassified snippets';
  is $minion->jobs({tasks => ['classify']})->total, 0, 'analysis did not enqueue classify (none is configured)';
};

subtest 'analysis enqueues classify when one is configured, coalesced to a single pending run' => sub {
  $app->classifier->url('http://127.0.0.1:5000');    # configured; the job itself is never run here

  $analyze_once->();
  is $minion->jobs({tasks => ['classify'], states => ['inactive']})->total, 1, 'analysis enqueued a classify job';

  $analyze_once->();
  is $minion->jobs({tasks => ['classify'], states => ['inactive']})->total, 1,
    'a second analysis does not pile on a duplicate while one is still pending';
};

done_testing;
