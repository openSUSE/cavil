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
    $report_app->snippets->resolve_snippets(1);    # refresh the stored resolution the report now reads
    return $report_app->reports->dig_report(1)->{folded} ? 1 : 0;
  };

  ok $folds->($app), 'confident, current-version, low-risk legal snippet folds';
  my $report = $app->reports->dig_report(1);
  ok $report->{licenses}{'GPL'}, 'the folded license appears in the report';

  # A fully-folded file is resolved, so the report does NOT auto-expand it inline - only files with
  # unresolved matches are expanded. It is still listed under its inferred license and opened on demand.
  my ($folded_file) = keys %{$report->{folded}};
  ok $folded_file,                       'a file folded its snippet';
  ok !$report->{expanded}{$folded_file}, 'a fully-folded file is not auto-expanded in the report';
  ok !$report->{lines}{$folded_file},    'and its source is not pre-rendered inline';

  # Opened on demand (the report file link / file browser both use the per-file path), the folded region
  # renders highlighted as its inferred license, carrying the snippet handle + "folded" marker for
  # inline correction - not shown as an unresolved snippet.
  my $opened             = $app->reports->dig_report(1, $folded_file);
  my $highlighted_as_gpl = grep { ($_->[1]{name} // '') eq 'GPL' } @{$opened->{lines}{$folded_file} // []};
  ok $highlighted_as_gpl, 'the folded region is highlighted as GPL when the file is opened';
  my ($folded_line) = grep { $_->[1]{folded} } @{$opened->{lines}{$folded_file} // []};
  ok $folded_line,                    'folded line is tagged as a derived (folded) resolution';
  ok $folded_line->[1]{snippet},      'folded line carries the originating snippet id for correction';
  ok defined $folded_line->[1]{hash}, 'folded line carries the snippet hash';

  # The file browser marks and exposes the same handle (the primary correction surface)
  $t->get_ok('/login')->status_is(302);
  my $fb = $t->get_ok('/reviews/file_view_meta/1/README')->status_is(200)->tx->res->json->{source};
  my ($fb_folded) = grep { $_->[1]{folded} } @{$fb->{lines}};
  ok $fb_folded,                                                'file browser marks the folded region';
  ok $fb_folded->[1]{snippet} && defined $fb_folded->[1]{hash}, 'file browser folded line carries the snippet handle';

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
  $strict->app->snippets->resolve_snippets(1);
  ok !$strict->app->reports->dig_report(1)->{folded}, 'does not fold a license above max_risk';

  # And nothing folds at all when the feature is disabled
  my $off = Test::Mojo->new(Cavil => $cavil_test->default_config);
  $off->app->snippets->resolve_snippets(1);
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
  $app->snippets->resolve_snippets(1);

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

  # Cleared regions stay findable + editable in the file browser (reviewers review negatives there):
  # tagged "cleared" and carrying the snippet handle for correction.
  my ($cleared_line) = grep { $_->[1]{cleared} } @{$source->{lines}};
  ok $cleared_line, 'file browser marks the cleared region';
  ok $cleared_line->[1]{snippet} && defined $cleared_line->[1]{hash},
    'cleared line carries the snippet handle for review';

  # With clearing disabled the same boilerplate stays unresolved
  my $off = Test::Mojo->new(Cavil => {%$config, snippet_fold => {%{$config->{snippet_fold}}, clear_threshold => 0}});
  $off->app->snippets->resolve_snippets(1);
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
  $app->snippets->resolve_snippets(1);

  is scalar(keys %{$app->reports->dig_report(1)->{folded}}), 2, 'the duplicated snippet folds in both files';
};

# The correction loop: resolve_snippets honors ignored lines, so a reviewer's ignore decision drops the
# stored 'fold' resolution on the next resolve (which a correction triggers via reindex). This proves the
# end-to-end behaviour the inline correction relies on, with no dedicated un-fold logic.
subtest 'correcting a fold removes it (resolve honors ignores)' => sub {
  my $cavil_test = Cavil::Test->new(online => $ENV{TEST_ONLINE}, schema => 'snippet_unfold_test');
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

  my $gpl = $db->query("SELECT id FROM license_patterns WHERE license = 'GPL' LIMIT 1")->hash;
  $db->query(
    'UPDATE snippets SET license = TRUE, classified = TRUE, likelyness = 0.99, second_match = 0,
       score_version = ?, like_pattern = ?', SNIPPET_SCORE_VERSION, $gpl->{id}
  );
  $app->snippets->resolve_snippets(1);
  ok $app->reports->dig_report(1)->{folded}, 'snippet folds before correction';

  # The reviewer opens the folded region and ignores it (the editor's "create ignore" action). In
  # production this reindexes the package, which re-resolves; here we resolve directly to mirror that.
  my $pkg   = $db->select('bot_packages', 'name', {id => 1})->hash->{name};
  my $snips = $db->query(
    'SELECT DISTINCT s.hash FROM snippets s JOIN file_snippets fs ON fs.snippet = s.id WHERE fs.package = 1')->hashes;
  $app->packages->ignore_line({hash => $_->{hash}, package => $pkg, owner => undef, contributor => undef}) for @$snips;
  $app->snippets->resolve_snippets(1);

  ok !$app->reports->dig_report(1)->{folded}, 'the fold is gone once the snippets are ignored';
};

# Overlap-clear: a snippet whose region already contains a real licensed match is redundant noise -
# the match reports the license, so the snippet is cleared even though similarity can't touch it.
subtest 'overlap-clear (snippet region already contains a real license match)' => sub {
  my $cavil_test = Cavil::Test->new(online => $ENV{TEST_ONLINE}, schema => 'snippet_overlap_test');
  my $config     = {
    %{$cavil_test->default_config},
    snippet_fold => {
      enabled         => 1,
      threshold       => 0.95,
      min_margin      => 0.15,
      max_risk        => 5,
      clear_threshold => 0,
      overlap_clear   => 1,
      overlap_guard   => 0.9
    }
  };
  my $t   = Test::Mojo->new(Cavil => $config);
  my $app = $t->app;
  $cavil_test->package_with_snippets_fixtures($app);
  $app->minion->enqueue(unpack => [1]);
  $app->minion->perform_jobs;
  my $db = $app->pg->db;

  # Every snippet is classifier-legal but unscored, so similarity fold/clear can never touch it
  $db->query(
    'UPDATE snippets SET license = TRUE, classified = TRUE, likelyness = 0, second_match = 0,
       like_pattern = NULL, score_version = 0'
  );

  # A real licensed match on the first line of each snippet (the SPDX-line-swallowed-by-expansion case).
  # Use a synthetic license that cannot appear from anywhere else in the package, so its presence proves
  # the *overlapping match itself* still reports - clearing the snippet must not suppress the very match
  # the clear relies on. A fixture license like GPL would be satisfied by unrelated matches and hide that.
  my $overlap
    = $app->patterns->create(pattern => 'a unique overlap-only license marker phrase', license => 'Overlap-Only');
  my @overlap_files;
  for my $fs ($db->query('SELECT file, sline FROM file_snippets WHERE package = 1')->hashes->each) {
    push @overlap_files, $fs->{file};
    $db->insert(
      'pattern_matches',
      {
        package => 1,
        file    => $fs->{file},
        pattern => $overlap->{id},
        sline   => $fs->{sline},
        eline   => $fs->{sline},
        ignored => 0
      }
    );
  }
  $app->snippets->resolve_snippets(1);

  my $report = $app->reports->dig_report(1);
  is_deeply $report->{missed_files}, {}, 'snippets overlapping a real license match are cleared';
  ok $report->{cleared}, 'the file is tagged as cleared';
  ok $report->{licenses}{'Overlap-Only'},
    'the overlapping match still reports its license (not suppressed by the clear)';
  ok !$report->{folded}, 'overlap-clear asserts no new license (not a fold)';

  # ...and the source view of a cleared file still highlights the overlapping match as its license.
  my $file_report = $app->reports->dig_report(1, $overlap_files[0]);
  my $highlighted = grep { ($_->[1]{name} // '') eq 'Overlap-Only' } @{$file_report->{lines}{$overlap_files[0]} // []};
  ok $highlighted, 'the overlapping match is still highlighted in the cleared file source view';

  # Guard: a snippet that itself strongly resembles a DIFFERENT license is kept for review
  my $other = $app->patterns->create(pattern => 'a distinct overlap guard marker text', license => 'Other-Test');
  my $one   = $db->query('SELECT id FROM snippets LIMIT 1')->hash->{id};
  $db->query(
    'UPDATE snippets SET like_pattern = ?, likelyness = 0.92, second_match = 0.92, score_version = ? WHERE id = ?',
    $other->{id}, SNIPPET_SCORE_VERSION, $one);
  $app->snippets->resolve_snippets(1);
  ok keys %{$app->reports->dig_report(1)->{missed_files}},
    'a snippet resembling a different license is kept despite the overlap';

  # Disabled -> nothing overlap-clears
  my $off = Test::Mojo->new(Cavil => {%$config, snippet_fold => {%{$config->{snippet_fold}}, overlap_clear => 0}});
  $off->app->snippets->resolve_snippets(1);
  ok keys %{$off->app->reports->dig_report(1)->{missed_files}}, 'nothing overlap-clears when the toggle is off';
};

# Overlapping highlights on the same line must never lower the line's risk: a lower-risk real match or a
# lower-risk fold may not overwrite a higher-risk highlight (it would make the source view explain the
# wrong, less severe thing). Both the match and the fold registration paths share this guard.
subtest 'overlapping highlights never lower a line risk' => sub {
  my $cavil_test = Cavil::Test->new(online => $ENV{TEST_ONLINE}, schema => 'report_risk_guard_test');
  my $t          = Test::Mojo->new(Cavil => $cavil_test->default_config);
  my $app        = $t->app;
  $cavil_test->package_with_snippets_fixtures($app);
  $app->minion->enqueue(unpack => [1]);
  $app->minion->perform_jobs;
  my $db = $app->pg->db;

  # Reuse a real unpacked file (so the source lines exist on disk) under fresh matched_files rows that
  # carry only the matches/snippet we set up, keeping each scenario isolated via dig_report's file view.
  my $filename
    = $db->query('SELECT filename FROM matched_files WHERE package = 1 ORDER BY id LIMIT 1')->hash->{filename};
  my $hi
    = $app->patterns->create(pattern => 'a unique high risk license marker phrase', license => 'HiRisk', risk => 9);
  my $lo = $app->patterns->create(pattern => 'a unique low risk license marker phrase', license => 'LoRisk', risk => 2);
  my $fresh_file = sub {
    $db->insert('matched_files', {package => 1, filename => $filename, mimetype => 'text/plain'}, {returning => 'id'})
      ->hash->{id};
  };
  my $line1 = sub ($fid) {
    (grep { $_->[0] == 1 } @{$app->reports->dig_report(1, $fid)->{lines}{$fid}})[0][1];
  };

  subtest 'a lower-risk match does not overwrite a higher-risk match' => sub {
    my $file = $fresh_file->();

    # Higher-risk match registered first (lower id), lower-risk match second - without the guard the
    # later, lower-risk match would win.
    $db->insert('pattern_matches',
      {package => 1, file => $file, pattern => $hi->{id}, sline => 1, eline => 1, ignored => 0});
    $db->insert('pattern_matches',
      {package => 1, file => $file, pattern => $lo->{id}, sline => 1, eline => 1, ignored => 0});

    my $info = $line1->($file);
    is $info->{risk}, 9,        'the line keeps the higher risk';
    is $info->{name}, 'HiRisk', 'and explains the higher-risk license';
  };

  subtest 'a lower-risk fold does not overwrite a higher-risk match' => sub {
    my $file = $fresh_file->();
    $db->insert('pattern_matches',
      {package => 1, file => $file, pattern => $hi->{id}, sline => 1, eline => 1, ignored => 0});

    my $sid = $db->insert(
      'snippets',
      {
        hash          => 'risk-guard-fold',
        text          => 'folded body',
        package       => 1,
        classified    => 1,
        license       => 1,
        approved      => 0,
        confidence    => 100,
        likelyness    => 0.99,
        second_match  => 0,
        score_version => SNIPPET_SCORE_VERSION,
        like_pattern  => $lo->{id}
      },
      {returning => 'id'}
    )->hash->{id};
    $db->insert('file_snippets',
      {package => 1, file => $file, snippet => $sid, sline => 1, eline => 1, resolution => 'fold'});

    my $info = $line1->($file);
    is $info->{risk}, 9, 'the line keeps the higher-risk match risk';
    ok !$info->{folded}, 'and is still explained by the match, not downgraded to the fold';
  };
};

# A folded snippet can swallow a line that is itself a real licensed match (e.g. the "Free Software
# Foundation" first line of a GCC GPL header). That line must render as its own curated match - at its
# real risk, not as the fold - in both the report source view and the file browser.
subtest 'a real match inside a folded region keeps its own highlight' => sub {
  my $cavil_test = Cavil::Test->new(online => $ENV{TEST_ONLINE}, schema => 'fold_over_match_test');
  my $t          = Test::Mojo->new(Cavil => $cavil_test->default_config);
  my $app        = $t->app;
  $cavil_test->package_with_snippets_fixtures($app);
  $app->minion->enqueue(unpack => [1]);
  $app->minion->perform_jobs;
  my $db = $app->pg->db;

  # Clean slate on README so only our scenario drives the rendering.
  my $f = $db->query("SELECT id FROM matched_files WHERE package = 1 AND filename = 'README'")->hash->{id};
  $db->query('DELETE FROM file_snippets WHERE file = ?',   $f);
  $db->query('DELETE FROM pattern_matches WHERE file = ?', $f);

  my $fsf
    = $app->patterns->create(pattern => 'a unique free software foundation marker', license => 'FSF-Test', risk => 0);
  my $gpl = $app->patterns->create(pattern => 'a unique folded gpl header marker', license => 'GPL-Test', risk => 6);

  # A real risk-0 match on line 1, and a fold spanning lines 1-3 that swallows it.
  $db->insert('pattern_matches',
    {package => 1, file => $f, pattern => $fsf->{id}, sline => 1, eline => 1, ignored => 0});
  my $sid = $db->insert(
    'snippets',
    {
      hash          => 'fold-over-match',
      text          => 'folded header body',
      package       => 1,
      classified    => 1,
      license       => 1,
      approved      => 0,
      confidence    => 100,
      likelyness    => 0.99,
      second_match  => 0,
      score_version => SNIPPET_SCORE_VERSION,
      like_pattern  => $gpl->{id}
    },
    {returning => 'id'}
  )->hash->{id};
  $db->insert('file_snippets',
    {package => 1, file => $f, snippet => $sid, sline => 1, eline => 3, resolution => 'fold'});

  my $line_of = sub ($lines, $n) {
    (grep { $_->[0] == $n } @$lines)[0][1];
  };

  subtest 'report source view' => sub {
    my $lines = $app->reports->dig_report(1, $f)->{lines}{$f};
    is $line_of->($lines,  1)->{name}, 'FSF-Test', 'the matched first line keeps its curated license';
    is $line_of->($lines,  1)->{risk}, 0,          'at its real risk';
    ok !$line_of->($lines, 1)->{folded}, 'and is not shown as folded';
    ok $line_of->($lines,  2)->{folded}, 'a non-matched line of the snippet still folds';
  };

  subtest 'file browser' => sub {
    $t->get_ok('/login')->status_is(302);
    my $src = $t->get_ok('/reviews/file_view_meta/1/README')->status_is(200)->tx->res->json->{source};
    is $line_of->($src->{lines},  1)->{name}, 'FSF-Test', 'the matched first line keeps its curated license';
    is $line_of->($src->{lines},  1)->{risk}, 0,          'at its real risk';
    ok !$line_of->($src->{lines}, 1)->{folded}, 'and is not shown as folded';
    ok $line_of->($src->{lines},  2)->{folded}, 'a non-matched line of the snippet still folds';
  };
};

done_testing;
