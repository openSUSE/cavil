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
use Cavil::Util qw(SNIPPET_SCORE_VERSION);

plan skip_all => 'set TEST_ONLINE to enable this test' unless $ENV{TEST_ONLINE};

sub capture ($app, @args) {
  my $buffer = '';
  open my $handle, '>', \$buffer;
  local *STDOUT = $handle;
  $app->start(@args);
  return $buffer;
}

subtest 'snippets without arguments prints usage' => sub {
  my $cavil_test = Cavil::Test->new(online => $ENV{TEST_ONLINE}, schema => 'command_snippets_usage_test');
  my $t          = Test::Mojo->new(Cavil => $cavil_test->default_config);
  $cavil_test->no_fixtures($t->app);
  like capture($t->app, 'snippets'), qr/--rescore/, 'shows the available options';
};

subtest 'snippets --rescore refuses to run without similarity signatures' => sub {
  my $cavil_test = Cavil::Test->new(online => $ENV{TEST_ONLINE}, schema => 'command_snippets_empty_test');
  my $t          = Test::Mojo->new(Cavil => $cavil_test->default_config);
  $cavil_test->no_fixtures($t->app);

  my $err = '';
  eval { capture($t->app, 'snippets', '--rescore'); 1 } or $err = $@;
  like $err, qr/run 'cavil pattern_stats'/, 'dies with a helpful message';
};

subtest 'snippets --rescore re-scores every snippet and stamps the version' => sub {
  my $cavil_test = Cavil::Test->new(online => $ENV{TEST_ONLINE}, schema => 'command_snippets_test');
  my $t          = Test::Mojo->new(Cavil => $cavil_test->default_config);
  my $app        = $t->app;
  $cavil_test->package_with_snippets_fixtures($app);
  $app->minion->enqueue(unpack => [1]);
  $app->minion->perform_jobs;
  my $db = $app->pg->db;
  ok $db->query('SELECT count(*) AS c FROM snippets')->hash->{c} > 0, 'fixture produced snippets';

  # Build the model, mark every snippet with a sentinel score / stale version, then re-score
  $app->patterns->rebuild_similarity_data;
  $db->query('UPDATE snippets SET likelyness = 0.999, score_version = 0');

  # (stdout is not asserted here: the preceding perform_jobs interferes with in-memory STDOUT
  # capture; the command's effect on the data is the meaningful check.)
  capture($app, 'snippets', '--rescore', '--batch', '100');
  is $db->query('SELECT count(*) AS c FROM snippets WHERE likelyness = 0.999')->hash->{c}, 0,
    'every snippet was re-scored (sentinel score overwritten)';
  is $db->query('SELECT count(*) AS c FROM snippets WHERE score_version <> ?', SNIPPET_SCORE_VERSION)->hash->{c}, 0,
    'every snippet stamped with the current score version';
};

subtest 'snippets --resolve recomputes the stored resolutions' => sub {
  my $cavil_test = Cavil::Test->new(online => $ENV{TEST_ONLINE}, schema => 'command_snippets_resolve_test');
  my $config     = {
    %{$cavil_test->default_config},
    snippet_fold => {enabled => 1, threshold => 0.9, min_margin => 0.1, max_risk => 9}
  };
  my $app = Test::Mojo->new(Cavil => $config)->app;
  $cavil_test->package_with_snippets_fixtures($app);
  $app->minion->enqueue(unpack => [1]);
  $app->minion->perform_jobs;
  my $db = $app->pg->db;

  # Make every snippet a confident GPL fold, then clear the stored resolutions to prove --resolve sets them
  my $gpl = $db->query("SELECT id FROM license_patterns WHERE license = 'GPL' LIMIT 1")->hash->{id};
  $db->query(
    'UPDATE snippets SET license = TRUE, classified = TRUE, likelyness = 0.99, second_match = 0,
       score_version = ?, like_pattern = ?', SNIPPET_SCORE_VERSION, $gpl
  );
  $db->query('UPDATE file_snippets SET resolution = NULL');

  capture($app, 'snippets', '--resolve');

  my $total  = $db->query('SELECT count(*) AS c FROM file_snippets')->hash->{c};
  my $folded = $db->query("SELECT count(*) AS c FROM file_snippets WHERE resolution = 'fold'")->hash->{c};
  ok $total > 0, 'fixture produced snippet occurrences';
  is $folded, $total, 'every occurrence was resolved to fold';
};

done_testing;
