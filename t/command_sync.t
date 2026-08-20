# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Mojo::Base -strict;

use FindBin;
use lib "$FindBin::Bin/lib";

use Test::More;
use Test::Mojo;
use Cavil::Test;
use Mojo::File qw(tempdir);
use Mojo::JSON qw(decode_json);

plan skip_all => 'set TEST_ONLINE to enable this test' unless $ENV{TEST_ONLINE};

my $cavil_test = Cavil::Test->new(online => $ENV{TEST_ONLINE}, schema => 'command_sync_test');
my $config     = $cavil_test->default_config;
my $t          = Test::Mojo->new(Cavil => $config);
my $app        = $t->app;
$cavil_test->mojo_fixtures($app);

my $tempdir = tempdir;
my $path    = $tempdir->child('license_patterns.jsonl');

# Curated legal properties have to survive the round trip, or seeding an instance from the production corpus
# quietly drops them. Nothing downstream would notice: the pattern still matches, it just stops being the
# license text a NOTICE reproduces.
my $curated = $app->patterns->create(
  pattern           => 'Sync fixture terms, curated and at some length',
  license           => 'Sync-Fixture-1.0',
  risk              => 5,
  cla               => 1,
  full_license_text => 1
)->{id};

subtest 'Sync' => sub {
  subtest 'Export' => sub {
    ok !-f $path, 'file does not exist';
    my $buffer = '';
    {
      open my $handle, '>', \$buffer;
      local *STDERR = $handle;
      $app->start('sync', '-e', $path);
    }
    like $buffer, qr/Exporting 7 patterns/, 'right output';
    ok -f $path, 'file exists';

    my ($line) = grep {/Sync-Fixture-1\.0/} split /\n/, $path->slurp;
    my $row    = decode_json($line);
    is $row->{full_license_text}, 1, 'the curated-text claim is exported';
    is $row->{cla},               1, 'alongside the other legal properties';
  };

  subtest 'Import' => sub {
    my $buffer = '';
    {
      open my $handle, '>', \$buffer;
      local *STDERR = $handle;
      $app->start('sync', '-i', $path);
    }
    like $buffer, qr/Importing 7 patterns/, 'right output';

    # Re-import into a database that already has them, so the rows are dedupe-skipped rather than doubled
    is $app->pg->db->query('SELECT COUNT(*) FROM license_patterns WHERE full_license_text')->array->[0], 1,
      'and importing it again leaves exactly one claim standing';
  };
};

done_testing();
