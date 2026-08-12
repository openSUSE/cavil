# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Mojo::Base -strict;

use FindBin;
use lib "$FindBin::Bin/lib";

use Test::More;
use Test::Mojo;
use Cavil::Test;
use Mojo::File qw(tempdir);

plan skip_all => 'set TEST_ONLINE to enable this test' unless $ENV{TEST_ONLINE};

my $cavil_test = Cavil::Test->new(online => $ENV{TEST_ONLINE}, schema => 'command_sync_test');
my $config     = $cavil_test->default_config;
my $t          = Test::Mojo->new(Cavil => $config);
my $app        = $t->app;
$cavil_test->mojo_fixtures($app);

my $tempdir = tempdir;
my $path    = $tempdir->child('license_patterns.jsonl');

subtest 'Sync' => sub {
  subtest 'Export' => sub {
    ok !-f $path, 'file does not exist';
    my $buffer = '';
    {
      open my $handle, '>', \$buffer;
      local *STDERR = $handle;
      $app->start('sync', '-e', $path);
    }
    like $buffer, qr/Exporting 6 patterns/, 'right output';
    ok -f $path, 'file exists';
  };

  subtest 'Import' => sub {
    my $buffer = '';
    {
      open my $handle, '>', \$buffer;
      local *STDERR = $handle;
      $app->start('sync', '-i', $path);
    }
    like $buffer, qr/Importing 6 patterns/, 'right output';
  };
};

done_testing();
