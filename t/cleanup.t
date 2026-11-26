# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Mojo::Base -strict;

use FindBin;
use lib "$FindBin::Bin/lib";

use Test::More;
use Test::Mojo;
use Cavil::Test;
use Cavil::Util;
use File::Copy 'copy';
use Mojo::File qw(path tempdir);
use Mojo::IOLoop;
use Mojo::Pg;
use Mojo::URL;

plan skip_all => 'set TEST_ONLINE to enable this test' unless $ENV{TEST_ONLINE};

my $cavil_test = Cavil::Test->new(online => $ENV{TEST_ONLINE}, schema => 'cleanup_test');
my $config     = $cavil_test->default_config;
my $t          = Test::Mojo->new(Cavil => $config);
$cavil_test->no_fixtures($t->app);
my $dir = $cavil_test->checkout_dir;

my @one = ('perl-Mojolicious', 'c7cfdab0e71b0bebfdf8b2dc3badfecd');
my $one = $dir->child(@one)->make_path;
copy "$_", $one->child($_->basename) for path(__FILE__)->dirname->child('legal-bot', @one)->list->each;
my @two   = ('perl-Mojolicious', 'c8cfdab0e71b0bebfdf8b2dc3badfece');
my @three = ('perl-Mojolicious', 'c9cfdab0e71b0bebfdf8b2dc3badfecf');
my $two   = $dir->child(@two)->make_path;
my $three = $dir->child(@three)->make_path;
copy "$_", $two->child($_->basename)   for path(__FILE__)->dirname->child('legal-bot', @one)->list->each;
copy "$_", $three->child($_->basename) for path(__FILE__)->dirname->child('legal-bot', @one)->list->each;

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
$t->app->packages->imported($one_id);
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
$t->app->packages->imported($two_id);
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
$t->app->packages->imported($three_id);
my $product_id = $t->app->products->find_or_create('Cpan')->{id};

$t->app->patterns->create(pattern => 'The Artistic License 2.0', license => "Artistic-2.0", risk => 2);

$t->app->minion->enqueue(unpack => [$_]) for ($one_id, $two_id, $three_id);
$t->app->minion->perform_jobs;

is $t->app->packages->find($one_id)->{state}, 'new', 'not previously reviewed by a human';
$t->app->packages->update({id => $one_id, state => 'acceptable', reviewing_user => 1, result => 'Human review ok'});
$t->app->minion->enqueue('reindex_all');
$t->app->minion->perform_jobs;

$t->app->pg->db->query('update bot_packages set imported = ? where id=?', '2017-12-24', $one_id);
is $t->app->packages->find($one_id)->{state},  'acceptable',      'right state';
is $t->app->packages->find($one_id)->{result}, 'Human review ok', 'right result';
ok !$t->app->packages->find($one_id)->{obsolete},                                               'not obsolete';
ok -e $dir->child(@one),                                                                        'checkout exists';
ok $t->app->pg->db->select('bot_reports', [\'count(*)'], {package => $one_id})->array->[0],     'has reports';
ok $t->app->pg->db->select('emails', [\'count(*)'], {package => $one_id})->array->[0],          'has emails';
ok $t->app->pg->db->select('urls', [\'count(*)'], {package => $one_id})->array->[0],            'has URLs';
ok $t->app->pg->db->select('matched_files', [\'count(*)'], {package => $one_id})->array->[0],   'has matched files';
ok $t->app->pg->db->select('pattern_matches', [\'count(*)'], {package => $one_id})->array->[0], 'has pattern matches';

$t->app->pg->db->query('update bot_packages set imported = ? where id=?', '2017-12-24', $two_id);
$t->app->pg->db->insert('bot_package_products', {package => $two_id, product => $product_id});
is $t->app->packages->find($two_id)->{state}, 'acceptable', 'right state';
is $t->app->packages->find($two_id)->{result}, 'Accepted because previously reviewed under the same license (1)',
  'right result';
ok !$t->app->packages->find($two_id)->{obsolete},                                               'not obsolete';
ok -e $dir->child(@two),                                                                        'checkout exists';
ok $t->app->pg->db->select('bot_reports', [\'count(*)'], {package => $two_id})->array->[0],     'has reports';
ok $t->app->pg->db->select('emails', [\'count(*)'], {package => $two_id})->array->[0],          'has emails';
ok $t->app->pg->db->select('urls', [\'count(*)'], {package => $two_id})->array->[0],            'has URLs';
ok $t->app->pg->db->select('matched_files', [\'count(*)'], {package => $two_id})->array->[0],   'has matched files';
ok $t->app->pg->db->select('pattern_matches', [\'count(*)'], {package => $two_id})->array->[0], 'has pattern matches';

is $t->app->packages->find($three_id)->{state}, 'acceptable', 'right state';
is $t->app->packages->find($three_id)->{result}, 'Accepted because previously reviewed under the same license (1)',
  'right result';
ok !$t->app->packages->find($three_id)->{obsolete},                                      'not obsolete';
ok -e $dir->child(@three),                                                               'checkout exists';
ok $t->app->pg->db->select('emails', [\'count(*)'], {package => $three_id})->array->[0], 'has emails';
ok $t->app->pg->db->select('urls', [\'count(*)'], {package => $three_id})->array->[0],   'has URLs';

$t->app->packages->update({id => $two_id, state => 'acceptable_by_lawyer', reviewing_user => 1});
$t->app->minion->enqueue(analyzed => [$one_id]);
$t->app->minion->perform_jobs;
is $t->app->packages->find($one_id)->{state}, 'acceptable_by_lawyer', 'right state';
is $t->app->packages->find($one_id)->{result}, 'Accepted because reviewed by lawyer under the same license (2)',
  'right result';
$t->app->minion->enqueue(analyzed => [$three_id]);
$t->app->minion->perform_jobs;
is $t->app->packages->find($three_id)->{state}, 'acceptable_by_lawyer', 'right state';
is $t->app->packages->find($three_id)->{result}, 'Accepted because reviewed by lawyer under the same license (2)',
  'right result';

my %keep = (days_to_keep_orphaned_packages => 3650, days_to_keep_orphaned_duplicate_packages => 3650);
$t->app->settings->update('test_bot', \%keep);
$t->app->minion->enqueue('obsolete');
$t->app->minion->perform_jobs;
ok !$t->app->packages->find($one_id)->{obsolete}, 'not obsolete within the retention settings';
$t->app->settings->update('test_bot',
  {days_to_keep_orphaned_packages => 7, days_to_keep_orphaned_duplicate_packages => 1});

my $obsolete_id = $t->app->minion->enqueue('obsolete');
$t->app->minion->perform_jobs;

my $obsolete = $t->app->minion->job($obsolete_id);
is $obsolete->info->{state},                  'finished',             'right state';
is $t->app->packages->find($one_id)->{state}, 'acceptable_by_lawyer', 'right state';
is $t->app->packages->find($one_id)->{result}, 'Accepted because reviewed by lawyer under the same license (2)',
  'right result';
ok $t->app->packages->find($one_id)->{obsolete},                                        'obsolete';
ok $t->app->packages->find($one_id)->{cleaned},                                         'cleanup done';
ok !-e $dir->child(@one),                                                               'checkout does not exist';
ok !$t->app->pg->db->select('emails', [\'count(*)'], {package => $one_id})->array->[0], 'no emails';
ok !$t->app->pg->db->select('urls', [\'count(*)'], {package => $one_id})->array->[0],   'no URLs';
ok !$t->app->pg->db->select('matched_files', [\'count(*)'], {package => $one_id})->array->[0],   'no matched files';
ok !$t->app->pg->db->select('pattern_matches', [\'count(*)'], {package => $one_id})->array->[0], 'no pattern matches';
ok !$t->app->pg->db->select('file_snippets', [\'count(*)'], {package => $one_id})->array->[0],   'no file snippets';

is $t->app->packages->find($two_id)->{state}, 'acceptable_by_lawyer', 'right state';
is $t->app->packages->find($two_id)->{result}, 'Accepted because previously reviewed under the same license (1)',
  'right result';
ok !$t->app->packages->find($two_id)->{obsolete}, 'not obsolete';
ok !$t->app->packages->find($two_id)->{cleaned},  'no cleanup done';

is $t->app->packages->find($three_id)->{state}, 'acceptable_by_lawyer', 'right state';
is $t->app->packages->find($three_id)->{result}, 'Accepted because reviewed by lawyer under the same license (2)',
  'right result';
ok !$t->app->packages->find($three_id)->{obsolete},                                               'not obsolete';
ok !$t->app->packages->find($three_id)->{cleaned},                                                'no clanup done';
ok -e $dir->child(@three),                                                                        'checkout exists';
ok $t->app->pg->db->select('bot_reports', [\'count(*)'], {package => $three_id})->array->[0],     'has reports';
ok $t->app->pg->db->select('emails', [\'count(*)'], {package => $three_id})->array->[0],          'has emails';
ok $t->app->pg->db->select('urls', [\'count(*)'], {package => $three_id})->array->[0],            'has URLs';
ok $t->app->pg->db->select('matched_files', [\'count(*)'], {package => $three_id})->array->[0],   'has matched files';
ok $t->app->pg->db->select('pattern_matches', [\'count(*)'], {package => $three_id})->array->[0], 'has pattern matches';

$t->app->minion->enqueue('obsolete');
$t->app->minion->perform_jobs;
ok $t->app->packages->find($one_id)->{obsolete},    'still obsolete';
ok !$t->app->packages->find($two_id)->{obsolete},   'old but part of product';
ok !$t->app->packages->find($three_id)->{obsolete}, 'still not obsolete';

subtest 'Open reviews nobody is waiting for anymore' => sub {
  my $pkgs = $t->app->packages;
  $t->app->settings->update('test_bot', {auto_accept => 0});

  my @ids;
  for my $n (4 .. 7) {
    my $checkout = "d4cfdab0e71b0bebfdf8b2dc3badfe0$n";
    my $target   = $dir->child('perl-Mojolicious', $checkout)->make_path;
    copy "$_", $target->child($_->basename) for path(__FILE__)->dirname->child('legal-bot', @one)->list->each;
    my $id = $pkgs->add(
      name            => 'perl-Mojolicious',
      checkout_dir    => $checkout,
      api_url         => $n == 7 ? '' : 'https://api.opensuse.org',
      requesting_user => $usr_id,
      project         => 'devel:languages:perl',
      package         => 'perl-Mojolicious',
      srcmd5          => "bd91c36647a5d3dd883d490da214040$n",
      priority        => 5
    );
    $pkgs->imported($id);
    $t->app->minion->enqueue(unpack => [$id]);
    push @ids, $id;
  }
  $t->app->minion->perform_jobs;
  my ($abandoned, $requested, $in_product, $uploaded) = @ids;
  is $pkgs->find($_)->{state}, 'new', 'open review' for @ids;

  $t->app->requests->add('obs#4', $requested);
  $t->app->products->update($product_id, [$two_id, $in_product]);
  $db->query('UPDATE bot_packages SET imported = ? WHERE id = ANY(?)', '2017-12-24', \@ids);
  $t->app->minion->enqueue('obsolete');
  $t->app->minion->perform_jobs;
  ok $pkgs->find($abandoned)->{obsolete}, 'abandoned open review retired';
  ok $pkgs->find($abandoned)->{cleaned},  'cleanup done';
  is $pkgs->find($abandoned)->{state}, 'new', 'state is left alone';
  ok !$pkgs->find($requested)->{obsolete},         'open review with a request is kept';
  ok !$pkgs->find($in_product)->{obsolete},        'open review in a product is kept';
  ok !$pkgs->find($uploaded)->{obsolete},          'uploaded open review is kept';
  ok $pkgs->has_manual_review('perl-Mojolicious'), 'family still counts as reviewed by a human';
  is $pkgs->find($three_id)->{state}, 'acceptable_by_lawyer', 'decided package untouched';
  ok !$pkgs->find($three_id)->{obsolete}, 'decided package not retired';

  $t->app->products->update($product_id, [$two_id]);
  $t->app->minion->enqueue('obsolete');
  $t->app->minion->perform_jobs;
  ok $pkgs->find($in_product)->{obsolete}, 'retired once the product dropped it';
  ok !$pkgs->find($two_id)->{obsolete},    'decided package in the product is kept';
  ok !$pkgs->find($requested)->{obsolete}, 'open review with a request is still kept';

  $t->app->requests->add('obs#5', $abandoned);
  ok !$pkgs->find($abandoned)->{obsolete}, 'reopened by a new request';
  $t->app->requests->remove('obs#5');
  $t->app->minion->enqueue('obsolete');
  $t->app->minion->perform_jobs;
  ok !$pkgs->find($abandoned)->{obsolete}, 'not retired again while its sources are still missing';
};

done_testing();
