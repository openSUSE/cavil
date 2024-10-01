# Copyright (C) 2023 SUSE LLC
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
use Cavil::Command::patterns;
use Mojo::File qw(tempdir);

plan skip_all => 'set TEST_ONLINE to enable this test' unless $ENV{TEST_ONLINE};

my $cavil_test = Cavil::Test->new(online => $ENV{TEST_ONLINE}, schema => 'command_patterns_test');
my $config     = $cavil_test->default_config;
my $t          = Test::Mojo->new(Cavil => $config);
my $app        = $t->app;
$cavil_test->no_fixtures($app);
my $tmp = tempdir;

subtest 'Empty database' => sub {
  my $dir    = $tmp->child('one');
  my $buffer = '';
  {
    open my $handle, '>', \$buffer;
    local *STDOUT = $handle;
    $app->start('learn', '-o', "$dir");
  }
  like $buffer, qr/Exported 0 snippets/, 'no snippets';
  ok -e $dir->child('good'), 'directory exists';
  ok -e $dir->child('bad'),  'directory exists';
};

subtest 'Snippets added' => sub {
  $cavil_test->mojo_fixtures($app);
  $app->minion->enqueue(unpack => [1]);
  $app->minion->perform_jobs;
  my $db = $app->pg->db;
  $db->query('UPDATE snippets SET license = false, approved = true WHERE id = 1');
  $db->query('UPDATE snippets SET license = true, approved = true WHERE id = 2');
  $db->query('UPDATE snippets SET license = true, approved = false WHERE id = 3');
  my $dir = $tmp->child('two');

  subtest 'Output snippets' => sub {
    my $buffer = '';
    {
      open my $handle, '>', \$buffer;
      local *STDOUT = $handle;
      $app->start('learn', '-o', "$dir");
    }
    like $buffer, qr/Exporting snippet 1/, 'first snippet';
    like $buffer, qr/Exporting snippet 2/, 'second snippet';
    like $buffer, qr/Exported 2 snippets/, 'two snippets exported';

    my $bad = $dir->child('bad')->list;
    is $bad->size, 1, 'one file';
    like $bad->first->slurp, qr/Fixed copyright notice/, 'right content';
    my $good = $dir->child('good')->list;
    is $good->size, 1, 'one file';
    like $good->first->slurp, qr/Copyright Holder/, 'right content';
  };

  subtest 'Output license patterns' => sub {
    my $buffer = '';
    {
      open my $handle, '>', \$buffer;
      local *STDOUT = $handle;
      $app->start('learn', '-p', '-o', "$dir");
    }
    like $buffer, qr/Exporting pattern 1/, 'first pattern';
    like $buffer, qr/Exporting pattern 2/, 'second pattern';
    like $buffer, qr/Exported 4 patterns/, 'six patterns exported';

    my $good = $dir->child('good')->list;
    is $good->size, 5, 'seven files';
    like $good->[1]->slurp, qr/Apache License/, 'right content';
  };

  $db->query('UPDATE snippets SET license = true, approved = false WHERE id = 1');
  $db->query('UPDATE snippets SET license = false, approved = false WHERE id = 2');
  $dir->child('good', 'doesnotexist.txt')->spew('Whatever');
  $dir->child('bad',  'doesnotexist.txt')->spew('Whatever');

  subtest 'Input snippets' => sub {
    my $buffer = '';
    {
      open my $handle, '>', \$buffer;
      local *STDOUT = $handle;
      $app->start('learn', '-i', "$dir");
    }
    like $buffer, qr/Imported 2 snippet classifications/, 'two snippets imported';

    my $first = $db->select('snippets', '*', {id => 1})->hash;
    is $first->{license},    0, 'is not a license';
    is $first->{classified}, 1, 'is classified';
    is $first->{approved},   1, 'is approved';

    my $second = $db->select('snippets', '*', {id => 2})->hash;
    is $second->{license},    1, 'is license';
    is $second->{approved},   1, 'is approved';
    is $second->{classified}, 1, 'is classified';

    my $third = $db->select('snippets', '*', {id => 3})->hash;
    is $third->{approved},   0, 'not approved';
    is $third->{classified}, 0, 'not classified';
  };

  subtest 'Input snippets (repeat does nothing)' => sub {
    my $buffer = '';
    {
      open my $handle, '>', \$buffer;
      local *STDOUT = $handle;
      $app->start('learn', '-i', "$dir");
    }
    like $buffer, qr/Imported 0 snippet classifications/, 'no snippets imported';
  };

  subtest 'Convert arbitrary text files' => sub {
    my $dir = $tmp->child('convert')->make_path;
    $dir->child('test.txt')->spew("Hello\nCavil\n");
    $dir->child('test2')->spew("Hello\nAgain\n");
    ok -e $dir->child('test.txt'), 'file exists';
    ok -e $dir->child('test2'),    'file exists';

    my $buffer = '';
    {
      open my $handle, '>', \$buffer;
      local *STDOUT = $handle;
      $app->start('learn', '--convert', "$dir");
    }
    like $buffer, qr/Converted test.txt to c512411bea5f292484180fb72e5ea0f9.txt/, 'first file';
    like $buffer, qr/Converted test2 to 00911bf540aebe36e7c2908760515b25.txt/,    'second file';

    ok !-e $dir->child('test.txt'), 'file no longer exists';
    ok !-e $dir->child('test2'),    'file no longer exists';
    is $dir->child('c512411bea5f292484180fb72e5ea0f9.txt')->slurp, "Hello\nCavil\n", 'right content';
    is $dir->child('00911bf540aebe36e7c2908760515b25.txt')->slurp, "Hello\nAgain\n", 'right content';
  };
};

subtest 'Embargo handling' => sub {
  my $dir = $tmp->child('embargo')->make_path;

  my $pkg_id = $app->packages->add(
    name            => 'some-security-package',
    checkout_dir    => 'f51a419bea8f272484680fb72e5e1234',
    api_url         => 'https://api.opensuse.org',
    requesting_user => 1,
    project         => 'openSUSE:Factory',
    priority        => 3,
    package         => 'some-security-package',
    srcmd5          => 'a51a419bea8f272484680fb72e5e123f',
    embargoed       => 1
  );
  my $snippets       = $app->snippets;
  my $snippet_one_id = $snippets->find_or_create(
    {hash => 'b51a469b6a8f2624866806b7265e123c', text => 'This is an embargo test', package => $pkg_id});
  my $snippet_two_id = $snippets->find_or_create(
    {hash => '751746976a8f7624766807b7265e1237', text => 'This is another embargo test', package => $pkg_id});
  my $snippet_three_id
    = $snippets->find_or_create({hash => 'abcd46976a8f7624766807b7265e12cd', text => 'Abandoned unembargoed snippet'});
  $snippets->approve($snippet_one_id,   'true');
  $snippets->approve($snippet_two_id,   'false');
  $snippets->approve($snippet_three_id, 'true');

  subtest 'Embargoed snippets are not exported' => sub {
    my $buffer = '';
    {
      open my $handle, '>', \$buffer;
      local *STDOUT = $handle;
      $app->start('learn', '-o', "$dir");
    }
    like $buffer, qr/Exporting snippet 1/, 'first snippet';
    like $buffer, qr/Exporting snippet 2/, 'second snippet';
    like $buffer, qr/Exporting snippet 9/, 'third snippet';
    like $buffer, qr/Exported 3 snippets/, 'two snippets exported';

    ok !-e $dir->child('bad',  '751746976a8f7624766807b7265e1237.txt'), 'embargoed file does not exist';
    ok !-e $dir->child('good', 'b51a469b6a8f2624866806b7265e123c.txt'), 'embargoed file does not exist';

    my $bad = $dir->child('bad')->list;
    is $bad->size, 1, 'one file';
    like $bad->first->slurp, qr/Fixed copyright notice/, 'right content';
    my $good = $dir->child('good')->list;
    is $good->size, 2, 'two files';
    like $good->first->slurp, qr/Copyright Holder/,              'right content';
    like $good->last->slurp,  qr/Abandoned unembargoed snippet/, 'right content';
  };

  subtest 'Snippets are exported once the embargo status has been lifted' => sub {
    $snippets->find_or_create(
      {hash => 'b51a469b6a8f2624866806b7265e123c', text => 'This is an embargo test', package => 1});
    $snippets->find_or_create(
      {hash => '751746976a8f7624766807b7265e1237', text => 'This is another embargo test', package => 1});


    my $buffer = '';
    {
      open my $handle, '>', \$buffer;
      local *STDOUT = $handle;
      $app->start('learn', '-o', "$dir");
    }
    like $buffer, qr/Exporting snippet 7/, 'first unembargoed snippet';
    like $buffer, qr/Exporting snippet 8/, 'second unembargoed snippet';
    like $buffer, qr/Exported 5 snippets/, 'five snippets exported';

    ok -e $dir->child('bad',  '751746976a8f7624766807b7265e1237.txt'), 'unembargoed file does exist';
    ok -e $dir->child('good', 'b51a469b6a8f2624866806b7265e123c.txt'), 'unembargoed file does exist';

    my $bad = $dir->child('bad')->list;
    is $bad->size, 2, 'two files';
    my $good = $dir->child('good')->list;
    is $good->size, 3, 'three files';
    like $dir->child('bad', '751746976a8f7624766807b7265e1237.txt')->slurp, qr/This is another embargo test/,
      'right content';
    like $dir->child('good', 'b51a469b6a8f2624866806b7265e123c.txt')->slurp, qr/This is an embargo test/,
      'right content';
  };
};

done_testing();
