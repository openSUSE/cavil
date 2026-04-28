# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Mojo::Base -strict;

use FindBin;
use lib "$FindBin::Bin/lib";

use Test::More;
use Test::Mojo;
use Cavil::Test;

plan skip_all => 'set TEST_ONLINE to enable this test' unless $ENV{TEST_ONLINE};

my $cavil_test = Cavil::Test->new(online => $ENV{TEST_ONLINE}, schema => 'analyze_test');
my $t          = Test::Mojo->new(Cavil => $cavil_test->default_config);
$cavil_test->mojo_fixtures($t->app);

subtest 'Analyze background job' => sub {
  $t->app->minion->enqueue(unpack => [1]);
  $t->app->minion->perform_jobs;

  # Set the first version to acceptable
  my $pkg = $t->app->packages->find(1);
  $pkg->{reviewing_user}   = 1;
  $pkg->{result}           = 'Sure';
  $pkg->{state}            = 'acceptable';
  $pkg->{review_timestamp} = 1;
  $t->app->packages->update($pkg);

  $t->app->minion->enqueue(unpack => [2]);
  $t->app->minion->perform_jobs;

  my $res = $t->app->pg->db->select('bot_packages', '*', {id => 2})->hashes->[0];
  is $res->{result}, undef,                                                                         'result cleared';
  is $res->{notice}, "Diff to closest match 1:\n\n  Different spec file license: Artistic-2.0\n\n", 'different spec';
  is $res->{state},  'new',                                                                         'not approved';
};

subtest 'Analyze clears stale notice when reusing a previous accepted review' => sub {
  my $pkgs = $t->app->packages;
  my $db   = $t->app->pg->db;
  my $pkg1 = $pkgs->find(1);

  my $pkg3_id = $pkgs->add(
    name            => 'perl-Mojolicious',
    checkout_dir    => $pkg1->{checkout_dir},
    api_url         => 'https://api.opensuse.org',
    requesting_user => 1,
    project         => 'devel:languages:perl',
    package         => 'perl-Mojolicious',
    srcmd5          => $pkg1->{checkout_dir},
    priority        => 5
  );

  $db->query(
    'INSERT INTO bot_reports (package, ldig_report, specfile_report, rolemodel)
     SELECT ?, ldig_report, specfile_report, rolemodel FROM bot_reports WHERE package = ?', $pkg3_id, 1
  );
  $db->query('UPDATE bot_packages SET indexed = NOW(), checksum = ?, notice = ? WHERE id = ?',
    $pkg1->{checksum}, 'stale notice', $pkg3_id);

  $t->app->minion->enqueue(analyzed => [$pkg3_id]);
  $t->app->minion->perform_jobs;

  my $res = $pkgs->find($pkg3_id);
  is $res->{state},  'acceptable',                                                      'approved from previous review';
  is $res->{notice}, undef,                                                             'stale notice cleared';
  is $res->{result}, 'Accepted because previously reviewed under the same license (1)', 'reused previous review';
};

subtest 'Prevent analyze race condition' => sub {
  my $minion = $t->app->minion;
  ok my $job_id = $minion->enqueue('analyze', [1]);
  my $guard = $minion->guard('processing_pkg_1', 172800);
  ok !$minion->lock('processing_pkg_1', 0), 'lock exists';
  my $worker = $minion->worker->register;
  ok my $job = $worker->dequeue(0, {id => $job_id}), 'job dequeued';
  is $job->execute, undef, 'no error';
  like $minion->job($job_id)->info->{result}, qr/Package \d+ is already being processed/, 'race condition prevented';
  $worker->unregister;
  undef $guard;
  ok $minion->lock('processing_pkg_1', 0), 'lock no longer exists';
};

done_testing;
