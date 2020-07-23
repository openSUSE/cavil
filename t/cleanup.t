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
$pg->db->query('drop schema if exists bot_cleanup_test cascade');
$pg->db->query('create schema bot_cleanup_test');

# Create checkout directories
my $dir = tempdir;
my @one = ('perl-Mojolicious', 'c7cfdab0e71b0bebfdf8b2dc3badfecd');
my $one = $dir->child(@one)->make_path;
copy "$_", $one->child($_->basename) for path(__FILE__)->dirname->child('legal-bot', @one)->list->each;
my @two   = ('perl-Mojolicious', 'c8cfdab0e71b0bebfdf8b2dc3badfece');
my @three = ('perl-Mojolicious', 'c9cfdab0e71b0bebfdf8b2dc3badfecf');
my $two   = $dir->child(@two)->make_path;
my $three = $dir->child(@three)->make_path;
copy "$_", $two->child($_->basename)   for path(__FILE__)->dirname->child('legal-bot', @one)->list->each;
copy "$_", $three->child($_->basename) for path(__FILE__)->dirname->child('legal-bot', @one)->list->each;

# Configure application
my $online = Mojo::URL->new($ENV{TEST_ONLINE})->query([search_path => 'bot_cleanup_test'])->to_unsafe_string;
my $config = {
  secrets                => ['just_a_test'],
  checkout_dir           => $dir,
  tokens                 => [],
  pg                     => $online,
  acceptable_risk        => 3,
  index_bucket_average   => 100,
  cleanup_bucket_average => 1,
  min_files_short_report => 20,
  max_email_url_size     => 26,
  max_task_memory        => 5_000_000_000,
  max_worker_rss         => 100000,
  max_expanded_files     => 100
};
my $t = Test::Mojo->new(Cavil => $config);
$t->app->pg->migrations->migrate;

# Prepare database
my $db     = $t->app->pg->db;
my $usr_id = $db->insert('bot_users', {login => 'test_bot'}, {returning => 'id'})->hash->{id};
my $one_id = $t->app->packages->add(
  name            => 'perl-Mojolicious',
  checkout_dir    => 'c7cfdab0e71b0bebfdf8b2dc3badfecd',
  api_url         => 'https://api.opensuse.org',
  requesting_user => $usr_id,
  project         => 'devel:languages:perl',
  package         => 'perl-Mojolicious',
  srcmd5          => 'bd91c36647a5d3dd883d490da2140401',
  priority        => 5
);
my $two_id = $t->app->packages->add(
  name            => 'perl-Mojolicious',
  checkout_dir    => 'c8cfdab0e71b0bebfdf8b2dc3badfece',
  api_url         => 'https://api.opensuse.org',
  requesting_user => $usr_id,
  project         => 'devel:languages:perl',
  package         => 'perl-Mojolicious',
  srcmd5          => 'bd91c36647a5d3dd883d490da2140402',
  priority        => 5
);
my $three_id = $t->app->packages->add(
  name            => 'perl-Mojolicious',
  checkout_dir    => 'c9cfdab0e71b0bebfdf8b2dc3badfecf',
  api_url         => 'https://api.opensuse.org',
  requesting_user => $usr_id,
  project         => 'devel:languages:perl',
  package         => 'perl-Mojolicious',
  srcmd5          => 'bd91c36647a5d3dd883d490da2140403',
  priority        => 5
);
my $product_id = $t->app->products->find_or_create('Cpan')->{id};

$t->app->patterns->create(pattern => 'The Artistic License 2.0', license => "Artistic-2.0", risk => 2);

# Unpack and index with the job queue
$t->app->minion->enqueue(unpack => [$_]) for ($one_id, $two_id, $three_id);
$t->app->minion->perform_jobs;

# First package
# fake import date
$t->app->pg->db->query('update bot_packages set imported = ? where id=?', '2017-12-24', $one_id);
is $t->app->packages->find($one_id)->{state},  'acceptable',                       'right state';
is $t->app->packages->find($one_id)->{result}, 'Accepted because of low risk (2)', 'right result';
ok !$t->app->packages->find($one_id)->{obsolete}, 'not obsolete';
ok -e $dir->child(@one), 'checkout exists';
ok $t->app->pg->db->select('bot_reports',     [\'count(*)'], {package => $one_id})->array->[0], 'has reports';
ok $t->app->pg->db->select('emails',          [\'count(*)'], {package => $one_id})->array->[0], 'has emails';
ok $t->app->pg->db->select('urls',            [\'count(*)'], {package => $one_id})->array->[0], 'has URLs';
ok $t->app->pg->db->select('matched_files',   [\'count(*)'], {package => $one_id})->array->[0], 'has matched files';
ok $t->app->pg->db->select('pattern_matches', [\'count(*)'], {package => $one_id})->array->[0], 'has pattern matches';

# Second package (product)
# fake import date
$t->app->pg->db->query('update bot_packages set imported = ? where id=?', '2017-12-24', $two_id);
$t->app->pg->db->insert('bot_package_products', {package => $two_id, product => $product_id});
is $t->app->packages->find($two_id)->{state}, 'acceptable', 'right state';
is $t->app->packages->find($two_id)->{result}, 'Accepted because previously reviewed under the same license (1)',
  'right result';
ok !$t->app->packages->find($two_id)->{obsolete}, 'not obsolete';
ok -e $dir->child(@two), 'checkout exists';
ok $t->app->pg->db->select('bot_reports',     [\'count(*)'], {package => $two_id})->array->[0], 'has reports';
ok $t->app->pg->db->select('emails',          [\'count(*)'], {package => $two_id})->array->[0], 'has emails';
ok $t->app->pg->db->select('urls',            [\'count(*)'], {package => $two_id})->array->[0], 'has URLs';
ok $t->app->pg->db->select('matched_files',   [\'count(*)'], {package => $two_id})->array->[0], 'has matched files';
ok $t->app->pg->db->select('pattern_matches', [\'count(*)'], {package => $two_id})->array->[0], 'has pattern matches';

# Third package
is $t->app->packages->find($three_id)->{state}, 'acceptable', 'right state';
is $t->app->packages->find($three_id)->{result}, 'Accepted because previously reviewed under the same license (1)',
  'right result';
ok !$t->app->packages->find($three_id)->{obsolete}, 'not obsolete';
ok -e $dir->child(@three), 'checkout exists';
ok $t->app->pg->db->select('emails', [\'count(*)'], {package => $three_id})->array->[0], 'has emails';
ok $t->app->pg->db->select('urls',   [\'count(*)'], {package => $three_id})->array->[0], 'has URLs';

# Upgrade from acceptable to correct by reindexing
$t->app->packages->update({id => $two_id, state => 'correct'});
$t->app->minion->enqueue(analyzed => [$one_id]);
$t->app->minion->perform_jobs;
is $t->app->packages->find($one_id)->{state},  'correct',                                             'right state';
is $t->app->packages->find($one_id)->{result}, 'Correct because reviewed under the same license (2)', 'right result';
$t->app->minion->enqueue(analyzed => [$three_id]);
$t->app->minion->perform_jobs;
is $t->app->packages->find($three_id)->{state},  'correct',                                             'right state';
is $t->app->packages->find($three_id)->{result}, 'Correct because reviewed under the same license (2)', 'right result';

# Clean up old packages
my $obsolete_id = $t->app->minion->enqueue('obsolete');
$t->app->minion->perform_jobs;

# First package (still valid)
my $obsolete = $t->app->minion->job($obsolete_id);
is $obsolete->info->{state}, 'finished', 'right state';
is $t->app->packages->find($one_id)->{state},  'correct',                                             'right state';
is $t->app->packages->find($one_id)->{result}, 'Correct because reviewed under the same license (2)', 'right result';
ok $t->app->packages->find($one_id)->{obsolete}, 'obsolete';
ok !-e $dir->child(@one), 'checkout does not exist';
ok !$t->app->pg->db->select('emails',          [\'count(*)'], {package => $one_id})->array->[0], 'no emails';
ok !$t->app->pg->db->select('urls',            [\'count(*)'], {package => $one_id})->array->[0], 'no URLs';
ok !$t->app->pg->db->select('matched_files',   [\'count(*)'], {package => $one_id})->array->[0], 'no matched files';
ok !$t->app->pg->db->select('pattern_matches', [\'count(*)'], {package => $one_id})->array->[0], 'no pattern matches';
ok !$t->app->pg->db->select('file_snippets',   [\'count(*)'], {package => $one_id})->array->[0], 'no file snippets';

# Second package (obsolete)
is $t->app->packages->find($two_id)->{state}, 'correct', 'right state';
is $t->app->packages->find($two_id)->{result}, 'Accepted because previously reviewed under the same license (1)',
  'right result';
ok !$t->app->packages->find($two_id)->{obsolete}, 'obsolete';

# Third package (obsolete)
is $t->app->packages->find($three_id)->{state},  'correct',                                             'right state';
is $t->app->packages->find($three_id)->{result}, 'Correct because reviewed under the same license (2)', 'right result';
ok !$t->app->packages->find($three_id)->{obsolete}, 'not obsolete';
ok -e $dir->child(@three), 'checkout exists';
ok $t->app->pg->db->select('bot_reports',     [\'count(*)'], {package => $three_id})->array->[0], 'has reports';
ok $t->app->pg->db->select('emails',          [\'count(*)'], {package => $three_id})->array->[0], 'has emails';
ok $t->app->pg->db->select('urls',            [\'count(*)'], {package => $three_id})->array->[0], 'has URLs';
ok $t->app->pg->db->select('matched_files',   [\'count(*)'], {package => $three_id})->array->[0], 'has matched files';
ok $t->app->pg->db->select('pattern_matches', [\'count(*)'], {package => $three_id})->array->[0], 'has pattern matches';

# Clean up old packages again
$t->app->minion->enqueue('obsolete');
$t->app->minion->perform_jobs;
ok $t->app->packages->find($one_id)->{obsolete}, 'still obsolete';
ok !$t->app->packages->find($two_id)->{obsolete},   'old but part of product';
ok !$t->app->packages->find($three_id)->{obsolete}, 'still not obsolete';

# Clean up once we are done
$pg->db->query('drop schema bot_cleanup_test cascade');

done_testing();
