# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Mojo::Base -strict;

use FindBin;
use lib "$FindBin::Bin/lib";

use Test::More;
use Test::Mojo;
use Cavil::Test;

plan skip_all => 'set TEST_ONLINE to enable this test' unless $ENV{TEST_ONLINE};

my $cavil_test = Cavil::Test->new(online => $ENV{TEST_ONLINE}, schema => 'command_families_test');
my $t          = Test::Mojo->new(Cavil => $cavil_test->default_config);
my $app        = $t->app;
$cavil_test->mojo_fixtures($app);

my $families = sub {
  my $buffer = '';
  {
    open my $handle, '>', \$buffer;
    local *STDOUT = $handle;
    $app->start('families');
  }
  return $buffer;
};

subtest 'Group what the upgrade left under exact names' => sub {
  my $pkgs = $app->packages;
  my $id   = $pkgs->add(
    name            => 'perl-Mojolicious.12345',
    checkout_dir    => 'a7cfdab0e71b0bebfdf8b2dc3badfecd',
    api_url         => 'https://api.opensuse.org',
    requesting_user => 1,
    project         => 'SUSE:Maintenance:12345',
    package         => 'perl-Mojolicious',
    srcmd5          => 'b7cfdab0e71b0bebfdf8b2dc3badfecd',
    priority        => 5
  );
  $app->pg->db->query('UPDATE bot_packages SET family = name');

  like $families->(), qr/Regrouped 2 package families/, 'old and new family of the copy';
  is $pkgs->find($id)->{family}, 'perl-Mojolicious', 'grouped';
  is $pkgs->find(1)->{family},   'perl-Mojolicious', 'base package unchanged';
  like $families->(), qr/Regrouped 0 package families/, 'nothing left to do';
};

done_testing;
