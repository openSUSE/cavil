# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Mojo::Base -strict, -signatures;

use FindBin;
use lib "$FindBin::Bin/lib";

use Test::More;
use Test::Mojo;
use Cavil::Test;

plan skip_all => 'set TEST_ONLINE to enable this test' unless $ENV{TEST_ONLINE};

my $cavil_test = Cavil::Test->new(online => $ENV{TEST_ONLINE}, schema => 'ephemeral_isolation_test');
my $t          = Test::Mojo->new(Cavil => $cavil_test->default_config);
my $app        = $t->app;
$cavil_test->no_fixtures($app);

my $db   = $app->pg->db;
my $usr  = $db->insert('bot_users', {login => 'tester'}, {returning => 'id'})->hash->{id};
my $pkgs = $app->packages;

sub add_pkg ($dir, %extra) {
  my $id = $pkgs->add(
    name            => 'iso-test',
    package         => 'iso-test',
    checkout_dir    => $dir,
    srcmd5          => $dir,
    api_url         => '',
    requesting_user => $usr,
    project         => '',
    priority        => 5
  );
  $db->update('bot_packages', {checksum => 'dup', indexed => \'now()', %extra}, {id => $id});
  return $id;
}

# A normal package auto-accepted (no manual reviewer), and an ephemeral one that a human did touch, sharing
# the same name and report checksum. The ephemeral one must be invisible to every auto-review sibling
# lookup, so it can neither anchor nor veto the normal package's review and its later purge changes nothing.
my $normal    = add_pkg('a' x 32, state => 'acceptable');
my $ephemeral = add_pkg('b' x 32, state => 'acceptable', reviewing_user => $usr, ephemeral => 1);

subtest 'Ephemeral packages are excluded from auto-review sibling lookups' => sub {
  ok !$pkgs->has_manual_review('iso-test'), 'a manual review on an ephemeral sibling does not count';

  my %hist = map { $_->{id} => 1 } @{$pkgs->history('iso-test', 'dup', -1)};
  ok $hist{$normal},     'normal sibling is in the history';
  ok !$hist{$ephemeral}, 'ephemeral sibling is excluded from the history';

  my %old = map { $_->{id} => 1 } @{$pkgs->old_reviews({name => 'iso-test', id => -1})};
  ok $old{$normal},     'normal sibling is an old-review candidate';
  ok !$old{$ephemeral}, 'ephemeral sibling is excluded from old-review candidates';
};

done_testing;
