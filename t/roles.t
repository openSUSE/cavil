# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later
use Mojo::Base -strict, -signatures;

use FindBin;
use lib "$FindBin::Bin/lib";

use Test::More;
use Test::Mojo;
use Cavil::Test;

plan skip_all => 'set TEST_ONLINE to enable this test' unless $ENV{TEST_ONLINE};

# End-to-end authorization matrix: for every role, hit a representative route for each capability and
# assert access (not 403) vs denial (403). The expected role sets below are written out independently of
# Cavil::Role, so this catches both a wrong map AND a mis-wired route/gate. Bogus ids (999999) are used
# for the mutating POST routes so an "allowed" probe reaches the controller (404) without changing state.
my $ct = Cavil::Test->new(online => $ENV{TEST_ONLINE}, schema => 'roles_test');
my $t  = Test::Mojo->new(Cavil => $ct->default_config);
$ct->mojo_fixtures($t->app);
my $db = $t->app->pg->db;

# Log in (Dummy) to get a session cookie, then drive the tester's roles per case.
$t->get_ok('/login')->status_is(302);
my $set_roles = sub (@roles) { $db->update('bot_users', {roles => [@roles]}, {login => 'tester'}) };
my $code      = sub ($method, $url) { $t->$method($url); return $t->tx->res->code };

my @probes = (
  {cap => 'infra',          method => 'get_ok',  url => '/upload',                        allow => [qw(admin)]},
  {cap => 'curate',         method => 'get_ok',  url => '/licenses/new_pattern',          allow => [qw(admin lawyer)]},
  {cap => 'curate/review',  method => 'post_ok', url => '/reviews/review_package/999999', allow => [qw(admin lawyer)]},
  {cap => 'curate/reindex', method => 'post_ok', url => '/reviews/reindex/999999',        allow => [qw(admin lawyer)]},
  {
    cap    => 'propose',
    method => 'get_ok',
    url    => '/snippets/from_file/999999/1/2',
    allow  => [qw(admin contributor lawyer)]
  },
  {cap => 'classify', method => 'post_ok', url => '/snippets/999999', allow => [qw(admin classifier lawyer)]},
  {
    cap    => 'review',
    method => 'post_ok',
    url    => '/reviews/fasttrack_package/999999',
    allow  => [qw(admin lawyer manager)]
  },
);

subtest 'capability matrix' => sub {
  for my $role (qw(user classifier contributor manager admin lawyer)) {
    $set_roles->($role);
    for my $p (@probes) {
      my $allowed = grep { $_ eq $role } @{$p->{allow}};
      my $c       = $code->($p->{method}, $p->{url});
      if   ($allowed) { isnt $c, 403, "role '$role' is allowed: $p->{cap} ($p->{url})" }
      else            { is $c,   403, "role '$role' is denied: $p->{cap} ($p->{url})" }
    }
  }
};

subtest 'acceptable_by_lawyer is derived from the lawyer role, never minted' => sub {

  # A non-lawyer curator (plain admin) accepts - even posting the old acceptable_by_lawyer param, the
  # state is a plain "acceptable"; the request can never assert lawyer sign-off.
  $set_roles->('admin');
  $db->update('bot_packages', {state => 'new'}, {id => 1});
  $t->post_ok('/reviews/review_package/1' => form => {comment => 'ok', acceptable => 1, acceptable_by_lawyer => 1})
    ->status_is(200);
  is $t->app->packages->find(1)->{state}, 'acceptable', 'admin accept -> acceptable (param ignored, not minted)';

  # A lawyer accepting the very same way produces the lawyer sign-off.
  $set_roles->('lawyer');
  $db->update('bot_packages', {state => 'new'}, {id => 1});
  $t->post_ok('/reviews/review_package/1' => form => {comment => 'ok', acceptable => 1})->status_is(200);
  is $t->app->packages->find(1)->{state}, 'acceptable_by_lawyer', 'lawyer accept -> acceptable_by_lawyer';

  # Reject is available to a curator and always yields unacceptable.
  $db->update('bot_packages', {state => 'new'}, {id => 1});
  $t->post_ok('/reviews/review_package/1' => form => {comment => 'no', unacceptable => 1})->status_is(200);
  is $t->app->packages->find(1)->{state}, 'unacceptable', 'reject -> unacceptable';
};

done_testing;
