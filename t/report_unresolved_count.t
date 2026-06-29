# Copyright (C) 2026 SUSE LLC
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, see <http://www.gnu.org/licenses/>.

use Mojo::Base -strict, -signatures;

use FindBin;
use lib "$FindBin::Bin/lib";

use Test::More;
use Test::Mojo;
use Cavil::Test;

plan skip_all => 'set TEST_ONLINE to enable this test' unless $ENV{TEST_ONLINE};

# `max_expanded_files` exists only to cap how many file source previews a report renders (browser
# safety). It must NOT shrink the stored unresolved-matches count or the "files with unresolved matches"
# list. This drives the real unpack+analyze pipeline on a synthetic package with 110 files, each carrying
# one distinct unresolved keyword snippet, with the preview cap set low so most files fall past it.
my $cavil_test = Cavil::Test->new(online => $ENV{TEST_ONLINE}, schema => 'report_unresolved_count_test');

my $CAP   = 5;
my $FILES = 110;    # the synthetic fixture generates this many files, one unresolved snippet each

my $config = $cavil_test->default_config;
$config->{max_expanded_files} = $CAP;
my $t   = Test::Mojo->new(Cavil => $config);
my $app = $t->app;

$app->pg->migrations->migrate;
my $usr_id = $app->pg->db->insert('bot_users', {login => 'test_bot'}, {returning => 'id'})->hash->{id};
$cavil_test->_synthetic_many_unresolved_fixture($app, $usr_id);
$app->minion->perform_jobs;

my $db     = $app->pg->db;
my $pkg_id = $db->select('bot_packages', 'id', {name => 'synthetic-many-unresolved'})->hash->{id};
ok $pkg_id, 'synthetic package was indexed';

subtest 'stored count reflects ALL unresolved snippets, not just the previewed files' => sub {
  my $count = $db->select('bot_packages', 'unresolved_matches', {id => $pkg_id})->hash->{unresolved_matches};
  is $count, $FILES, "all $FILES unresolved snippets are counted (the cap must not truncate the count)";
};

subtest 'report serves the full unresolved-file list while capping inline previews' => sub {
  $t->get_ok('/login')->status_is(302);
  $t->get_ok("/reviews/report_details/$pkg_id")->status_is(200);
  my $data = $t->tx->res->json;

  is scalar(@{$data->{missed_files}}),     $FILES, "all $FILES files appear in the unresolved-files list";
  is $data->{package}{unresolved_matches}, $FILES, 'served count matches the full unresolved total';

  my $previewed = grep { $_->{expand} } @{$data->{files}};
  ok $previewed >= 1,    'at least one file is previewed inline';
  ok $previewed <= $CAP, "inline previews stay capped at max_expanded_files ($previewed <= $CAP)";
};

done_testing;
