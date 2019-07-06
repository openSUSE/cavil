use Mojo::Base -strict;

BEGIN { $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll' }

use Test::More;

plan skip_all => 'set TEST_ONLINE to enable this test' unless $ENV{TEST_ONLINE};

use Cavil::Util;
use File::Copy 'copy';
use Mojo::File qw(path tempdir);
use Mojo::IOLoop;
use Mojo::Pg;
use Mojo::URL;
use Test::Mojo;

# Isolate tests
my $pg = Mojo::Pg->new($ENV{TEST_ONLINE});
$pg->db->query('drop schema if exists bot_index_test cascade');
$pg->db->query('create schema bot_index_test');

# Create checkout directory
my $dir  = tempdir;
my @src  = ('perl-Mojolicious', 'c7cfdab0e71b0bebfdf8b2dc3badfecd');
my $mojo = $dir->child(@src)->make_path;
copy "$_", $mojo->child($_->basename)
  for path(__FILE__)->dirname->child('legal-bot', @src)->list->each;

# Configure application
my $online
  = Mojo::URL->new($ENV{TEST_ONLINE})->query([search_path => 'bot_index_test'])
  ->to_unsafe_string;
my $config = {
  secrets                => ['just_a_test'],
  checkout_dir           => $dir,
  tokens                 => [],
  pg                     => $online,
  acceptable_risk        => 3,
  index_bucket_average   => 100,
  cleanup_bucket_average => 50,
  min_files_short_report => 20,
  max_email_url_size     => 26,
  max_task_memory        => 5_000_000_000,
  max_worker_rss         => 100000,
  max_expanded_files     => 100
};
my $t = Test::Mojo->new(Cavil => $config);
$t->app->pg->migrations->migrate;

# Prepare database
my $db = $t->app->pg->db;
my $usr_id
  = $db->insert('bot_users', {login => 'test_bot'}, {returning => 'id'})
  ->hash->{id};
my $pkg_id = $t->app->packages->add(
  name            => 'perl-Mojolicious',
  checkout_dir    => 'c7cfdab0e71b0bebfdf8b2dc3badfecd',
  api_url         => 'https://api.opensuse.org',
  requesting_user => $usr_id,
  project         => 'devel:languages:perl',
  package         => 'perl-Mojolicious',
  srcmd5          => 'bd91c36647a5d3dd883d490da2140401',
  priority        => 5
);

$t->app->patterns->expire_cache;
my $lic_id1 = $t->app->licenses->create(name => 'Apache-2.0');
$t->app->patterns->create($lic_id1,
  pattern => 'You may obtain a copy of the License at', license_string => 'Apache-2.0');
$t->app->patterns->create(
  $lic_id1,
  packname => 'perl-Mojolicious',
  pattern  => 'Licensed under the Apache License, Version 2.0',
  license_string => 'Apache-2.0'
);
my $lic_id2 = $t->app->licenses->create(name => 'Artistic-2.0');
$t->app->patterns->create($lic_id2, pattern => 'License: Artistic-2.0', license_string => 'Artistic-2.0');
my $lic_id3
  = $t->app->licenses->create(name => 'Definitely not a license', risk => 0);
$t->app->patterns->create($lic_id3,
  pattern => 'powerful web development toolkit', license_string => 'SUSE-NotALicense');
# keyword without license
$t->app->patterns->create($lic_id3, pattern => 'the terms');

# Unpack and index with the job queue
my $unpack_id = $t->app->minion->enqueue(unpack => [$pkg_id]);
ok !$db->select('emails', ['id'], {email => 'sri@cpan.org'})->rows,
  'email address does not exist';
ok !$db->select('urls', ['id'], {url => 'http://mojolicious.org'})->rows,
  'URL does not exist';
ok !$db->select('bot_packages', ['unpacked'], {id => $pkg_id})
  ->hash->{unpacked}, 'not unpacked';
$t->app->minion->perform_jobs;
my $unpack_job = $t->app->minion->job($unpack_id);
is $unpack_job->task, 'unpack', 'right task';
is $unpack_job->info->{state},  'finished', 'job is finished';
is $unpack_job->info->{result}, undef,      'job was successful';
my $index_id  = $unpack_job->info->{children}[0];
my $index_job = $t->app->minion->job($index_id);
is $index_job->task, 'index', 'right task';
is $index_job->info->{state},  'finished', 'job is finished';
is $index_job->info->{result}, undef,      'job was successful';
my @batch_ids  = @{$index_job->info->{children}};
my @batch_jobs = map { $t->app->minion->job($_) } @batch_ids;
is $batch_jobs[0]->task, 'index_batch', 'right task';
is $batch_jobs[0]->info->{state},  'finished', 'job is finished';
is $batch_jobs[0]->info->{result}, undef,      'job was successful';
is $batch_jobs[1]->task, 'index_batch', 'right task';
is $batch_jobs[1]->info->{state},  'finished', 'job is finished';
is $batch_jobs[1]->info->{result}, undef,      'job was successful';
is $batch_jobs[2]->task, 'index_batch', 'right task';
is $batch_jobs[2]->info->{state},  'finished', 'job is finished';
is $batch_jobs[2]->info->{result}, undef,      'job was successful';
is $batch_jobs[3], undef, 'no more jobs';
my $indexed_id  = $batch_jobs[0]->info->{children}[0];
my $indexed_job = $t->app->minion->job($indexed_id);
is $indexed_job->task, 'indexed', 'right task';
is $indexed_job->info->{state},  'finished', 'job is finished';
is $indexed_job->info->{result}, undef,      'job was successful';
my $analyze_id  = $indexed_job->info->{children}[0];
my $analyze_job = $t->app->minion->job($analyze_id);
is $analyze_job->task, 'analyze', 'right task';
is $analyze_job->info->{state},  'finished', 'job is finished';
is $analyze_job->info->{result}, undef,      'job was successful';
my $analyzed_id  = $analyze_job->info->{children}[0];
my $analyzed_job = $t->app->minion->job($analyzed_id);
is $analyzed_job->task, 'analyzed', 'right task';
is $analyzed_job->info->{state},  'finished', 'job is finished';
is $analyzed_job->info->{result}, undef,      'job was successful';
is $t->app->packages->find($pkg_id)->{state}, 'new', 'still new';

# Check shortname
like $t->app->packages->find($pkg_id)->{checksum}, qr/^Artistic-2.0-5:\w+/,
  'right shortname';

# Check email addresses and URLs
ok $db->select('emails', ['id'], {email => 'sri@cpan.org'})->rows,
  'email address has been added';
is $db->select('urls', ['hits'], {url => 'http://mojolicious.org'})
  ->hash->{hits}, 154, 'URL has been added';
my $long = 'e2%98%83@xn--n3h.xn--n3h.de';
is $db->select('emails', ['id'], {email => $long})->hash, undef,
  'email address is too long';
$long
  = 'https://cdn.rawgit.com/google/code-prettify/master/loader/prettify.css';
is $db->select('urls', ['hits'], {url => $long})->hash, undef,
  'URL is too long';

# Check files
my $file_id = $db->select('matched_files', ['id'],
  {filename => 'Mojolicious-7.25/lib/Mojolicious.pm'})->hash->{id};
ok $file_id, 'file has been added';
ok $db->select('bot_packages', ['unpacked'], {id => $pkg_id})->hash->{unpacked},
  'unpacked';

# Verify report checksum
my $specfile = $t->app->reports->specfile_report($pkg_id);
my $dig      = $t->app->reports->dig_report($pkg_id);
is $t->app->checksum($specfile, $dig), '425a58966dd35fb9dbe17591cd4cf2f5',
  'right checksum';

# Check matches
my $res = $db->select(
  ['pattern_matches', ['matched_files', id => 'file']],
  ['sline', 'pattern'],
  {
    'matched_files.filename' => 'Mojolicious-7.25/lib/Mojolicious/resources/'
      . 'public/mojo/prettify/run_prettify.processed.js'
  },
  {order_by => 'sline'}
)->arrays;
is_deeply $res, [[5, 2], [7, 1], [19, 2], [21, 1]],
  'JavaScript correctly tagged Apache';
$res = $db->select(
  ['pattern_matches', ['matched_files', id => 'file']],
  ['sline', 'pattern'],
  {'matched_files.filename' => 'Mojolicious-7.25/lib/Mojolicious.pm'},
  {order_by                 => 'sline'}
)->arrays;
is_deeply $res, [[751, 2]], 'Perl correctly tagged Artistic';

# Raise acceptable risk
$config->{acceptable_risk} = 5;
$t = Test::Mojo->new(Cavil => $config);

# License management requires a login
$t->get_ok('/licenses')->status_is(403)->content_like(qr/Permission/);
$t->get_ok('/login')->status_is(302)->header_is(Location => '/');
$t->get_ok('/licenses')->status_is(200)->content_like(qr/Licenses/);

# Pattern change
$t->get_ok('/licenses')->status_is(200)
  ->text_is('td a[href=/licenses/1]' => 'Apache-2.0')
  ->text_is('td a[href=/licenses/2]' => 'Artistic-2.0')
  ->text_is('td a[href=/licenses/3]' => 'Definitely not a license');
$t->get_ok('/licenses/1')->status_is(200)
  ->element_exists('li div a[href=/licenses/edit_pattern/1]')
  ->text_is('li pre' => 'You may obtain a copy of the License at');
$t->get_ok('/licenses/edit_pattern/1')->status_is(200)
  ->text_is('select[name=license] option[value=1]' => 'Apache-2.0')
  ->text_is(
  'textarea[name=pattern]' => 'You may obtain a copy of the License at')
  ->element_exists_not('input:checked');
$t->post_ok('/licenses/update_pattern/1' => form =>
    {license => 1, pattern => 'real-time web framework'})->status_is(302)
  ->header_is(Location => '/licenses/1');
$t->get_ok('/licenses/1')->status_is(200)
  ->element_exists('li div a[href=/licenses/edit_pattern/1]')
  ->text_is('li pre' => 'real-time web framework')
  ->text_like('.alert-success' =>
    qr/Pattern has been updated, reindexing all affected packages/);

# Automatic reindexing
my $list = $t->app->minion->backend->list_jobs(0, 10, {states => ['inactive']});
is $list->{total}, 1, 'one inactive job';
is $list->{jobs}[0]{task}, 'reindex_matched_later', 'right task';
is_deeply $list->{jobs}[0]{args}, [1], 'right arguments';
my $reindex_id = $list->{jobs}[0]{id};
$t->app->minion->perform_jobs;
is $t->app->minion->job($reindex_id)->info->{state}, 'finished',
  'job is finished';
$res = $db->select(
  ['pattern_matches', ['matched_files', id => 'file']],
  ['sline', 'pattern'],
  {'matched_files.filename' => 'Mojolicious-7.25/lib/Mojolicious.pm'},
  {order_by                 => 'sline'}
)->arrays;
is_deeply $res, [[210, 1], [236, 1], [751, 2]],
  'Perl correctly tagged with new pattern';

# Manual reindexing
$t->app->pg->db->query(
  "update license_patterns set pattern = 'powerful' where id = 1");
$t->app->patterns->expire_cache;
$list = $t->app->minion->backend->list_jobs(0, 10, {tasks => ['index_later']});
is $list->{total}, 1, 'one index_later jobs';
$reindex_id = $t->app->minion->enqueue('reindex_all');
$t->app->minion->perform_jobs;
$list = $t->app->minion->backend->list_jobs(0, 10, {tasks => ['index_later']});
is $list->{total}, 2, 'two index_later jobs';
is $list->{jobs}[0]{state}, 'finished', 'right state';
is $list->{jobs}[1]{state}, 'finished', 'right state';
$res = $db->select(
  ['pattern_matches', ['matched_files', id => 'file']],
  ['sline', 'pattern'],
  {'matched_files.filename' => 'Mojolicious-7.25/lib/Mojolicious.pm'},
  {order_by                 => 'sline'}
)->arrays;
is_deeply $res, [[236, 1], [258, 1], [278, 1], [333, 1], [751, 2]],
  'Perl correctly tagged with new pattern';

# Accepted because of low risk
my $pkg = $t->app->packages->find($pkg_id);
is $pkg->{state}, 'acceptable', 'automatically accepted';
is $pkg->{result}, 'Accepted because of low risk (5)', 'because of low risk';

# Clean up once we are done
$pg->db->query('drop schema bot_index_test cascade');

done_testing();
