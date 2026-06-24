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

use Mojo::Base -strict;

use FindBin;
use lib "$FindBin::Bin/lib";

use Test::More;
use Test::Mojo;
use Cavil::Test;
use Cavil::Util qw(SNIPPET_SCORE_VERSION);

plan skip_all => 'set TEST_ONLINE to enable this test' unless $ENV{TEST_ONLINE};

my $cavil_test = Cavil::Test->new(online => $ENV{TEST_ONLINE}, schema => 'spdx_fold_test');
my $config     = {%{$cavil_test->default_config},
  snippet_fold => {enabled => 1, threshold => 0.9, min_margin => 0.1, max_risk => 9}};
my $t   = Test::Mojo->new(Cavil => $config);
my $app = $t->app;
$cavil_test->spdx_fixtures($app);
my $db = $app->pg->db;

$app->minion->enqueue(unpack => [1]);
$app->minion->perform_jobs;
$t->get_ok('/login')->status_is(302);

subtest 'a folded snippet contributes its license to the SPDX report' => sub {

  # Fold one snippet into a synthetic license whose SPDX id cannot appear from any real match, so
  # its presence in the report proves it came from fold-in.
  my $pattern = $app->patterns->create(pattern => 'a unique foldable license marker phrase', license => 'Fold-Test');
  $db->query('UPDATE license_patterns SET spdx = ?, risk = 2 WHERE id = ?', 'Fold-Test-SPDX', $pattern->{id});
  is $db->query(
    'UPDATE snippets SET classified = TRUE, license = TRUE, like_pattern = ?, likelyness = 0.99, second_match = 0,
       score_version = ? WHERE id = (SELECT min(id) FROM snippets)', $pattern->{id}, SNIPPET_SCORE_VERSION
  )->rows, 1, 'one snippet set up to fold';

  $t->get_ok('/spdx/1')->status_is(408);
  $app->minion->perform_jobs;
  is $app->minion->jobs({states => ['failed']})->total, 0, 'no failed jobs';

  my $report = $t->get_ok('/spdx/1')->status_is(200)->tx->res->text;
  like $report, qr/SPDXVersion/,                                   'is a real SPDX report';
  like $report, qr/LicenseInfoInFile:\s*Fold-Test-SPDX/,           'folded license is listed for the file';
  like $report, qr/PackageLicenseInfoFromFiles:\s*Fold-Test-SPDX/, 'folded license is in the package license list';
};

subtest 'a cleared boilerplate snippet asserts no license in the SPDX report' => sub {
  my $ct  = Cavil::Test->new(online => $ENV{TEST_ONLINE}, schema => 'spdx_clear_test');
  my $cfg = {
    %{$ct->default_config},
    snippet_fold => {enabled => 1, threshold => 0.95, min_margin => 0.15, max_risk => 5, clear_threshold => 0.95}
  };
  my $tt = Test::Mojo->new(Cavil => $cfg);
  my $a  = $tt->app;
  my $d  = $a->pg->db;
  $ct->spdx_fixtures($a);
  $a->minion->enqueue(unpack => [1]);
  $a->minion->perform_jobs;
  $tt->get_ok('/login')->status_is(302);

  my $p = $a->patterns->create(pattern => 'a unique clearable license marker phrase', license => 'Clear-Test');
  $d->query('UPDATE license_patterns SET spdx = ?, risk = 2 WHERE id = ?', 'Clear-Test-SPDX', $p->{id});

  # Zero margin so it cannot fold; high containment so it clears -> no license asserted.
  $d->query(
    'UPDATE snippets SET classified = TRUE, license = TRUE, like_pattern = ?, likelyness = 0.99, second_match = 0.99,
       score_version = ? WHERE id = (SELECT min(id) FROM snippets)', $p->{id}, SNIPPET_SCORE_VERSION
  );

  $tt->get_ok('/spdx/1')->status_is(408);
  $a->minion->perform_jobs;
  my $report = $tt->get_ok('/spdx/1')->status_is(200)->tx->res->text;
  like $report,   qr/SPDXVersion/,     'is a real SPDX report';
  unlike $report, qr/Clear-Test-SPDX/, 'cleared boilerplate asserts no license';
};

done_testing;
