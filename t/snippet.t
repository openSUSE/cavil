# Copyright (C) 2018-2020 SUSE LLC
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
use Mojo::JSON  qw(true false);

plan skip_all => 'set TEST_ONLINE to enable this test' unless $ENV{TEST_ONLINE};

my $cavil_test = Cavil::Test->new(online => $ENV{TEST_ONLINE}, schema => 'snippet_test');
my $t          = Test::Mojo->new(Cavil => $cavil_test->default_config);
$cavil_test->mojo_fixtures($t->app);

my $db = $t->app->pg->db;

subtest 'Snippet metadata' => sub {
  $t->get_ok('/login')->status_is(302)->header_is(Location => '/');

  $t->get_ok('/snippets/meta?isClassified=false')->status_is(200)->json_hasnt('/snippets/0');
  my $id = $t->app->snippets->find_or_create({hash => '0000', text => 'Licenses are cool'});
  $t->get_ok('/snippets/meta?isClassified=false')
    ->status_is(200)
    ->json_has('/snippets/0')
    ->json_is('/snippets/0/classified', false)
    ->json_is('/snippets/0/approved',   false);

  $t->get_ok('/logout')->status_is(302)->header_is(Location => '/');
};

subtest 'Snippet approval' => sub {
  $t->post_ok('/snippets/1' => form => {license => 'false'})->status_is(403);

  $t->get_ok('/login')->status_is(302)->header_is(Location => '/');
  $t->post_ok('/snippets/1' => form => {license => 'false'})->status_is(200);

  $t->get_ok('/snippets/meta?isClassified=false')->status_is(200)->json_hasnt('/snippets/0');

  my $res = $db->select('snippets', [qw(classified approved license)])->hash;
  is_deeply($res, {classified => 1, approved => 1, license => 0}, 'all fields updated');
};

# A manual approval changes the snippet's license, which is an input to the stored fold/clear/overlap
# resolution. The endpoint must re-analyze the affected packages so that resolution (and the cached
# report, file browser, SPDX and triage filter that read it) does not go stale.
subtest 'approval refreshes the stored resolution of affected packages' => sub {
  my $ct = Cavil::Test->new(online => $ENV{TEST_ONLINE}, schema => 'snippet_approve_test');
  my $cfg
    = {%{$ct->default_config}, snippet_fold => {enabled => 1, threshold => 0.9, min_margin => 0.1, max_risk => 9}};
  my $tt  = Test::Mojo->new(Cavil => $cfg);
  my $app = $tt->app;
  $ct->package_with_snippets_fixtures($app);
  $app->minion->enqueue(unpack => [1]);
  $app->minion->perform_jobs;
  my $d = $app->pg->db;

  # Make one snippet a confident, current-version GPL match so it folds, then resolve.
  my $gpl = $d->query("SELECT id FROM license_patterns WHERE license = 'GPL' LIMIT 1")->hash->{id};
  my $sid = $d->query('SELECT min(snippet) AS id FROM file_snippets WHERE package = 1')->hash->{id};
  $d->update(
    'snippets',
    {
      license       => 1,
      classified    => 1,
      likelyness    => 0.99,
      second_match  => 0,
      score_version => SNIPPET_SCORE_VERSION,
      like_pattern  => $gpl
    },
    {id => $sid}
  );
  $app->snippets->resolve_snippets(1);
  is $d->query('SELECT resolution FROM file_snippets WHERE snippet = ? LIMIT 1', $sid)->hash->{resolution}, 'fold',
    'snippet folds before the correction';

  # A reviewer marks it as not legal text through the approval endpoint.
  $tt->get_ok('/login')->status_is(302);
  $app->minion->reset;    # clear the index/analyze jobs from setup so we can see the approval's effect
  $tt->post_ok("/snippets/$sid" => form => {license => 'false'})->status_is(200);
  ok $app->minion->jobs({tasks => ['analyze']})->total, 'approval enqueued analysis for the affected package';

  $app->minion->perform_jobs;
  is $app->minion->jobs({states => ['failed']})->total, 0, 'no failed jobs';
  is $d->query('SELECT resolution FROM file_snippets WHERE snippet = ? LIMIT 1', $sid)->hash->{resolution}, undef,
    'the stale fold is cleared once the snippet is no longer legal text';
};

done_testing();
