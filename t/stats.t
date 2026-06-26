# Copyright (C) 2024 SUSE LLC
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

use Mojo::Base -strict;

use FindBin;
use lib "$FindBin::Bin/lib";

use Test::More;
use Test::Mojo;
use Cavil::Test;

plan skip_all => 'set TEST_ONLINE to enable this test' unless $ENV{TEST_ONLINE};

my $cavil_test = Cavil::Test->new(online => $ENV{TEST_ONLINE}, schema => 'stats_test');
my $t          = Test::Mojo->new(Cavil => $cavil_test->default_config);
$cavil_test->mojo_fixtures($t->app);

subtest 'Statistics' => sub {
  $t->get_ok('/login')->status_is(302)->header_is(Location => '/');

  $t->get_ok('/stats')->status_is(200)->content_like(qr/id="statistics"/);
  $t->get_ok('/stats/meta')
    ->status_is(200)
    ->json_is('/active_packages',    2)
    ->json_is('/embargoed_packages', 0)
    ->json_is('/open_reviews'      => 2)
    ->json_is('/rejected_packages' => 0)
    ->json_is('/manual_reviews'    => 0)
    ->json_has('/unresolved_matches')
    ->json_has('/performed_reviews')
    ->json_has('/automated_reviews')
    ->json_has('/monthly_performed_reviews')
    ->json_has('/monthly_manual_reviews')
    ->json_has('/monthly_automated_reviews')
    ->json_has('/imported_activity')
    ->json_has('/imported_activity/0/bucket')
    ->json_has('/imported_activity/0/label')
    ->json_has('/imported_activity/0/count')
    ->json_has('/imported_activity/23/count')
    ->json_has('/weekly_imported_activity')
    ->json_has('/weekly_imported_activity/0/bucket')
    ->json_has('/weekly_imported_activity/0/label')
    ->json_has('/weekly_imported_activity/0/count')
    ->json_has('/weekly_imported_activity/6/count')
    ->json_has('/total_snippets')
    ->json_has('/total_license_patterns');

  $t->get_ok('/logout')->status_is(302)->header_is(Location => '/');
};

done_testing;
