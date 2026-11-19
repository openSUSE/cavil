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

  like $families->(), qr/Regrouped 3 package families/, 'both exact names and the new lower case family';
  is $pkgs->find($id)->{family}, 'perl-mojolicious', 'grouped';
  is $pkgs->find(1)->{family},   'perl-mojolicious', 'base package in the same family';
  like $families->(), qr/Regrouped 0 package families/, 'nothing left to do';
};

subtest 'A rename to other letter case stays in the family' => sub {
  my $pkgs = $app->packages;
  my $id   = $pkgs->add(
    name            => 'Perl-Mojolicious',
    checkout_dir    => 'c7cfdab0e71b0bebfdf8b2dc3badfece',
    api_url         => 'https://api.opensuse.org',
    requesting_user => 1,
    project         => 'devel:languages:perl',
    package         => 'Perl-Mojolicious',
    srcmd5          => 'd7cfdab0e71b0bebfdf8b2dc3badfecd',
    priority        => 5
  );
  $app->pg->db->query('UPDATE bot_packages SET family = name WHERE id = ?', $id);

  like $families->(), qr/Regrouped 2 package families/, 'the exact name and the shared family';
  is $pkgs->find($id)->{family}, 'perl-mojolicious', 'grouped with the old spelling';
  my $names
    = $app->pg->db->query(
    "SELECT DISTINCT name FROM bot_packages WHERE family = 'perl-mojolicious' AND name NOT LIKE '%.%'")
    ->arrays->flatten;
  is_deeply [sort @$names], ['Perl-Mojolicious', 'perl-Mojolicious'], 'both spellings in one family';
};

done_testing;
