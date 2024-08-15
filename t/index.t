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
is report_checksum($specfile, $dig), '42af80e97542a008844a74245b19a147', 'right checksum';

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
  $t->get_ok('/licenses/edit_pattern/1')->status_is(200)->element_exists('input[name=license][value=Apache-2.0]')
    ->text_is('textarea[name=pattern]' => 'You may obtain a copy of the License at')
    ->element_exists_not('input:checked');
  $t->post_ok('/licenses/update_pattern/1' => form => {license => 'Apache-2.0', pattern => 'real-time web framework'})
    ->status_is(302)->header_is(Location => '/licenses/edit_pattern/1');
  $t->get_ok('/licenses/Apache-2.0')->status_is(200)->element_exists('div div a[href=/licenses/edit_pattern/1]')
    ->text_is('div pre' => 'real-time web framework')
    ->text_like('.alert-success' => qr/Pattern has been updated, reindexing all affected packages/);

  $t->post_ok('/licenses/update_patterns' => form => {license => 'Apache-2.0', spdx => 'Apache-2'})->status_is(302)
    ->header_is(Location => '/licenses/Apache-2.0');
  $t->get_ok('/licenses/Apache-2.0')->status_is(200)->element_exists('div div a[href=/licenses/edit_pattern/1]')
    ->text_is('div pre' => 'real-time web framework')->text_like('.alert-danger' => qr/not a valid SPDX expression/);

  $t->post_ok('/licenses/update_patterns' => form => {license => 'Apache-2.0', spdx => 'Apache-2.0'})->status_is(302)
    ->header_is(Location => '/licenses/Apache-2.0');
  $t->get_ok('/licenses/Apache-2.0')->status_is(200)->element_exists('div div a[href=/licenses/edit_pattern/1]')
    ->text_is('div pre' => 'real-time web framework')->text_like('.alert-success' => qr/2 patterns have been updated/);
};

# Automatic reindexing
my $list = $t->app->minion->backend->list_jobs(0, 10, {states => ['inactive']});
is $list->{total},         2,                       'two inactives job';
is $list->{jobs}[0]{task}, 'pattern_stats',         'right task';
is $list->{jobs}[1]{task}, 'reindex_matched_later', 'right task';
is_deeply $list->{jobs}[1]{args}, [1], 'right arguments';
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

  $pkg = $t->app->packages->find(1);
  is $pkg->{state},  'acceptable',                                          'automatically accepted';
  is $pkg->{result}, 'Accepted because of package name (perl-Mojolicious)', 'because of name';
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

done_testing();
