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

subtest 'similarity round-trip: rebuild -> context -> best_license_for' => sub {
  my $cavil_test = Cavil::Test->new(online => $ENV{TEST_ONLINE}, schema => 'snippet_fold_sim_test');
  my $t          = Test::Mojo->new(Cavil => $cavil_test->default_config);
  $cavil_test->just_patterns_fixtures($t->app);
  my $patterns = $t->app->patterns;

  $patterns->rebuild_similarity_data;
  my $ctx = $patterns->similarity_context;
  ok $ctx,                             'context built from the sidecar';
  ok $ctx->{signatures}{'Apache-2.0'}, 'per-license signature built for Apache-2.0';

  # Relax the required-phrase gate: this tiny fixture corpus has only low IDF values (the gate is
  # exercised on its own in t/patterns_similarity.t); here we test the rebuild/store/load wiring.
  my $relaxed = {%$ctx, distinctive_idf => 0, min_distinctive => 1};
  my $r       = $patterns->best_license_for(
    'You may obtain a copy of the License at, Licensed under the Apache License, Version 2.0', $relaxed);
  is $r->{license}, 'Apache-2.0', 'snippet scored to the right license through the full round-trip';
  ok $r->{match} > 0.5, 'with a healthy score';
};

# The fold gate is exercised through the public report instead of the private decision method: we
# set snippet metadata, regenerate the report, and check whether the license folded in.
subtest 'fold-in gate (via the report)' => sub {
  my $cavil_test = Cavil::Test->new(online => $ENV{TEST_ONLINE}, schema => 'snippet_fold_report_test');
  my $config     = {
    %{$cavil_test->default_config},
    snippet_fold => {enabled => 1, threshold => 0.9, min_margin => 0.1, max_risk => 9}
  };
  my $t   = Test::Mojo->new(Cavil => $config);
  my $app = $t->app;
  $cavil_test->package_with_snippets_fixtures($app);
  $app->minion->enqueue(unpack => [1]);
  $app->minion->perform_jobs;
  my $db = $app->pg->db;

  my $gpl   = $db->query("SELECT id FROM license_patterns WHERE license = 'GPL' LIMIT 1")->hash;
  my $empty = $db->query("SELECT id FROM license_patterns WHERE license = '' LIMIT 1")->hash;
  ok $gpl && $empty, 'fixtures provide a real and an empty-license pattern';

  # A confident, classified, current-version, low-risk GPL match for every snippet is the baseline
  # that should fold; each case overrides one field to check a single gate.
  my %ok
    = (license => 1, likelyness => 0.99, second_match => 0, version => SNIPPET_SCORE_VERSION, pattern => $gpl->{id});
  my $folds = sub ($report_app, %override) {
    my %f       = (%ok, %override);
    my $license = $f{license} ? 'TRUE' : 'FALSE';
    $db->query(
      "UPDATE snippets SET license = $license, classified = TRUE, likelyness = ?, second_match = ?,
         score_version = ?, like_pattern = ?", $f{likelyness}, $f{second_match}, $f{version}, $f{pattern}
    );
    return $report_app->reports->dig_report(1)->{folded} ? 1 : 0;
  };

  ok $folds->($app), 'confident, current-version, low-risk legal snippet folds';
  my $report = $app->reports->dig_report(1);
  ok $report->{licenses}{'GPL'}, 'the folded license appears in the report';

  # The folded file must render in the source view highlighted as its inferred license (so clicking
  # the file in the license list shows why it is listed), not as an unresolved snippet.
  my ($expanded_file) = keys %{$report->{folded}};
  ok $report->{expanded}{$expanded_file}, 'the folded file is expanded for the source view';
  my $highlighted_as_gpl = grep { ($_->[1]{name} // '') eq 'GPL' } @{$report->{lines}{$expanded_file} // []};
  ok $highlighted_as_gpl, 'the folded region is highlighted as GPL in the source view';

  ok !$folds->($app, license      => 0),            'does not fold unless classified as legal text';
  ok !$folds->($app, likelyness   => 0.5),          'does not fold below the similarity threshold';
  ok !$folds->($app, second_match => 0.95),         'does not fold on a thin margin to the runner-up';
  ok !$folds->($app, version      => 0),            'does not fold rows scored by an older version';
  ok !$folds->($app, pattern      => $empty->{id}), 'does not fold an empty-license (keyword) pattern';

  # Risk gate: the same confident GPL (risk 5) must not fold for an app that caps risk at 4
  my $strict = Test::Mojo->new(
    Cavil => {
      %{$cavil_test->default_config},
      snippet_fold => {enabled => 1, threshold => 0.9, min_margin => 0.1, max_risk => 4}
    }
  );
  $folds->($app);    # reset to the confident baseline
  ok !$strict->app->reports->dig_report(1)->{folded}, 'does not fold a license above max_risk';

  # And nothing folds at all when the feature is disabled
  my $off = Test::Mojo->new(Cavil => $cavil_test->default_config);
  ok !$off->app->reports->dig_report(1)->{folded}, 'nothing folds when snippet_fold is disabled';
};

subtest 'boilerplate-clear (via the report)' => sub {
  my $cavil_test = Cavil::Test->new(online => $ENV{TEST_ONLINE}, schema => 'snippet_clear_test');
  my $config     = {
    %{$cavil_test->default_config},
    snippet_fold => {enabled => 1, threshold => 0.95, min_margin => 0.15, max_risk => 5, clear_threshold => 0.97}
  };
  my $t   = Test::Mojo->new(Cavil => $config);
  my $app = $t->app;
  $cavil_test->package_with_snippets_fixtures($app);
  $app->minion->enqueue(unpack => [1]);
  $app->minion->perform_jobs;
  my $db = $app->pg->db;

  # Point at a synthetic license that cannot otherwise appear in the report, so its absence proves
  # clearing asserts nothing.
  my $pattern = $app->patterns->create(pattern => 'a distinct clearable boilerplate marker', license => 'Clear-Test');

  # Ambiguous boilerplate: high containment but zero margin, so it can't fold - it should clear.
  $db->query(
    'UPDATE snippets SET license = TRUE, classified = TRUE, likelyness = 0.99, second_match = 0.99,
       score_version = ?, like_pattern = ?', SNIPPET_SCORE_VERSION, $pattern->{id}
  );

  my $report = $app->reports->dig_report(1);
  ok $report->{cleared},                 'snippet cleared as recognized license boilerplate';
  ok !$report->{folded},                 'not folded (no margin)';
  ok !$report->{licenses}{'Clear-Test'}, 'clearing asserts no license';
  is_deeply $report->{missed_files}, {}, 'nothing left in the unresolved list';

  # The file browser agrees: cleared regions render as resolved, not as risk-9 unresolved snippets
  $t->get_ok('/login')->status_is(302);
  my $source = $t->get_ok('/reviews/file_view_meta/1/README')->status_is(200)->tx->res->json->{source};
  is scalar(grep { ($_->[1]{risk} // 0) == 9 } @{$source->{lines}}), 0,
    'file browser shows no unresolved (risk 9) lines once boilerplate is cleared';

  # With clearing disabled the same boilerplate stays unresolved
  my $off = Test::Mojo->new(Cavil => {%$config, snippet_fold => {%{$config->{snippet_fold}}, clear_threshold => 0}});
  ok keys %{$off->app->reports->dig_report(1)->{missed_files}}, 'stays unresolved when clearing is off';
};

# A snippet that appears in several files must fold/clear in EVERY file, like a real pattern match -
# the per-snippet-id dedup applies only to the unresolved backlog display, not to resolved results.
subtest 'fold applies to every file occurrence of a duplicated snippet' => sub {
  my $cavil_test = Cavil::Test->new(online => $ENV{TEST_ONLINE}, schema => 'snippet_dup_test');
  my $config     = {
    %{$cavil_test->default_config},
    snippet_fold => {enabled => 1, threshold => 0.9, min_margin => 0.1, max_risk => 9, clear_threshold => 0}
  };
  my $t   = Test::Mojo->new(Cavil => $config);
  my $app = $t->app;
  $cavil_test->package_with_snippets_fixtures($app);
  $app->minion->enqueue(unpack => [1]);
  $app->minion->perform_jobs;
  my $db = $app->pg->db;

  # Attach an existing snippet to a second file, on disk and in the database
  my $fs       = $db->query('SELECT snippet, sline, eline FROM file_snippets ORDER BY id LIMIT 1')->hash;
  my $unpacked = $cavil_test->checkout_dir->child('package-with-snippets', '2a0737e27a3b75590e7fab112b06a76fe7573615',
    '.unpacked');
  $unpacked->child('README')->copy_to($unpacked->child('README2'));
  my $fid2
    = $db->insert('matched_files', {package => 1, filename => 'README2', mimetype => 'text/plain'}, {returning => 'id'})
    ->hash->{id};
  $db->insert('file_snippets',
    {package => 1, file => $fid2, snippet => $fs->{snippet}, sline => $fs->{sline}, eline => $fs->{eline}});

  # Fold that snippet to a synthetic license; it must fold in BOTH files, not just the first
  my $p = $app->patterns->create(pattern => 'a unique duplicated foldable marker', license => 'Dup-Test');
  $db->query(
    'UPDATE snippets SET license = TRUE, classified = TRUE, likelyness = 0.99, second_match = 0, score_version = ?,
       like_pattern = ? WHERE id = ?', SNIPPET_SCORE_VERSION, $p->{id}, $fs->{snippet}
  );

  is scalar(keys %{$app->reports->dig_report(1)->{folded}}), 2, 'the duplicated snippet folds in both files';
};

done_testing;
