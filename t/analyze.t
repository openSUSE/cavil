# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Mojo::Base -strict;

use FindBin;
use lib "$FindBin::Bin/lib";

use Test::More;
use Test::Mojo;
use Cavil::Test;

plan skip_all => 'set TEST_ONLINE to enable this test' unless $ENV{TEST_ONLINE};

my $cavil_test = Cavil::Test->new(online => $ENV{TEST_ONLINE}, schema => 'analyze_test');
my $t          = Test::Mojo->new(Cavil => $cavil_test->default_config);
$cavil_test->mojo_fixtures($t->app);

subtest 'Analyze background job' => sub {
  $t->app->minion->enqueue(unpack => [1]);
  $t->app->minion->perform_jobs;

  my $pkg = $t->app->packages->find(1);
  $pkg->{reviewing_user}   = 1;
  $pkg->{result}           = 'Sure';
  $pkg->{state}            = 'acceptable';
  $pkg->{review_timestamp} = 1;
  $t->app->packages->update($pkg);

  $t->app->minion->enqueue(unpack => [2]);
  $t->app->minion->perform_jobs;

  my $res = $t->app->pg->db->select('bot_packages', '*', {id => 2})->hashes->[0];
  is $res->{result}, undef, 'result cleared';
  is $res->{notice}, "Diff to closest match 1\n\n  Declared license  Artistic-2.0 -> GPL-1.0-or-later\n",
    'different spec';
  is $res->{diff_report}, undef, 'no structured diff for a spec-only delta (no new unresolved matches)';
  is $res->{state},       'new', 'not approved';
};

subtest 'Analyze clears stale notice when reusing a previous accepted review' => sub {
  my $pkgs = $t->app->packages;
  my $db   = $t->app->pg->db;
  my $pkg1 = $pkgs->find(1);

  my $pkg3_id = $pkgs->add(
    name            => 'perl-Mojolicious',
    checkout_dir    => $pkg1->{checkout_dir},
    api_url         => 'https://api.opensuse.org',
    requesting_user => 1,
    project         => 'devel:languages:perl',
    package         => 'perl-Mojolicious',
    srcmd5          => $pkg1->{checkout_dir},
    priority        => 5
  );

  $db->query(
    'INSERT INTO bot_reports (package, ldig_report, declarations, rolemodel)
     SELECT ?, ldig_report, declarations, rolemodel FROM bot_reports WHERE package = ?', $pkg3_id, 1
  );
  $db->query(
    "UPDATE bot_packages SET indexed = NOW(), checksum = ?, notice = ?, diff_report = '{\"version\":1}' WHERE id = ?",
    $pkg1->{checksum}, 'stale notice', $pkg3_id);

  $t->app->minion->enqueue(analyzed => [$pkg3_id]);
  $t->app->minion->perform_jobs;

  my $res = $pkgs->find($pkg3_id);
  is $res->{state},       'acceptable', 'approved from previous review';
  is $res->{notice},      undef,        'stale notice cleared';
  is $res->{diff_report}, undef,        'stale structured diff cleared alongside the notice';
  is $res->{result},      'Accepted because previously reviewed under the same license (1)', 'reused previous review';
};

subtest 'Re-analyze refreshes notice on already-reviewed packages' => sub {
  my $pkgs = $t->app->packages;
  my $db   = $t->app->pg->db;

  # Mark package 2 as lawyer-reviewed with a stale notice from before the
  # package was approved, and a result the lawyer set manually.
  $db->query(
    "UPDATE bot_packages SET state = 'acceptable_by_lawyer', reviewing_user = 1, reviewed = NOW(),
     result = 'lawyer approved', notice = 'Found new unresolved matches in something' WHERE id = 2"
  );

  $t->app->minion->enqueue(analyzed => [2]);
  $t->app->minion->perform_jobs;

  my $res = $pkgs->find(2);
  is $res->{state},          'acceptable_by_lawyer', 'state preserved';
  is $res->{result},         'lawyer approved',      'result preserved';
  is $res->{reviewing_user}, 1,                      'reviewing user preserved';
  like $res->{notice}, qr/Diff to closest match \d+/, 'notice refreshed to current delta';
};

subtest 'Prevent analyze race condition' => sub {
  my $minion = $t->app->minion;
  ok my $job_id = $minion->enqueue('analyze', [1]);
  ok my $guard  = $t->app->packages->claim_guard(1, 999999), 'package claimed by another job';
  my $worker = $minion->worker->register;
  ok my $job = $worker->dequeue(0, {id => $job_id}), 'job dequeued';
  is $job->execute, undef, 'no error';
  like $minion->job($job_id)->info->{result}, qr/Package \d+ is already being processed/, 'race condition prevented';
  $worker->unregister;
  undef $guard;
  is $t->app->packages->find(1)->{processing_job}, undef, 'package no longer claimed';
};

subtest 'dig_report tolerates pattern_matches in files covered by an ignored_files glob' => sub {
  my $app = $t->app;
  my $db  = $app->pg->db;

  my $filename = $db->query(
    'SELECT mf.filename FROM matched_files mf
       JOIN pattern_matches pm ON pm.file = mf.id
      WHERE pm.package = 1 AND pm.ignored = false
      LIMIT 1'
  )->hash->{filename};
  ok $filename, "file with unignored pattern_match available ($filename)";

  $app->ignored_files->add($filename, 'test_bot');
  is $db->select('ignored_lines')->rows, 0, 'no ignored_lines row backs the glob';

  my $report = eval { $app->reports->dig_report(1) };
  ok !$@,     'dig_report does not raise an FK violation' or diag $@;
  ok $report, 'got a report';

  my $still_unignored = $db->query(
    'SELECT COUNT(*) AS c FROM pattern_matches pm
       JOIN matched_files mf ON pm.file = mf.id
      WHERE pm.package = 1 AND mf.filename = ? AND pm.ignored = false', $filename
  )->hash->{c};
  is $still_unignored, 0, 'matches in the ignored-glob file are now marked ignored';

  my $with_fake_fk = $db->query('SELECT COUNT(*) AS c FROM pattern_matches WHERE ignored_line IS NOT NULL')->hash->{c};
  is $with_fake_fk, 0, 'glob-ignored matches do not invent an ignored_lines reference';
};

subtest 'Reindex of an accepted package upgrades it to acceptable_by_lawyer' => sub {
  my $pkgs = $t->app->packages;
  my $db   = $t->app->pg->db;

  my $src       = $pkgs->find(1);
  my $shortname = $src->{checksum};
  ok $shortname, 'source package has a checksum';

  my $make = sub {
    my ($state) = @_;
    my $pid = $pkgs->add(
      name            => 'perl-Mojolicious',
      checkout_dir    => $src->{checkout_dir},
      api_url         => 'https://api.opensuse.org',
      requesting_user => 1,
      project         => 'devel:languages:perl',
      package         => 'perl-Mojolicious',
      srcmd5          => $src->{checkout_dir},
      priority        => 5
    );
    $db->query(
      'INSERT INTO bot_reports (package, ldig_report, declarations, rolemodel)
       SELECT ?, ldig_report, declarations, rolemodel FROM bot_reports WHERE package = 1', $pid
    );
    $db->query(
      'UPDATE bot_packages SET indexed = NOW(), reviewed = NOW(), reviewing_user = 1, checksum = ?, state = ? WHERE id = ?',
      $shortname, $state, $pid);
    return $pid;
  };

  my $lawyer = $make->('acceptable_by_lawyer');
  my $target = $make->('acceptable');
  $db->query('UPDATE bot_packages SET ai_assisted = ? WHERE id = ?', 1, $target);

  $t->app->minion->enqueue(analyzed => [$target]);
  $t->app->minion->perform_jobs;

  my $res = $pkgs->find($target);
  is $res->{state},          'acceptable_by_lawyer', 'upgraded to acceptable_by_lawyer';
  is $res->{reviewing_user}, undef,                  'reviewing user cleared on upgrade';
  ok !$res->{ai_assisted}, 'ai_assisted reset on upgrade';
  like $res->{result}, qr/reviewed by lawyer under the same license \($lawyer\)/, 'result names the lawyer sibling';

  subtest 'an unacceptable sibling vetoes the upgrade' => sub {
    $make->('unacceptable');
    my $target2 = $make->('acceptable');

    $t->app->minion->enqueue(analyzed => [$target2]);
    $t->app->minion->perform_jobs;

    is $pkgs->find($target2)->{state}, 'acceptable', 'stays acceptable when a sibling is unacceptable';
  };
};

subtest 'Versioned and build service names share the decisions of their package family' => sub {
  my $app  = $t->app;
  my $pkgs = $app->packages;
  my $db   = $app->pg->db;
  my $src  = $pkgs->find(1);

  my $make = sub {
    my ($name, $from, $checksum) = @_;
    $from //= 1;
    my $pid = $pkgs->add(
      name            => $name,
      checkout_dir    => $src->{checkout_dir},
      api_url         => 'https://api.opensuse.org',
      requesting_user => 1,
      project         => 'SUSE:Maintenance:12345',
      package         => $name,
      srcmd5          => $src->{checkout_dir},
      priority        => 5
    );
    $db->query(
      'INSERT INTO bot_reports (package, ldig_report, declarations, rolemodel)
       SELECT ?, ldig_report, declarations, rolemodel FROM bot_reports WHERE package = ?', $pid, $from
    );
    $db->query('UPDATE bot_packages SET indexed = NOW(), checksum = ? WHERE id = ?',
      $checksum // $pkgs->find($from)->{checksum}, $pid);
    $app->minion->enqueue(analyzed => [$pid]);
    $app->minion->perform_jobs;
    return $pkgs->find($pid);
  };

  my $incident = $make->('perl-Mojolicious.12345');
  is $incident->{family}, 'perl-Mojolicious', 'family stored';
  is $incident->{state},  'new',              'held';
  like $incident->{notice},
    qr/Manual review is required because it was rejected before with the same license as \d+ in perl-Mojolicious/,
    'the rejection of a sibling with the same report holds it';

  $db->query("UPDATE bot_packages SET state = 'acceptable' WHERE state = 'unacceptable'");
  $app->minion->enqueue(analyzed => [$incident->{id}]);
  $app->minion->perform_jobs;
  $incident = $pkgs->find($incident->{id});
  is $incident->{state}, 'acceptable_by_lawyer', 'inherited the lawyer decision';
  like $incident->{result},
    qr/^Accepted because previously reviewed under the same license in perl-Mojolicious \(\d+\)$/,
    'result names the sibling package';

  my $versioned = $make->('perl-Mojolicious-9.41');
  is $versioned->{state}, 'acceptable_by_lawyer', 'version token folded too';

  my $same = $make->('perl-Mojolicious.34567', 2, 'GPL-1.0-or-later-9:fresh1');
  is $same->{result}, 'Accepted because of no significant difference in perl-Mojolicious (2)',
    'names the sibling package';
  is $same->{notice}, 'Not found any significant difference against 2 in perl-Mojolicious', 'notice names it too';

  my $other = $make->('perl-Mojolicious-Plugin');
  is $other->{family}, 'perl-Mojolicious-Plugin', 'own family';
  is $other->{state},  'new',                     'different package inherits nothing';

  subtest 'A limitation holds the whole family' => sub {
    $app->notes->add(1, 'perl-Mojolicious', 1, 'Only for the base system', 0, 0, undef, 1);
    my $limited = $make->('perl-Mojolicious.23456');
    is $limited->{state}, 'new', 'held';
    like $limited->{notice}, qr/Limitation noted in 1 of perl-Mojolicious\s+Only for the base system/,
      'limitation of the sibling';
    is scalar @{$app->notes->limitations('perl-Mojolicious-9.41')}, 1, 'visible from every name';
    $db->query('DELETE FROM package_notes WHERE limitation');
  };

  subtest 'Ignored matches cover the whole family' => sub {
    my $ids = $pkgs->ignore_line({package => 'perl-Mojolicious', hash => 'family-hash', owner => 1});
    ok((grep { $_ == $incident->{id} } @$ids),  'build service name reindexed');
    ok((grep { $_ == $versioned->{id} } @$ids), 'versioned name reindexed');
    ok !(grep { $_ == $other->{id} } @$ids), 'different package left alone';
    ok $app->patterns->ignore_pattern_exists('perl-Mojolicious.12345',   'family-hash'), 'found from a sibling';
    ok !$app->patterns->ignore_pattern_exists('perl-Mojolicious-Plugin', 'family-hash'), 'not for a different package';

    my $events = $app->audit_log->paginate_events({search => 'perl-Mojolicious.12345', limit => 100, offset => 0});
    ok(
      (
        grep { ($_->{package_name} // '') eq 'perl-Mojolicious' && $_->{type} eq 'ignored_match.added' }
          @{$events->{page}}
      ),
      'audit events of a sibling show up in the family history'
    );
  };

  subtest 'Stored families are brought up to date' => sub {
    $db->query('UPDATE bot_packages SET family = NULL WHERE id = ?', $incident->{id});
    is_deeply $pkgs->sync_families, [], 'a first family regroups nothing';
    is $pkgs->find($incident->{id})->{family}, 'perl-Mojolicious', 'filled in';
    $db->query("UPDATE bot_packages SET family = 'perl-Mojo' WHERE id = ?", $incident->{id});
    is_deeply $pkgs->sync_families, ['perl-Mojo', 'perl-Mojolicious'], 'both families of a regrouped name';
    is $pkgs->find($incident->{id})->{family}, 'perl-Mojolicious', 'restored';
    is_deeply $pkgs->sync_families, [], 'nothing left to change';
  };
};

done_testing;
