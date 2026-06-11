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
use Cavil::ReportUtil qw(report_checksum);
use Mojo::File        qw(path);

plan skip_all => 'set TEST_ONLINE to enable this test' unless $ENV{TEST_ONLINE};

my $cavil_test = Cavil::Test->new(online => $ENV{TEST_ONLINE}, schema => 'index_test');
my $config     = $cavil_test->default_config;
my $t          = Test::Mojo->new(Cavil => $config);
$cavil_test->mojo_fixtures($t->app);

# Changes entry about 6.57 fixing copyright notices
$t->app->packages->ignore_line({package => 'perl-Mojolicious', hash => '81efb065de14988c4bd808697de1df51'});

subtest 'Cannot analyze before indexing' => sub {
  my $analyze_id = $t->app->minion->enqueue(analyze => [1]);
  $t->app->minion->perform_jobs;
  my $analyze_job = $t->app->minion->job($analyze_id);
  is $analyze_job->task,          'analyze',  'right task';
  is $analyze_job->info->{state}, 'finished', 'job is finished';
  like $analyze_job->info->{result}, qr/Package 1 is not indexed yet/, 'not yet indexed';

  my $analyzed_id = $t->app->minion->enqueue(analyzed => [1]);
  $t->app->minion->perform_jobs;
  my $analyzed_job = $t->app->minion->job($analyzed_id);
  is $analyzed_job->task,          'analyzed', 'right task';
  is $analyzed_job->info->{state}, 'finished', 'job is finished';
  like $analyzed_job->info->{result}, qr/Package 1 is not indexed yet/, 'not yet indexed';
};

# Unpack and index with the job queue
my $unpack_id = $t->app->minion->enqueue(unpack => [1]);
my $db        = $t->app->pg->db;
ok !$db->select('emails',       ['id'], {email => 'sri@cpan.org'})->rows,           'email address does not exist';
ok !$db->select('urls',         ['id'], {url   => 'http://mojolicious.org'})->rows, 'URL does not exist';
ok !$db->select('bot_packages', ['unpacked'], {id => 1})->hash->{unpacked},         'not unpacked';
$t->app->minion->perform_jobs;
my $unpack_job = $t->app->minion->job($unpack_id);
is $unpack_job->task,           'unpack',   'right task';
is $unpack_job->info->{state},  'finished', 'job is finished';
is $unpack_job->info->{result}, undef,      'job was successful';
my $index_id  = $unpack_job->info->{children}[0];
my $index_job = $t->app->minion->job($index_id);
is $index_job->task,           'index',    'right task';
is $index_job->info->{state},  'finished', 'job is finished';
is $index_job->info->{result}, undef,      'job was successful';
my @batch_ids  = @{$index_job->info->{children}};
my @batch_jobs = map { $t->app->minion->job($_) } @batch_ids;
is $batch_jobs[0]->task,           'index_batch', 'right task';
is $batch_jobs[0]->info->{state},  'finished',    'job is finished';
is $batch_jobs[0]->info->{result}, undef,         'job was successful';
is $batch_jobs[1]->task,           'index_batch', 'right task';
is $batch_jobs[1]->info->{state},  'finished',    'job is finished';
is $batch_jobs[1]->info->{result}, undef,         'job was successful';
is $batch_jobs[2]->task,           'index_batch', 'right task';
is $batch_jobs[2]->info->{state},  'finished',    'job is finished';
is $batch_jobs[2]->info->{result}, undef,         'job was successful';
is $batch_jobs[3],                 undef,         'no more jobs';
my $indexed_id  = $batch_jobs[0]->info->{children}[0];
my $indexed_job = $t->app->minion->job($indexed_id);
is $indexed_job->task,           'indexed',  'right task';
is $indexed_job->info->{state},  'finished', 'job is finished';
is $indexed_job->info->{result}, undef,      'job was successful';
my $analyze_id  = $indexed_job->info->{children}[0];
my $analyze_job = $t->app->minion->job($analyze_id);
is $analyze_job->task,           'analyze',  'right task';
is $analyze_job->info->{state},  'finished', 'job is finished';
is $analyze_job->info->{result}, undef,      'job was successful';
my $analyzed_id  = $analyze_job->info->{children}[0];
my $analyzed_job = $t->app->minion->job($analyzed_id);
is $analyzed_job->task,                 'analyzed', 'right task';
is $analyzed_job->info->{state},        'finished', 'job is finished';
is $analyzed_job->info->{result},       undef,      'job was successful';
is $t->app->packages->find(1)->{state}, 'new',      'still new';


# Check shortname (3 missing snippets)
like $t->app->packages->find(1)->{checksum}, qr/^Artistic-2.0-9:\w+/, 'right shortname';

# Check email addresses and URLs
ok $db->select('emails', ['id'], {email => 'sri@cpan.org'})->rows, 'email address has been added';
is $db->select('urls', ['hits'], {url => 'http://mojolicious.org'})->hash->{hits}, 154, 'URL has been added';
my $long = 'e2%98%83@xn--n3h.xn--n3h.de';
is $db->select('emails', ['id'], {email => $long})->hash, undef, 'email address is too long';
$long = 'https://cdn.rawgit.com/google/code-prettify/master/loader/prettify.css';
is $db->select('urls', ['hits'], {url => $long})->hash, undef, 'URL is too long';

# Check files
my $file_id = $db->select('matched_files', ['id'], {filename => 'Mojolicious-7.25/lib/Mojolicious.pm'})->hash->{id};
ok $file_id,                                                               'file has been added';
ok $db->select('bot_packages', ['unpacked'], {id => 1})->hash->{unpacked}, 'unpacked';

# Verify report checksum
my $specfile = $t->app->reports->specfile_report(1);
my $dig      = $t->app->reports->dig_report(1);
is report_checksum($specfile, $dig), '7d2fa36eff75adc8d7c309b8ff025992', 'right checksum';

# Check matches
my $res = $db->select(
  ['pattern_matches', ['matched_files', id => 'file']],
  ['sline',           'pattern'],
  {
        'matched_files.filename' => 'Mojolicious-7.25/lib/Mojolicious/resources/'
      . 'public/mojo/prettify/run_prettify.processed.js'
  },
  {order_by => 'sline'}
)->arrays;
is_deeply $res, [[5, 2], [7, 1], [19, 2], [21, 1]], 'JavaScript correctly tagged Apache';
$res = $db->select(
  ['pattern_matches', ['matched_files', id => 'file']],
  ['sline',           'pattern'],
  {'matched_files.filename' => 'Mojolicious-7.25/lib/Mojolicious.pm'},
  {order_by                 => 'sline'}
)->arrays;
is_deeply $res, [[751, 2], [1103, 5]], 'Perl correctly tagged Artistic';

subtest 'Make sure there are no leftover .processed files' => sub {
  my $dir = path($t->app->config->{checkout_dir}, 'perl-Mojolicious', 'c7cfdab0e71b0bebfdf8b2dc3badfecd', '.unpacked');
  ok -e $dir->child('perl-Mojolicious.spec'),                                'main file exists';
  ok -e $dir->child('perl-Mojolicious.processed.spec'),                      'processed file exists';
  ok -e $dir->child('Mojolicious-7.25', 'lib', 'Mojolicious.pm'),            'main file exists';
  ok !-e $dir->child('Mojolicious-7.25', 'lib', 'Mojolicious.processed.pm'), 'processed file does not exist';
};


# Raise acceptable risk
$config->{acceptable_risk} = 5;
$t = Test::Mojo->new(Cavil => $config);

# License management requires a login
$t->get_ok('/licenses/edit_pattern/1')->status_is(403)->content_like(qr/Permission/);
$t->get_ok('/login')->status_is(302)->header_is(Location => '/');
$t->get_ok('/licenses/edit_pattern/1')->status_is(200)->content_like(qr/License/);

subtest 'Pattern change' => sub {
  $t->get_ok('/licenses/edit_pattern/1')->status_is(200)->element_exists('#edit-pattern[data-pattern]');
  $t->get_ok('/licenses/pattern/1.json')
    ->status_is(200)
    ->json_is('/license'   => 'Apache-2.0')
    ->json_is('/pattern'   => 'You may obtain a copy of the License at')
    ->json_is('/patent'    => 0)
    ->json_is('/trademark' => 0);
  $t->post_ok('/licenses/update_pattern/1' => form => {license => 'Apache-2.0', pattern => 'real-time web framework'})
    ->status_is(302)
    ->header_is(Location => '/licenses/edit_pattern/1');
  $t->get_ok('/licenses/Apache-2.0')
    ->status_is(200)
    ->element_exists('#license-details')
    ->text_like('.alert-success' => qr/Pattern has been updated, reindexing all affected packages/);
  $t->get_ok('/licenses/meta/Apache-2.0')->status_is(200)->json_is('/display_license' => 'Apache-2.0');
  my $patterns = $t->tx->res->json->{patterns};
  my ($pattern) = grep { $_->{id} == 1 } @$patterns;
  is $pattern->{pattern}, 'real-time web framework', 'license meta includes updated pattern';
  ok exists $pattern->{matches_capped},  'license meta includes match cap marker';
  ok exists $pattern->{packages_capped}, 'license meta includes package cap marker';

  $t->post_ok('/licenses/update_patterns' => form => {license => 'Apache-2.0', spdx => 'Apache-2'})
    ->status_is(302)
    ->header_is(Location => '/licenses/Apache-2.0');
  $t->get_ok('/licenses/Apache-2.0')
    ->status_is(200)
    ->element_exists('#license-details')
    ->text_like('.alert-danger' => qr/not a valid SPDX expression/);

  $t->post_ok('/licenses/update_patterns' => form => {license => 'Apache-2.0', spdx => 'Apache-2.0'})
    ->status_is(302)
    ->header_is(Location => '/licenses/Apache-2.0');
  $t->get_ok('/licenses/Apache-2.0')
    ->status_is(200)
    ->element_exists('#license-details')
    ->text_like('.alert-success' => qr/2 patterns have been updated/);
  $t->get_ok('/licenses/meta/Apache-2.0')->status_is(200)->json_is('/spdx' => 'Apache-2.0');
};

subtest 'Pattern detail JSON endpoint' => sub {
  $t->get_ok('/licenses/pattern/1.json')
    ->status_is(200)
    ->json_is('/id'      => 1)
    ->json_is('/license' => 'Apache-2.0')
    ->json_is('/pattern' => 'real-time web framework')
    ->json_has('/risk')
    ->json_has('/spdx');

  $t->get_ok('/licenses/pattern/999999.json')->status_is(404);

  # Logging out must put the JSON endpoint back behind the login wall.
  $t->get_ok('/logout')->status_is(302);
  $t->get_ok('/licenses/pattern/1.json')->status_is(401)->content_like(qr/Login Required/);
  $t->get_ok('/login')->status_is(302);
};

subtest 'Pattern match count JSON endpoint' => sub {
  $t->get_ok('/licenses/pattern/1/match_count.json')->status_is(200)->json_has('/matches')->json_has('/packages');

  # Logging out must put the JSON endpoint back behind the login wall.
  $t->get_ok('/logout')->status_is(302);
  $t->get_ok('/licenses/pattern/1/match_count.json')->status_is(401)->content_like(qr/Login Required/);
  $t->get_ok('/login')->status_is(302);
};

subtest 'License detail JSON endpoint permissions' => sub {
  $t->get_ok('/licenses/meta/Apache-2.0')
    ->status_is(200)
    ->json_is('/license'   => 'Apache-2.0')
    ->json_is('/can_admin' => 1);

  $t->post_ok('/licenses/meta/Apache-2.0' => form => {license => 'Apache-2.0', spdx => 'Apache-2.0'})
    ->status_is(200)
    ->json_is('/updated' => 2);

  $t->get_ok('/logout')->status_is(302);
  $t->get_ok('/licenses/meta/Apache-2.0')
    ->status_is(200)
    ->json_is('/license'   => 'Apache-2.0')
    ->json_is('/can_admin' => 0);
  $t->post_ok('/licenses/meta/Apache-2.0' => form => {license => 'Apache-2.0', spdx => 'Apache-2.0'})
    ->status_is(403)
    ->content_like(qr/Permission/);
  $t->post_ok('/licenses/pattern/1.json' => form => {license => 'Apache-2.0', pattern => 'real-time web framework'})
    ->status_is(403)
    ->content_like(qr/Permission/);
  $t->get_ok('/login')->status_is(302);
};

# Automatic reindexing
my $list = $t->app->minion->backend->list_jobs(0, 10, {states => ['inactive']});
is $list->{total},         2,                       'two inactives job';
is $list->{jobs}[0]{task}, 'reindex_matched_later', 'right task';
is $list->{jobs}[1]{task}, 'pattern_stats',         'right task';
is_deeply $list->{jobs}[0]{args}, [1], 'right arguments';
my $reindex_id = $list->{jobs}[0]{id};
$t->app->minion->perform_jobs;
is $t->app->minion->job($reindex_id)->info->{state}, 'finished', 'job is finished';
ok -f $cavil_test->cache_dir->child('cavil.tokens'), 'cache initialized';
$res = $db->select(
  ['pattern_matches', ['matched_files', id => 'file']],
  ['sline',           'pattern'],
  {'matched_files.filename' => 'Mojolicious-7.25/lib/Mojolicious.pm'},
  {order_by                 => 'sline'}
)->arrays;
is_deeply $res, [[210, 1], [236, 1], [751, 2], [1103, 5]], 'Perl correctly tagged with new pattern';
$res = $db->select('snippets', ['hash'], {}, {order_by => 'hash'})->arrays;
is_deeply $res,
  [
  ["17ca85fa8cb6e7b6517e5e71470861cc"], ["23173dc0c404f298e5f20597697e5b19"],
  ["300a5e5e524c7a2daa8da898c2d4da54"], ["3c376fca10ff8a41d0d51c9d46a3bdae"],
  ["541e8cc6ac467ffcbb5b2c27088def98"]
  ],
  'Snippets inserted - ignored line ignored';

# Manual reindexing
$t->app->pg->db->query("update license_patterns set pattern = 'powerful' where id = 1");
$t->app->patterns->expire_cache;
$list = $t->app->minion->backend->list_jobs(0, 10, {tasks => ['index_later']});
is $list->{total}, 1, 'one index_later jobs';
$t->app->minion->enqueue('reindex_all');
$t->app->minion->perform_jobs;
$list = $t->app->minion->backend->list_jobs(0, 10, {tasks => ['index_later']});
is $list->{total},          3,          'three index_later jobs';
is $list->{jobs}[0]{state}, 'finished', 'right state';
is $list->{jobs}[1]{state}, 'finished', 'right state';
$res = $db->select(
  ['pattern_matches', ['matched_files', id => 'file']],
  ['sline',           'pattern'],
  {'matched_files.filename' => 'Mojolicious-7.25/lib/Mojolicious.pm'},
  {order_by                 => 'sline'}
)->arrays;
is_deeply $res, [[236, 1], [258, 1], [278, 1], [333, 1], [751, 2], [1103, 5]], 'Perl correctly tagged with new pattern';

$res = $db->select(
  ['pattern_matches', ['matched_files', id => 'file']],
  ['sline', 'pattern', 'ignored'],
  {'matched_files.filename' => 'Mojolicious-7.25/Changes'},
  {order_by                 => 'sline'}
)->arrays;
is_deeply $res, [[225, 6, 1], [2801, 1, 0]], 'Only one Changes entry is an ignored line';

my $pkg = $t->app->packages->find(1);
is $pkg->{state}, 'new', 'still snippets left';

# now 'classify'
$db->update('snippets', {classified => 1, license => 0});

subtest 'Accepted because of low risk (with human review)' => sub {
  $t->app->minion->enqueue('reindex_all');
  $t->app->minion->perform_jobs;

  my $pkg = $t->app->packages->find(1);
  is $pkg->{state}, 'new', 'not previously reviewed by a human';

  my $acceptable_id = $t->app->packages->add(
    name            => 'perl-Mojolicious',
    checkout_dir    => 'c7cfdab0e71b0bebfdf8b2dc3badfecd',
    api_url         => 'https://api.opensuse.org',
    requesting_user => 1,
    project         => 'devel:languages:perl',
    package         => 'perl-Mojolicious',
    srcmd5          => 'bd91c36647a5d3dd883d490da2140401',
    priority        => 5
  );
  $t->app->packages->imported($acceptable_id);
  $t->app->packages->unpacked($acceptable_id);
  $t->app->packages->indexed($acceptable_id);
  $t->app->packages->update({id => $acceptable_id, state => 'acceptable', reviewing_user => 2, obsolete => 1});
  $t->app->minion->enqueue('reindex_all');
  $t->app->minion->perform_jobs;

  $pkg = $t->app->packages->find(1);
  is $pkg->{state},  'acceptable',                       'automatically accepted';
  is $pkg->{result}, 'Accepted because of low risk (5)', 'because of low risk';
};

subtest 'Accept package because of its name' => sub {
  $db->update('bot_packages', {state => 'new'}, {id => 1});
  $pkg = $t->app->packages->find(1);
  is $pkg->{state}, 'new',              'new again';
  is $pkg->{name},  'perl-Mojolicious', 'rigth name';

  $t->app->config->{acceptable_packages} = ['perl-Mojolicious'];
  $t->app->minion->enqueue('reindex_all');
  $t->app->minion->perform_jobs;
  $t->app->config->{acceptable_packages} = [];

  $pkg = $t->app->packages->find(1);
  is $pkg->{state},  'acceptable',                                          'automatically accepted';
  is $pkg->{result}, 'Accepted because of package name (perl-Mojolicious)', 'because of name';
};

subtest 'Accept package because of auto-accept risk threshold' => sub {
  $db->update(
    'bot_packages',
    {
      state          => 'new',
      checksum       => 'Unknown-1:autotest',
      result         => undef,
      notice         => undef,
      reviewed       => undef,
      reviewing_user => undef
    },
    {id => 1}
  );
  my $pkg = $t->app->packages->find(1);
  is $pkg->{state}, 'new', 'new again';

  # Ensure no previous human review exists for this package name
  $db->query('UPDATE bot_packages SET reviewing_user = NULL WHERE name = ?', $pkg->{name});

  local $t->app->config->{auto_accept_risk} = 2;
  $t->app->minion->enqueue(analyzed => [1]);
  $t->app->minion->perform_jobs;

  $pkg = $t->app->packages->find(1);
  is $pkg->{state}, 'acceptable', 'automatically accepted';
  is $pkg->{result}, 'Accepted because of low risk (1) and auto-accept risk threshold (2)',
    'because of low risk threshold';
};

subtest 'Prevent index race condition' => sub {
  my $minion = $t->app->minion;
  ok my $job_id = $minion->enqueue('index', [1]), 'enqueued';
  $minion->perform_jobs;
  unlike $minion->job($job_id)->info->{result}, qr/Package \d+ is already being processed/, 'race condition prevented';
  ok $minion->lock('processing_pkg_1', 0), 'lock no longer exists';

  ok $job_id = $minion->enqueue('index', [1]), 'enqueued';
  my $guard = $minion->guard('processing_pkg_1', 172800);
  ok !$minion->lock('processing_pkg_1', 0), 'lock exists';
  my $worker = $minion->worker->register;
  ok my $job = $worker->dequeue(0, {id => $job_id}), 'job dequeued';
  is $job->execute, undef, 'no error';
  like $minion->job($job_id)->info->{result}, qr/Package \d+ is already being processed/, 'race condition prevented';
  $worker->unregister;
  undef $guard;
  ok $minion->lock('processing_pkg_1', 0), 'lock no longer exists';

  $guard = $minion->guard('processing_pkg_1', 172800);
  ok !$t->app->packages->reindex(1), 'not reindexing';
  undef $guard;
  ok $t->app->packages->reindex(1), 'reindexing';

  ok !$t->app->packages->reindex(99999), 'package does not exist';
};

subtest 'Reindex skips when an import or unpack is queued' => sub {
  my $minion = $t->app->minion;

  # Drain anything left over from prior subtests
  $minion->perform_jobs;

  for my $task (qw(obs_import git_import unpack)) {
    my $blocker = $minion->enqueue($task => [1] => {notes => {pkg_1 => 1}});
    ok !$t->app->packages->reindex(1), "reindex skipped while $task is inactive";
    is $minion->jobs({tasks => ['index'], states => ['inactive']})->total, 0, "no orphan index enqueued ($task)";
    $minion->backend->remove_job($blocker);
  }

  ok $t->app->packages->reindex(1), 'reindex proceeds once the queue is clear';
  $minion->perform_jobs;
};

subtest 'Index retries instead of failing when unpacked is transiently null' => sub {
  my $minion = $t->app->minion;
  my $db     = $t->app->pg->db;

  $minion->perform_jobs;

  # Simulate an unpack-in-progress: unpacked has just been cleared by _unpack
  # but the actual unpack work has not finished yet
  $db->update('bot_packages', {unpacked => undef}, {id => 1});

  my $job_id = $minion->enqueue('index', [1]);
  my $worker = $minion->worker->register;
  my $job    = $worker->dequeue(0, {id => $job_id});
  is $job->execute, undef, 'no error from execute';
  $worker->unregister;

  my $info = $minion->job($job_id)->info;
  is $info->{state},   'inactive', 'job was retried instead of failed';
  is $info->{retries}, 1,          'retried once';
  is $info->{result},  undef,      'no failure result yet';

  # Simulate the unpack finishing (sets unpacked) and the delay expiring so the
  # retried job becomes ready for a worker again
  $db->update('bot_packages', {unpacked => \'now()'}, {id => 1});
  $db->update('minion_jobs',  {delayed  => \'now()'}, {id => $job_id});

  $minion->perform_jobs;
  is $minion->job($job_id)->info->{state}, 'finished', 'retried job eventually succeeds';
};

subtest 'Index gives up after too many retries' => sub {
  my $minion = $t->app->minion;
  my $db     = $t->app->pg->db;

  $minion->perform_jobs;
  $db->update('bot_packages', {unpacked => undef}, {id => 1});

  my $job_id = $minion->enqueue('index', [1]);

  # Burn through the retry budget without waiting on real delays
  for my $attempt (1 .. 11) {
    $db->update('minion_jobs', {delayed => \'now()'}, {id => $job_id});
    my $worker = $minion->worker->register;
    my $job    = $worker->dequeue(0, {id => $job_id});
    last unless $job;
    $job->execute;
    $worker->unregister;
  }

  my $info = $minion->job($job_id)->info;
  is $info->{state}, 'failed', 'job eventually fails when unpack never completes';
  like $info->{result}, qr/gave up after \d+ retries/, 'result mentions retry exhaustion';

  $db->update('bot_packages', {unpacked => \'now()'}, {id => 1});
};

done_testing();
