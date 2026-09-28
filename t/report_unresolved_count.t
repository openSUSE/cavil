# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Mojo::Base -strict, -signatures;

use FindBin;
use lib "$FindBin::Bin/lib";

use Test::More;
use Test::Mojo;
use Cavil::Test;

plan skip_all => 'set TEST_ONLINE to enable this test' unless $ENV{TEST_ONLINE};

# Unresolved counts and file lists must never be truncated.
my $cavil_test = Cavil::Test->new(online => $ENV{TEST_ONLINE}, schema => 'report_unresolved_count_test');

my $FILES = 110;

my $t   = Test::Mojo->new(Cavil => $cavil_test->default_config);
my $app = $t->app;

$app->pg->migrations->migrate;
my $usr_id = $app->pg->db->insert('bot_users', {login => 'test_bot'}, {returning => 'id'})->hash->{id};
$cavil_test->_synthetic_many_unresolved_fixture($app, $usr_id);
$app->minion->perform_jobs;

my $db     = $app->pg->db;
my $pkg_id = $db->select('bot_packages', 'id', {name => 'synthetic-many-unresolved'})->hash->{id};
ok $pkg_id, 'synthetic package was indexed';

subtest 'stored count reflects ALL unresolved snippets' => sub {
  my $count = $db->select('bot_packages', 'unresolved_matches', {id => $pkg_id})->hash->{unresolved_matches};
  is $count, $FILES, "all $FILES unresolved snippets are counted";
};

subtest 'report serves the full unresolved-file list' => sub {
  $t->get_ok('/login')->status_is(302);
  $t->get_ok("/reviews/report_details/$pkg_id")->status_is(200);
  my $data = $t->tx->res->json;

  is scalar(@{$data->{missed_files}}),     $FILES, "all $FILES files appear in the unresolved-files list";
  is $data->{package}{unresolved_matches}, $FILES, 'served count matches the full unresolved total';
};

done_testing;
