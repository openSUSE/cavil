# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Mojo::Base -strict;

use FindBin;
use lib "$FindBin::Bin/lib";

use Test::More;
use Test::Mojo;
use Cavil::Test;
use Mojo::File qw(path);

plan skip_all => 'set TEST_ONLINE to enable this test' unless $ENV{TEST_ONLINE};

my $cavil_test = Cavil::Test->new(online => $ENV{TEST_ONLINE}, schema => 'command_checkouts_test');
my $config     = $cavil_test->default_config;
my $t          = Test::Mojo->new(Cavil => $config);
my $app        = $t->app;
$cavil_test->mojo_fixtures($app);

subtest 'Default output' => sub {
  my $buffer = '';
  {
    open my $handle, '>', \$buffer;
    local *STDOUT = $handle;
    $app->start('checkouts');
  }
  like $buffer, qr/Checkouts stored in ".+": 1/, 'checkout directory and count';
};

subtest 'Detect abandoned checkout' => sub {
  my $dir       = path($cavil_test->checkout_dir);
  my $abandined = $dir->child('abandoned', '1234abcd5678ef90')->make_path;

  subtest 'Abandoned checkout' => sub {
    my $buffer = '';
    {
      open my $handle, '>', \$buffer;
      local *STDOUT = $handle;
      $app->start('checkouts', '--check-abandoned');
    }
    unlike $buffer, qr/perl-Mojolicious\/c7cfdab0e71b0bebfdf8b2dc3badfecd/, 'not abandoned';
    like $buffer,   qr/abandoned\/1234abcd5678ef90/,                        'abandoned';
  };

  $abandined->remove_tree;
  subtest 'Clean' => sub {
    my $buffer = '';
    {
      open my $handle, '>', \$buffer;
      local *STDOUT = $handle;
      $app->start('checkouts', '--check-abandoned');
    }
    unlike $buffer, qr/perl-Mojolicious\/c7cfdab0e71b0bebfdf8b2dc3badfecd/, 'not abandoned';
    unlike $buffer, qr/abandoned\/1234abcd5678ef90/,                        'not abandoned';
  };

  $app->pg->db->query('UPDATE bot_packages SET obsolete = TRUE WHERE id = 1');
  subtest 'Obsolete package waiting for cleanup' => sub {
    my $buffer = '';
    {
      open my $handle, '>', \$buffer;
      local *STDOUT = $handle;
      $app->start('checkouts', '--check-abandoned');
    }
    unlike $buffer, qr/perl-Mojolicious\/c7cfdab0e71b0bebfdf8b2dc3badfecd/, 'not abandoned';
    unlike $buffer, qr/abandoned\/1234abcd5678ef90/,                        'not abandoned';
  };

  $app->pg->db->query('UPDATE bot_packages SET obsolete = TRUE, cleaned = NOW() WHERE id = 1');
  subtest 'Obsolete package has been abandoned' => sub {
    my $buffer = '';
    {
      open my $handle, '>', \$buffer;
      local *STDOUT = $handle;
      $app->start('checkouts', '--check-abandoned');
    }
    like $buffer,   qr/perl-Mojolicious\/c7cfdab0e71b0bebfdf8b2dc3badfecd/, 'abandoned';
    unlike $buffer, qr/abandoned\/1234abcd5678ef90/,                        'not abandoned';
  };
};

done_testing();
