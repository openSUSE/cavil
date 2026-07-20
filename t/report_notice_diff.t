# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Mojo::Base -strict, -signatures;

use FindBin;
use lib "$FindBin::Bin/lib";

use Test::More;
use Test::Mojo;
use Cavil::Test;
use Mojo::JSON qw(decode_json);

plan skip_all => 'set TEST_ONLINE to enable this test' unless $ENV{TEST_ONLINE};

my $cavil_test = Cavil::Test->new(online => $ENV{TEST_ONLINE}, schema => 'report_notice_diff_test');
my $t          = Test::Mojo->new(Cavil => $cavil_test->default_config);
$cavil_test->report_notice_fixtures($t->app);

my $app  = $t->app;
my $pkgs = $app->packages;
my $db   = $app->pg->db;

# The set of unresolved files the report flags "new", by filename.
my $badged_new = sub ($id) {
  $t->get_ok("/reviews/report_details/$id")->status_is(200);
  my $missed = $t->tx->res->json->{missed_files};
  return {map { $_->{name} => 1 } grep { $_->{new} } @$missed};
};

# Version 2 (package id 2) is the "new" review: eight brand-new unresolved files
# vs the closest previous review (version 1).
subtest 'New unresolved files are badged' => sub {
  $t->get_ok('/login')->status_is(302);
  is scalar(keys %{$badged_new->(2)}), 8, 'eight files badged new';
};

subtest 'Reindex refreshes the diff and badges by filename, not id' => sub {

  # Reindexing an accepted package deletes and re-inserts every matched_files row,
  # minting fresh ids, and rewrites notice/diff_report from the current report.
  # The diff joins back to the live report by filename, so the badges survive the
  # id churn.
  my $ids_before = $db->query('SELECT id FROM matched_files WHERE package = 2 ORDER BY id')->arrays->flatten->to_array;

  my $pkg = $pkgs->find(2);
  $pkg->{reviewing_user}   = 1;
  $pkg->{result}           = 'Reviewed ok';
  $pkg->{state}            = 'acceptable';
  $pkg->{review_timestamp} = 1;
  $pkgs->update($pkg);

  ok $pkgs->reindex(2), 'reindex queued';
  $app->minion->perform_jobs;

  my $ids_after = $db->query('SELECT id FROM matched_files WHERE package = 2 ORDER BY id')->arrays->flatten->to_array;
  isnt "@$ids_after", "@$ids_before", 'matched_files ids churned by reindex';

  my $diff = decode_json($pkgs->find(2)->{diff_report});
  is $diff->{closest},                   1, 'closest still points at version 1';
  is scalar(@{$diff->{new_unresolved}}), 8, 'diff refreshed with eight new unresolved files';
  ok !(grep { !exists $_->{name} } @{$diff->{new_unresolved}}), 'every entry is keyed by filename';

  is scalar(keys %{$badged_new->(2)}), 8, 'still eight files badged new after id churn';
};

subtest 'Stale diff on an accepted package is corrected by reindex' => sub {

  # Seed a deliberately wrong notice/diff (as if left over from an older pattern
  # set) on the already-accepted package, then reindex and confirm both columns
  # are replaced with the current delta rather than left to confuse reviewers.
  $db->query(
    q{UPDATE bot_packages SET notice = ?, diff_report = ? WHERE id = 2},
    'STALE - do not trust',
    '{"version":1,"closest":999,"new_licenses":[],"new_unresolved":[{"name":"ghost.txt"}]}'
  );

  ok $pkgs->reindex(2), 'reindex queued';
  $app->minion->perform_jobs;

  my $pkg = $pkgs->find(2);
  like $pkg->{notice}, qr/New unresolved matches in 8 files/, 'stale notice replaced by current delta';

  my $diff = decode_json($pkg->{diff_report});
  is $diff->{closest},                   1, 'closest recomputed to version 1';
  is scalar(@{$diff->{new_unresolved}}), 8, 'ghost file replaced by the eight real ones';
  ok !(grep { $_->{name} eq 'ghost.txt' } @{$diff->{new_unresolved}}), 'stale ghost.txt entry gone';

  is scalar(keys %{$badged_new->(2)}), 8, 'badges reflect the corrected diff';
};

done_testing;
