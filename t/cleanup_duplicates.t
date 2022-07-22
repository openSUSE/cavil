# Copyright (C) 2018-2022 SUSE LLC
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
use Cavil::Util;
use File::Copy 'copy';
use Mojo::File qw(path tempdir);
use Mojo::IOLoop;
use Mojo::Pg;
use Mojo::URL;

plan skip_all => 'set TEST_ONLINE to enable this test' unless $ENV{TEST_ONLINE};

my $cavil_test = Cavil::Test->new(online => $ENV{TEST_ONLINE}, schema => 'cleanup_duplicates_test');
my $config     = $cavil_test->default_config;
my $t          = Test::Mojo->new(Cavil => $config);
$cavil_test->no_fixtures($t->app);
my $dir = $cavil_test->checkout_dir;

# Create checkout directories
my @one   = ('perl-Mojolicious', 'c7cfdab0e71b0bebfdf8b2dc3badfecd');
my @two   = ('perl-Mojolicious', 'c8cfdab0e71b0bebfdf8b2dc3badfece');
my @three = ('perl-Mojolicious', 'c9cfdab0e71b0bebfdf8b2dc3badfecf');
my @four  = ('perl-Mojolicious', 'c9cfdab0e71b0bebfdf8b2dc3badfedf');
my @five  = ('perl-Mojolicious', 'd9cfdab0e71b0bebfdf8b2dc3badfedf');
my $one   = $dir->child(@one)->make_path;
my $two   = $dir->child(@two)->make_path;
my $three = $dir->child(@three)->make_path;
my $four  = $dir->child(@four)->make_path;
my $five  = $dir->child(@five)->make_path;
copy "$_", $one->child($_->basename)   for path(__FILE__)->dirname->child('legal-bot', @one)->list->each;
copy "$_", $two->child($_->basename)   for path(__FILE__)->dirname->child('legal-bot', @one)->list->each;
copy "$_", $three->child($_->basename) for path(__FILE__)->dirname->child('legal-bot', @one)->list->each;
copy "$_", $four->child($_->basename)  for path(__FILE__)->dirname->child('legal-bot', @one)->list->each;
copy "$_", $five->child($_->basename)  for path(__FILE__)->dirname->child('legal-bot', @one)->list->each;

# Prepare database (fourth and fifth packages need to be added first to get the oldest timestamp)
my $db      = $t->app->pg->db;
my $usr_id  = $db->insert('bot_users', {login => 'test_bot'}, {returning => 'id'})->hash->{id};
my $four_id = $t->app->packages->add(
  name            => 'perl-Mojolicious',
  checkout_dir    => 'c9cfdab0e71b0bebfdf8b2dc3badfedf',
  api_url         => 'https://api.opensuse.org',
  requesting_user => $usr_id,
  project         => 'devel:languages:perl',
  package         => 'perl-Mojolicious',
  srcmd5          => 'bd91c36647a5d3dd883d490da214040f',
  priority        => 5
);
$t->app->packages->update({id => $four_id, external_link => 'home:kraih:SLL'});
$t->app->packages->imported($four_id);
my $five_id = $t->app->packages->add(
  name            => 'perl-Mojolicious',
  checkout_dir    => 'd9cfdab0e71b0bebfdf8b2dc3badfedf',
  api_url         => 'https://api.opensuse.org',
  requesting_user => $usr_id,
  project         => 'devel:languages:perl',
  package         => 'perl-Mojolicious',
  srcmd5          => 'bd91c36647a5d3dd883d490da214041f',
  priority        => 5
);
$t->app->packages->imported($five_id);
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
$t->app->packages->update({id => $one_id, external_link => 'openSUSE:Factory'});
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
$t->app->packages->update({id => $two_id, external_link => 'openSUSE:Factory'});
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
$t->app->packages->update({id => $three_id, external_link => 'openSUSE:Factory'});
$t->app->packages->imported($three_id);

$t->app->patterns->create(pattern => 'The Artistic License 2.0', license => "Non-Free", risk => 6);

subtest 'Index duplicate packages' => sub {
  $t->app->minion->enqueue(unpack => [$_]) for ($one_id, $two_id, $three_id, $four_id, $five_id);
  $t->app->minion->perform_jobs;

  # First package
  is $t->app->packages->find($one_id)->{state}, 'new', 'right state';
  ok !$t->app->packages->find($one_id)->{obsolete},                                               'not obsolete';
  ok -e $dir->child(@one),                                                                        'checkout exists';
  ok $t->app->pg->db->select('bot_reports', [\'count(*)'], {package => $one_id})->array->[0],     'has reports';
  ok $t->app->pg->db->select('emails', [\'count(*)'], {package => $one_id})->array->[0],          'has emails';
  ok $t->app->pg->db->select('urls', [\'count(*)'], {package => $one_id})->array->[0],            'has URLs';
  ok $t->app->pg->db->select('matched_files', [\'count(*)'], {package => $one_id})->array->[0],   'has matched files';
  ok $t->app->pg->db->select('pattern_matches', [\'count(*)'], {package => $one_id})->array->[0], 'has pattern matches';

  # Second package
  is $t->app->packages->find($two_id)->{state}, 'new', 'right state';
  ok !$t->app->packages->find($two_id)->{obsolete},                                               'not obsolete';
  ok -e $dir->child(@two),                                                                        'checkout exists';
  ok $t->app->pg->db->select('bot_reports', [\'count(*)'], {package => $two_id})->array->[0],     'has reports';
  ok $t->app->pg->db->select('emails', [\'count(*)'], {package => $two_id})->array->[0],          'has emails';
  ok $t->app->pg->db->select('urls', [\'count(*)'], {package => $two_id})->array->[0],            'has URLs';
  ok $t->app->pg->db->select('matched_files', [\'count(*)'], {package => $two_id})->array->[0],   'has matched files';
  ok $t->app->pg->db->select('pattern_matches', [\'count(*)'], {package => $two_id})->array->[0], 'has pattern matches';

  # Third package
  is $t->app->packages->find($three_id)->{state}, 'new', 'right state';
  ok !$t->app->packages->find($three_id)->{obsolete},                                             'not obsolete';
  ok -e $dir->child(@three),                                                                      'checkout exists';
  ok $t->app->pg->db->select('emails', [\'count(*)'], {package => $three_id})->array->[0],        'has emails';
  ok $t->app->pg->db->select('urls', [\'count(*)'], {package => $three_id})->array->[0],          'has URLs';
  ok $t->app->pg->db->select('matched_files', [\'count(*)'], {package => $three_id})->array->[0], 'has matched files';
  ok $t->app->pg->db->select('pattern_matches', [\'count(*)'], {package => $three_id})->array->[0],
    'has pattern matches';

  # Fourth package (different external_link)
  is $t->app->packages->find($four_id)->{state}, 'new', 'right state';
  ok !$t->app->packages->find($four_id)->{obsolete},                                             'not obsolete';
  ok -e $dir->child(@four),                                                                      'checkout exists';
  ok $t->app->pg->db->select('emails', [\'count(*)'], {package => $four_id})->array->[0],        'has emails';
  ok $t->app->pg->db->select('urls', [\'count(*)'], {package => $four_id})->array->[0],          'has URLs';
  ok $t->app->pg->db->select('matched_files', [\'count(*)'], {package => $four_id})->array->[0], 'has matched files';
  ok $t->app->pg->db->select('pattern_matches', [\'count(*)'], {package => $four_id})->array->[0],
    'has pattern matches';

  # Fifth package (no external_link)
  is $t->app->packages->find($five_id)->{state}, 'new', 'right state';
  ok !$t->app->packages->find($five_id)->{obsolete},                                             'not obsolete';
  ok -e $dir->child(@five),                                                                      'checkout exists';
  ok $t->app->pg->db->select('emails', [\'count(*)'], {package => $five_id})->array->[0],        'has emails';
  ok $t->app->pg->db->select('urls', [\'count(*)'], {package => $five_id})->array->[0],          'has URLs';
  ok $t->app->pg->db->select('matched_files', [\'count(*)'], {package => $five_id})->array->[0], 'has matched files';
  ok $t->app->pg->db->select('pattern_matches', [\'count(*)'], {package => $five_id})->array->[0],
    'has pattern matches';
};

subtest 'Clean up duplicates' => sub {
  $t->app->minion->enqueue('cleanup');
  $t->app->minion->perform_jobs;

  # First package (cleaned up)
  is $t->app->packages->find($one_id)->{state}, 'obsolete', 'right state';
  ok $t->app->packages->find($one_id)->{obsolete},                                        'obsolete';
  ok !-e $dir->child(@one),                                                               'checkout does not exist';
  ok !$t->app->pg->db->select('emails', [\'count(*)'], {package => $one_id})->array->[0], 'no emails';
  ok !$t->app->pg->db->select('urls', [\'count(*)'], {package => $one_id})->array->[0],   'no URLs';
  ok !$t->app->pg->db->select('matched_files', [\'count(*)'], {package => $one_id})->array->[0],   'no matched files';
  ok !$t->app->pg->db->select('pattern_matches', [\'count(*)'], {package => $one_id})->array->[0], 'no pattern matches';
  ok !$t->app->pg->db->select('file_snippets', [\'count(*)'], {package => $one_id})->array->[0],   'no file snippets';

  # Second package (cleaned up)
  is $t->app->packages->find($one_id)->{state}, 'obsolete', 'right state';
  ok $t->app->packages->find($two_id)->{obsolete},                                        'obsolete';
  ok !-e $dir->child(@two),                                                               'checkout does not exist';
  ok !$t->app->pg->db->select('emails', [\'count(*)'], {package => $two_id})->array->[0], 'no emails';
  ok !$t->app->pg->db->select('urls', [\'count(*)'], {package => $two_id})->array->[0],   'no URLs';
  ok !$t->app->pg->db->select('matched_files', [\'count(*)'], {package => $two_id})->array->[0],   'no matched files';
  ok !$t->app->pg->db->select('pattern_matches', [\'count(*)'], {package => $two_id})->array->[0], 'no pattern matches';
  ok !$t->app->pg->db->select('file_snippets', [\'count(*)'], {package => $two_id})->array->[0],   'no file snippets';

  # Third package (still valid, because the latest)
  is $t->app->packages->find($three_id)->{state}, 'new', 'right state';
  ok !$t->app->packages->find($three_id)->{obsolete},                                             'not obsolete';
  ok -e $dir->child(@three),                                                                      'checkout exists';
  ok $t->app->pg->db->select('emails', [\'count(*)'], {package => $three_id})->array->[0],        'has emails';
  ok $t->app->pg->db->select('urls', [\'count(*)'], {package => $three_id})->array->[0],          'has URLs';
  ok $t->app->pg->db->select('matched_files', [\'count(*)'], {package => $three_id})->array->[0], 'has matched files';
  ok $t->app->pg->db->select('pattern_matches', [\'count(*)'], {package => $three_id})->array->[0],
    'has pattern matches';

  # Fourth package (still valid, different external link)
  is $t->app->packages->find($four_id)->{state}, 'new', 'right state';
  ok !$t->app->packages->find($four_id)->{obsolete},                                             'not obsolete';
  ok -e $dir->child(@four),                                                                      'checkout exists';
  ok $t->app->pg->db->select('emails', [\'count(*)'], {package => $four_id})->array->[0],        'has emails';
  ok $t->app->pg->db->select('urls', [\'count(*)'], {package => $four_id})->array->[0],          'has URLs';
  ok $t->app->pg->db->select('matched_files', [\'count(*)'], {package => $four_id})->array->[0], 'has matched files';
  ok $t->app->pg->db->select('pattern_matches', [\'count(*)'], {package => $four_id})->array->[0],
    'has pattern matches';

  # Fifth package (still valid, no external_link)
  is $t->app->packages->find($five_id)->{state}, 'new', 'right state';
  ok !$t->app->packages->find($five_id)->{obsolete},                                             'not obsolete';
  ok -e $dir->child(@five),                                                                      'checkout exists';
  ok $t->app->pg->db->select('emails', [\'count(*)'], {package => $five_id})->array->[0],        'has emails';
  ok $t->app->pg->db->select('urls', [\'count(*)'], {package => $five_id})->array->[0],          'has URLs';
  ok $t->app->pg->db->select('matched_files', [\'count(*)'], {package => $five_id})->array->[0], 'has matched files';
  ok $t->app->pg->db->select('pattern_matches', [\'count(*)'], {package => $five_id})->array->[0],
    'has pattern matches';
};

done_testing();
