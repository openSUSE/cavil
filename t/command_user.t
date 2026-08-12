# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Mojo::Base -strict;

use FindBin;
use lib "$FindBin::Bin/lib";

use Test::More;
use Test::Mojo;
use Cavil::Test;

plan skip_all => 'set TEST_ONLINE to enable this test' unless $ENV{TEST_ONLINE};

my $cavil_test = Cavil::Test->new(online => $ENV{TEST_ONLINE}, schema => 'command_user_test');
my $config     = $cavil_test->default_config;
my $t          = Test::Mojo->new(Cavil => $config);
my $app        = $t->app;
$cavil_test->no_fixtures($app);
$app->users->find_or_create(login => 'tester');

subtest 'List users' => sub {
  my $buffer = '';
  {
    open my $handle, '>', \$buffer;
    local *STDOUT = $handle;
    $app->start('user');
  }
  like $buffer, qr/1  tester  user/, 'one user with default role';
};

subtest 'Add role' => sub {
  my $buffer = '';
  {
    open my $handle, '>', \$buffer;
    local *STDOUT = $handle;
    $app->start('user', '-A', 'admin', '1');
  }
  like $buffer, qr/user/,  'default role';
  like $buffer, qr/admin/, 'admin role';
};

subtest 'Remove role' => sub {
  my $buffer = '';
  {
    open my $handle, '>', \$buffer;
    local *STDOUT = $handle;
    $app->start('user', '-R', 'admin', '1');
  }
  like $buffer,   qr/user/,  'default role';
  unlike $buffer, qr/admin/, 'no admin role';
};

done_testing();
