# Copyright (C) 2025 SUSE LLC
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

plan skip_all => 'set TEST_ONLINE to enable this test' unless $ENV{TEST_ONLINE};

my $cavil_test = Cavil::Test->new(online => $ENV{TEST_ONLINE}, schema => 'command_unpack_test');
my $config     = $cavil_test->default_config;
my $t          = Test::Mojo->new(Cavil => $config);
my $app        = $t->app;
$cavil_test->mojo_fixtures($app);

my $minion = $app->minion;
$minion->enqueue('unpack', [2]);
$minion->perform_jobs;

subtest 'Unpack' => sub {
  subtest 'Re-unpack package' => sub {
    is $app->minion->jobs({tasks => ['unpack']})->total, 1, 'one unpack job';
    my $buffer = '';
    {
      open my $handle, '>', \$buffer;
      local *STDOUT = $handle;
      $app->start('unpack', '2');
    }
    unlike $buffer, qr/Releasing locks/,      'no locks released';
    like $buffer,   qr/Triggered unpack job/, 'unpack job triggered';
    is $app->minion->jobs({tasks => ['unpack']})->total, 2, 'two unpack jobs';
  };

  subtest 'Unpacking in progress' => sub {
    my $buffer = '';
    {
      open my $handle, '>', \$buffer;
      local *STDOUT = $handle;
      $app->start('unpack', '2');
    }
    like $buffer, qr/Unpacking already in progress/, 'in progress';
    is $app->minion->jobs({tasks => ['unpack']})->total, 2, 'two unpack jobs';
  };

  my $worker = $app->minion->worker->register;
  my $job    = $worker->dequeue(0);
  $job->fail('Something went wrong');

  subtest 'Unlock failed prior attempt' => sub {
    is $app->minion->jobs({tasks => ['unpack']})->total, 2, 'two unpack jobs';
    $minion->lock('processing_pkg_2', 172800);
    my $buffer = '';
    {
      open my $handle, '>', \$buffer;
      local *STDOUT = $handle;
      $app->start('unpack', '2');
    }
    like $buffer, qr/Releasing locks for package 2/, 'package locks released';
    like $buffer, qr/Triggered unpack job/,          'unpack job triggered';
    is $app->minion->jobs({tasks => ['unpack']})->total, 3, 'three unpack jobs';
  };
};

done_testing();
