# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Mojo::Base -strict, -signatures;

use FindBin;
use lib "$FindBin::Bin/lib";

use Test::More;
use Test::Mojo;
use Cavil::Test;
use Mojo::File qw(tempfile);
use Mojo::JSON qw(to_json);

plan skip_all => 'set TEST_ONLINE to enable this test' unless $ENV{TEST_ONLINE};

# A reindex used to start by deleting the report it was about to replace, which put everybody reading it in
# front of a progress bar for as long as the rebuild took. Now the new report is built beside the live one
# under a generation of its own and only swapped in at the very end, so the report a reviewer is reading
# never goes away. These tests drive the real job pipeline one job at a time and check that.
my $cavil_test = Cavil::Test->new(online => $ENV{TEST_ONLINE}, schema => 'transactional_reindex_test');
my $config     = $cavil_test->default_config;
my $t          = Test::Mojo->new(Cavil => $config);
my $app        = $t->app;
$cavil_test->mojo_fixtures($app);

my $minion = $app->minion;
my $pkgs   = $app->packages;
my $db     = $app->pg->db;

$minion->enqueue(unpack => [1]);
$minion->perform_jobs;
ok $pkgs->find(1)->{indexed}, 'package is indexed';

my $snippet_id = $db->query('SELECT snippet FROM file_snippets WHERE package = 1 ORDER BY snippet LIMIT 1')->array->[0];
ok $snippet_id, 'package has a snippet to decide on';

$t->get_ok('/login')->status_is(302);

# Run the queue one job at a time, calling back after each so the report can be inspected mid-rebuild
sub step_jobs ($check) {
  my $worker = $minion->worker->register;
  my $steps  = 0;
  while (my $job = $worker->dequeue(0)) {
    my $task = $job->task;
    my $err  = $job->execute;

    # Once before the job is marked finished, because that is a moment a reviewer's poll really can land
    # in: a task that has done its work but is still active, like the analyze job wrapping up after it
    # promoted the new report
    $check->($task) unless $err;

    $err ? $job->fail($err) : $job->finish;
    is $err, undef, "job $task was successful";
    $steps++;
    $check->($task);
  }
  $worker->unregister;
  return $steps;
}

sub report_details () {
  $t->get_ok('/reviews/report_details/1');
  return $t->tx->res->json;
}

subtest 'A settled report reports no rebuild' => sub {
  my $data = report_details();
  is $t->tx->res->code,      200,               'report is served';
  is $data->{error},         undef,             'no error';
  is $data->{reindexing},    Mojo::JSON->false, 'not reindexing';
  is $data->{rebuild_stage}, undef,             'no rebuild stage';
  ok $data->{checksum}, 'report checksum is exposed for the state poll';

  $t->get_ok('/reviews/report_state/1')
    ->status_is(200)
    ->json_is('/reindexing'    => Mojo::JSON->false)
    ->json_is('/rebuild_stage' => undef)
    ->json_is('/checksum'      => $data->{checksum});
};

subtest 'The report stays readable for the whole rebuild, then swaps' => sub {
  my $before = report_details();
  my @risks  = sort keys %{$before->{risks}};
  ok @risks, 'the live report has licenses to lose';

  is $pkgs->reindex(1), 'now', 'reindex enqueued';

  # Queued but not started: the report is untouched and already flagged as being rebuilt
  my $queued = report_details();
  is $t->tx->res->code, 200, 'report is still served while the reindex waits for a worker';
  is_deeply [sort keys %{$queued->{risks}}], \@risks, 'same licenses as before';
  is $queued->{reindexing},    Mojo::JSON->true, 'flagged as reindexing';
  is $queued->{rebuild_stage}, 1,                'waiting in the queue';

  my @stages;
  my $steps = step_jobs(
    sub ($task) {
      my $data = report_details();
      is $t->tx->res->code, 200, "report is still served after $task";
      ok !$data->{error}, "no error after $task";
      push @stages, $data->{rebuild_stage} if $data->{reindexing};

      # Nothing partial ever becomes visible: until the promote it is the old report, verbatim
      is_deeply [sort keys %{$data->{risks}}], \@risks, "same licenses after $task" if $data->{reindexing};
    }
  );
  ok $steps > 2, 'the rebuild really was several jobs';

  # The stages the reviewer saw are the ones the build actually went through, in order and without
  # ever dropping back to "queued"
  ok @stages, 'the rebuild was observed in progress';
  is_deeply [@stages], [sort { $a <=> $b } @stages], 'stages only ever advance';
  ok((grep { $_ == 3 } @stages), 'indexing was reported');
  ok((grep { $_ == 4 } @stages), 'analyzing was reported');
  is $stages[-1], 4, 'and is the last thing seen before the new report';

  my $after = report_details();
  is $after->{reindexing},    Mojo::JSON->false, 'settled again';
  is $after->{rebuild_stage}, undef,             'no rebuild stage left';
  is_deeply [sort keys %{$after->{risks}}], \@risks, 'the fresh report has the same licenses';

  my $pkg = $pkgs->find(1);
  is $pkg->{processing_job},    undef, 'no claim left on the package';
  is $pkg->{index_stage},       undef, 'no rebuild stage left on the package';
  is $pkg->{reindex_requested}, undef, 'no reindex request left over';
};

subtest 'The promote never leaves the report row empty' => sub {
  my $row = $db->select('bot_reports', '*', {package => 1})->hash;
  ok $row,                    'report row exists';
  ok $row->{ldig_report},     'dig report is cached';
  ok $row->{specfile_report}, 'spec file report is cached';
};

subtest 'Every reader stays on the live report while a build has rows beside it' => sub {

  # A build in progress duplicates the package: every row it writes carries its own generation and is a
  # rival of the live row for the same file, url, component. Any reader that forgets to say
  # "generation = 0" therefore does not just show something extra, it shows the package twice. To make
  # that unmissable, this build consists entirely of rows nothing else in the fixtures mentions.
  my $marker     = 'shadowbuild';
  my $generation = 777;
  my $pattern    = $app->patterns->create(
    license => 'Shadowbuild-1.0',
    pattern => 'This is shadowbuild license text that only a build in progress knows about',
    risk    => 7,
    patent  => 1
  );
  my $flags_before = $pkgs->flags(1);
  my $file         = $db->insert(
    'matched_files',
    {package   => 1, filename => "$marker/BUILD-ONLY.txt", mimetype => 'text/plain', generation => $generation},
    {returning => 'id'}
  )->hash->{id};
  $db->insert('pattern_matches',
    {package => 1, file => $file, pattern => $pattern->{id}, sline => 1, eline => 1, generation => $generation});
  $db->insert('file_snippets',
    {package => 1, file => $file, snippet => $snippet_id, sline => 1, eline => 1, generation => $generation});
  $db->insert('urls',   {package => 1, url   => "https://$marker.example.com/", hits => 3, generation => $generation});
  $db->insert('emails', {package => 1, email => "$marker\@example.com",         hits => 2, generation => $generation});
  $db->insert(
    'package_components',
    {
      package    => 1,
      purl       => "pkg:npm/$marker\@1.0.0",
      type       => 'npm',
      name       => $marker,
      version    => '1.0.0',
      complete   => 1,
      generation => $generation
    }
  );

  # Each reader is handed something it would have to invent from the build to get wrong, and answers with
  # the number of times the build leaked into it
  my sub leaks ($data) { return scalar(() = to_json($data) =~ /$marker/gi) }

  # Guard against the checks below passing because the build was never there in the first place
  ok leaks($app->reports->dig_report(1, undef, $generation)) > 0, 'the build is visible under its own generation';

  my @readers = (
    ['dig report'          => sub { leaks($app->reports->dig_report(1)) }],
    ['cached dig report'   => sub { leaks($app->reports->sanitized_dig_report(1)) }],
    ['report summary'      => sub { leaks($app->reports->summary(1)) }],
    ['report page payload' => sub { leaks(report_details()) }],
    ['file list'           => sub { leaks($pkgs->matched_files(1)) }],
    ['ignore glob preview' => sub { $pkgs->glob_matches_report_files(1, "$marker/*") }],
    ['component lookup'    => sub { leaks($pkgs->matching_components([1], $marker)) }],
    [
      'component search' => sub {
        $pkgs->paginate_review_search(undef,
          {component => $marker, search => '', not_obsolete => 'false', limit => 10, offset => 0})->{total};
      }
    ],
    [
      'component export' => sub {
        my @rows;
        $pkgs->export_components(sub { push @rows, shift });
        leaks(\@rows);
      }
    ],
    ['snippet search' => sub { leaks($app->snippets->snippet_search({package_id => 1, resolution => 'any'})) }],
    [
      'SPDX document' => sub {
        my $tmp = tempfile;
        $app->spdx->generate_to_file(1, "$tmp");
        return scalar(() = $tmp->slurp =~ /$marker/gi);
      }
    ]
  );
  for my $reader (@readers) {
    my ($name, $cb) = @$reader;
    is $cb->(), 0, "$name is not confused by the build";
  }

  # Pattern flags are aggregated over every match of the package, and the build's pattern is flagged
  is_deeply $pkgs->flags(1), $flags_before, 'package flags are not confused by the build';

  is $pkgs->discard_builds(1, undef), 4, 'the build is thrown away again';
  is $db->query('SELECT COUNT(*) FROM pattern_matches WHERE package = 1 AND generation <> 0')->array->[0], 0,
    'matches cascaded with it';
  is $db->query('SELECT COUNT(*) FROM file_snippets WHERE package = 1 AND generation <> 0')->array->[0], 0,
    'snippets cascaded with it';
};

subtest 'The cached reports are only ever replaced, never emptied' => sub {
  my sub cached ($column) { return $db->select('bot_reports', $column, {package => 1})->hash->{$column} }

  # A spec file report that could only have come from the previous sources, so it is obvious which of the
  # two paths below refreshed it
  my $stale = to_json({main => {license => 'Cached-From-The-Previous-Sources'}});
  $db->update('bot_reports', {specfile_report => $stale}, {package => 1});

  # A plain re-analyze - an approved snippet, a newly ignored line - used to begin by nulling the cached
  # dig report, which took the report page down for as long as it ran
  $pkgs->analyze(1);
  step_jobs(sub ($task) { ok cached('ldig_report'), "the dig report is still cached after $task" });
  is cached('specfile_report'), $stale, 'a re-analyze has no new sources and keeps the cached spec file report';

  # A rebuild can follow a re-unpack, which replaces the sources and with them the spec file
  is $pkgs->reindex(1), 'now', 'reindex enqueued';
  step_jobs(sub ($task) { ok cached('ldig_report'), "the dig report is still cached after $task" });
  isnt cached('specfile_report'), $stale, 'a rebuild replaced the spec file report';
  is_deeply $app->reports->specfile_report(1), $app->reports->build_specfile_report(1),
    'with one built from the sources it just indexed';
};

subtest 'A rebuild puts the report page into read-only mode' => sub {
  is $pkgs->reindex(1), 'now', 'reindex enqueued';
  $t->get_ok('/reviews/report_state/1')->status_is(200)->json_is('/reindexing' => Mojo::JSON->true);

  # Decisions staged against this report were made when it still marked what the reviewer had covered,
  # so the whole batch is refused rather than applied against a report that is about to be replaced
  $t->post_ok(
    '/snippet/batch_decision' => json => {
      report  => 1,
      actions => [
        {
          kind      => 'create-pattern',
          snippetId => $snippet_id,
          formData  => {license => 'MIT', pattern => 'Some text', risk => 5}
        }
      ]
    }
    )
    ->status_is(409)
    ->json_is('/ok'         => Mojo::JSON->false)
    ->json_is('/reindexing' => Mojo::JSON->true)
    ->json_like('/error' => qr/being rebuilt/);

  # A batch from a page that is not showing this report (the Change Proposals queue) is not gated
  $t->post_ok('/snippet/batch_decision' => json => {actions => [{kind => 'nonsense', formData => {}}]})
    ->status_is(400)
    ->json_like('/results/0/error' => qr/Unknown action kind/);

  $minion->perform_jobs;
  $t->get_ok('/reviews/report_state/1')->status_is(200)->json_is('/reindexing' => Mojo::JSON->false);

  $t->post_ok(
    '/snippet/batch_decision' => json => {
      report  => 1,
      actions => [
        {
          kind      => 'create-pattern',
          snippetId => $snippet_id,
          formData  => {license => 'MIT', pattern => 'Some text', risk => 5}
        }
      ]
    }
  )->status_is(200)->json_is('/ok' => Mojo::JSON->true);
  $minion->perform_jobs;
};

subtest 'Generating an SPDX report does not lock the page' => sub {
  $minion->enqueue('spdx_report' => [1] => {notes => {pkg_1 => 1}});
  $t->get_ok('/reviews/report_state/1')->status_is(200)->json_is('/reindexing' => Mojo::JSON->false);
  $minion->perform_jobs;
};

subtest 'A reindex requested while an SPDX report runs starts as soon as it is over' => sub {
  my $before = report_details();
  ok !$before->{error}, 'report is readable to begin with';

  # An spdx job claims the package for as long as it takes, and one follows every single build when SPDX
  # reports are generated automatically - so a reviewer pressing "Reindex" lands in that window fairly
  # easily. Nothing is queued behind it that could notice the request, which is what makes the job itself
  # responsible for it: otherwise the reviewer stares at a read-only report until the nightly sweep.
  my $spdx_id = $minion->enqueue('spdx_report' => [1] => {notes => {pkg_1 => 1}});
  ok $pkgs->claim(1, $spdx_id), 'the spdx job has the package';
  is $pkgs->reindex(1), 'later', 'the reindex has to wait for it';
  $t->get_ok('/reviews/report_state/1')->status_is(200)->json_is('/reindexing' => Mojo::JSON->true);

  my $worker = $minion->worker->register;
  my $job    = $worker->dequeue(0, {id => $spdx_id});
  my $err    = $job->execute;
  $err ? $job->fail($err) : $job->finish;
  is $err, undef, 'spdx job was successful';
  $worker->unregister;

  my $pkg = $pkgs->find(1);
  is $pkg->{processing_job},    undef, 'the package is free again';
  is $pkg->{reindex_requested}, undef, 'and no longer owes a rebuild';
  ok $minion->jobs({tasks => ['index'], states => ['inactive'], notes => ['pkg_1']})->total,
    'because the rebuild is queued already, with no sweep involved';

  $minion->perform_jobs;
  my $after = report_details();
  is $t->tx->res->code, 200, 'report is still served';
  is_deeply [sort keys %{$after->{risks}}], [sort keys %{$before->{risks}}], 'and was rebuilt with the same licenses';
  is $after->{reindexing}, Mojo::JSON->false, 'with nothing left in flight';
};

subtest 'An index job that loses the race for the package does not lose the rebuild' => sub {
  my $before = report_details();
  ok !$before->{error}, 'report is readable to begin with';

  # A reindex checks that the package is free before it enqueues anything, but the owner can change
  # between that check and the job actually running - the analyzed job of the build that just promoted, an
  # spdx report being generated. The index job writes nothing at all when that happens, so there are no
  # stranded rows for the sweep to find it by, and the rebuild is gone unless it is written down.
  ok $pkgs->claim(1, 999999), 'somebody else took the package first';
  my $id = $pkgs->index(1);
  $minion->perform_jobs;
  like $minion->job($id)->info->{result}, qr/remembered the reindex for later/, 'the index job stood down';

  is $db->query('SELECT COUNT(*) FROM matched_files WHERE package = 1 AND generation <> 0')->array->[0], 0,
    'it left no rows behind to be recognised by';
  is $pkgs->find(1)->{processing_job}, 999999, 'the other job still owns the package';
  is $pkgs->reindex_requested(1),      1,      'but the rebuild it owes is on the record';

  # Nothing followed it that could pick the request up, so the sweep is what runs it in the end
  $pkgs->release(1, 999999);
  $minion->enqueue('cleanup');
  $minion->perform_jobs;

  is $pkgs->find(1)->{reindex_requested}, undef, 'the request is settled';
  my $after = report_details();
  is $t->tx->res->code, 200, 'report is still served';
  is_deeply [sort keys %{$after->{risks}}], [sort keys %{$before->{risks}}], 'and was rebuilt with the same licenses';
  is $after->{reindexing}, Mojo::JSON->false, 'with nothing left in flight';
};

subtest 'An abandoned rebuild is swept up and retried' => sub {
  my $before = report_details();
  ok !$before->{error}, 'report is readable to begin with';

  # A worker that died mid-rebuild: rows under a generation, the package still claimed by the build, the
  # job gone from the queue, and nothing that will ever finish it
  my $generation = 424242;
  $db->query('INSERT INTO matched_files (package, filename, mimetype, generation) VALUES (1, ?, ?, ?)',
    'abandoned/rebuild.txt', 'text/plain', $generation);
  $db->update('bot_packages', {processing_job => $generation, index_stage => 'indexing'}, {id => 1});

  # The reviewer is not left in the dark while it sits there
  my $stuck = report_details();
  is $t->tx->res->code,       200,              'report is still served';
  is $stuck->{reindexing},    Mojo::JSON->true, 'still flagged as reindexing';
  is $stuck->{rebuild_stage}, 3,                'stuck at indexing';
  is_deeply [sort keys %{$stuck->{risks}}], [sort keys %{$before->{risks}}], 'the live report is untouched';

  is_deeply $pkgs->unsettled_builds, [1], 'the sweep can see it';
  $minion->enqueue('cleanup');
  $minion->perform_jobs;

  is $db->query('SELECT COUNT(*) FROM matched_files WHERE package = 1 AND generation <> 0')->array->[0], 0,
    'abandoned rows are gone';

  my $pkg = $pkgs->find(1);
  is $pkg->{processing_job}, undef, 'package is no longer claimed by the dead build';
  is $pkg->{index_stage},    undef, 'stage is cleared';

  my $after = report_details();
  is $t->tx->res->code, 200, 'report survived the sweep';
  is_deeply [sort keys %{$after->{risks}}], [sort keys %{$before->{risks}}], 'with the same licenses';
  is $after->{reindexing}, Mojo::JSON->false, 'settled once the requeued reindex is done';
};

subtest 'An analyze for a build that is gone does not promote anything' => sub {
  my $before = report_details();
  ok !$before->{error}, 'report is readable to begin with';
  my $files = $db->query('SELECT COUNT(*) FROM matched_files WHERE package = 1')->array->[0];
  ok $files, 'the live report has files';

  # The sweep discarded this build (or it was promoted already and Minion is retrying the job). Promoting
  # now would delete the live report and put nothing in its place.
  my $id = $minion->enqueue(analyze => [1, 424242] => {notes => {pkg_1 => 1}});
  $minion->perform_jobs;
  like $minion->job($id)->info->{result}, qr/nothing to promote/, 'the promote was declined';

  is $db->query('SELECT COUNT(*) FROM matched_files WHERE package = 1')->array->[0], $files, 'no files were lost';
  my $after = report_details();
  is $t->tx->res->code, 200, 'report is still served';
  is_deeply [sort keys %{$after->{risks}}], [sort keys %{$before->{risks}}], 'the live report is untouched';
};

subtest 'A failed unpack leaves a stage behind that the sweep clears' => sub {
  $db->update('bot_packages', {index_stage => 'unpacking'}, {id => 1});
  is_deeply $pkgs->unsettled_builds, [1], 'a stranded stage counts as unsettled';

  my $data = report_details();
  is $t->tx->res->code,      200, 'report is still served';
  is $data->{rebuild_stage}, 2,   'reported as unpacking';

  $minion->enqueue('cleanup');
  $minion->perform_jobs;
  is $pkgs->find(1)->{index_stage}, undef, 'stage is cleared';
  is_deeply $pkgs->unsettled_builds, [], 'nothing unsettled left';
};

subtest 'A build stranded by a dead worker is recovered by retrying its job' => sub {
  my $before = report_details();
  ok !$before->{error}, 'report is readable to begin with';

  ok my $id = $pkgs->index(1), 'reindex enqueued';
  my $worker = $minion->worker->register;
  ok my $job = $worker->dequeue(0, {id => $id}), 'index job dequeued';

  # What Minion's repair leaves behind when a worker disappears mid-build: the job is failed, and the
  # claim it took on the package is standing with nobody left to hand it back
  ok $pkgs->claim(1, $id),           'the build claimed the package';
  ok $job->fail('Worker went away'), 'the worker went away';
  $worker->unregister;
  is $pkgs->find(1)->{processing_job}, $id, 'the package is still claimed by the dead build';

  # Retrying the failed job is what an admin does in the Minion admin UI, and it is all that is needed:
  # the claim the build finds in its way is its own
  ok $minion->job($id)->retry, 'index job retried';
  $minion->perform_jobs;
  unlike $minion->job($id)->info->{result}, qr/already being processed/, 'the retry took the package back';

  my $after = report_details();
  is $t->tx->res->code,    200,               'the rebuild finished and its report is served';
  is $after->{reindexing}, Mojo::JSON->false, 'with nothing left in flight';
  is_deeply [sort keys %{$after->{risks}}], [sort keys %{$before->{risks}}], 'and the same licenses';
  is $pkgs->find(1)->{processing_job}, undef, 'the package has been handed back';
};

subtest 'A failure after the promote still belongs to the package' => sub {
  is $pkgs->reindex(1), 'now', 'reindex enqueued';

  # By the time the analyze job reaches its follow-up work the promote has committed and the job has
  # stopped counting as a rebuild of this package, so that the progress bar does not drop back to "queued"
  # right before the new report lands. A failure in that tail is still the package's failure though.
  my $failed = do {
    no warnings qw(once redefine);
    local *Cavil::Model::Packages::classify = sub { die "classifier exploded\n" };
    $minion->perform_jobs;
    $minion->jobs({tasks => ['analyze'], states => ['failed'], notes => ['pkg_1']})->total;
  };
  is $failed, 1, 'the failed analyze is counted against the package';

  # And what it promoted before failing is the live report, in one piece. The package was handed back by
  # the promote itself, so a failure afterwards cannot leave it claimed by a job that will never return.
  my $data = report_details();
  is $t->tx->res->code,   200,               'the promoted report is served';
  is $data->{reindexing}, Mojo::JSON->false, 'with the rebuild over';
  ok !$data->{error}, 'and no error';
  is $pkgs->find(1)->{processing_job}, undef, 'and the package free despite the failure';
};

done_testing;
