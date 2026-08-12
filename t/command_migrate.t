# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Mojo::Base -strict;

use FindBin;
use lib "$FindBin::Bin/lib";

use Test::More;
use Test::Mojo;
use Cavil::Test;

plan skip_all => 'set TEST_ONLINE to enable this test' unless $ENV{TEST_ONLINE};

my $cavil_test = Cavil::Test->new(online => $ENV{TEST_ONLINE}, schema => 'command_migrate_test');
my $config     = $cavil_test->default_config;
my $t          = Test::Mojo->new(Cavil => $config);
my $app        = $t->app;
$cavil_test->no_fixtures($app);
$app->pg->migrations->migrate(0);

subtest 'Migrate' => sub {
  is $app->pg->migrations->active, 0, 'version 0 is active';
  my $latest = $app->pg->migrations->latest;
  my $buffer = '';
  {
    open my $handle, '>', \$buffer;
    local *STDOUT = $handle;
    $app->start('migrate');
  }
  like $buffer, qr/Migrated from/, 'right output';
  is $app->pg->migrations->active, $latest, 'latest version is active';

  $buffer = '';
  {
    open my $handle, '>', \$buffer;
    local *STDOUT = $handle;
    $app->start('migrate');
  }
  like $buffer, qr/Nothing to do/, 'right output';
  is $app->pg->migrations->active, $latest, 'latest version is active';
};

done_testing();
