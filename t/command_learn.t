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
    $app->start('learn', '-e', "$dir");
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

  subtest 'Export snippets' => sub {
    my $dir    = $tmp->child('two');
    my $buffer = '';
    {
      open my $handle, '>', \$buffer;
      local *STDOUT = $handle;
      $app->start('learn', '-e', "$dir");
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
};

done_testing();
