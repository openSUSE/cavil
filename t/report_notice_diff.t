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

my $badged_new = sub ($id) {
  $t->get_ok("/reviews/report_details/$id")->status_is(200);
  my $missed = $t->tx->res->json->{missed_files};
  return {map { $_->{name} => 1 } grep { $_->{new} } @$missed};
};

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

# Low risk changes compared with the closest accepted version are accepted (a separate name is its own history)
my %risk = (restrictive => 6, managed => 5, copyleft => 4, weak => 3, permissive => 2);
$app->patterns->create(pattern => "delta $_ license marker", license => "Delta-\u$_", risk => $risk{$_}) for keys %risk;

my $md5     = 0;
my $version = sub ($licenses, $unresolved = []) {
  my %files = map { ("LICENSE-$_.txt" => "delta $_ license marker\n") } 'restrictive', @$licenses;
  return $cavil_test->synthetic_version($app, 1, sprintf('%032x', ++$md5), $unresolved, \%files, 'delta');
};

my $reviewed = $version->([]);
is $pkgs->find($reviewed)->{state}, 'new', 'risk 6 needs a person';
$t->post_ok("/reviews/review_package/$reviewed" => form => {acceptable => 1, comment => 'Reviewed ok'})->status_is(200);

subtest 'New licenses up to the threshold are accepted' => sub {
  my $pkg = $pkgs->find($version->(['copyleft', 'permissive']));
  is $pkg->{state},  'acceptable',                                                     'accepted';
  is $pkg->{result}, "Accepted because of low risk changes (4) compared to $reviewed", 'names the closest match';
  like $pkg->{notice}, qr/^Diff to closest match $reviewed\n\n  New licenses \(by risk\)\n    4  Delta-Copyleft\n/,
    'diff kept for reviewers';
};

subtest 'Riskier new licenses, unresolved matches and a higher threshold' => sub {
  my $managed = $version->(['managed']);
  my $pkg     = $pkgs->find($managed);
  is $pkg->{state},  'new', 'risk 5 needs a person';
  is $pkg->{result}, undef, 'no result';
  like $pkg->{notice}, qr/^Diff to closest match \d+\n\n  New licenses \(by risk\)\n    5  Delta-Managed\n$/, 'diff';

  $pkg = $pkgs->find($version->([], [1]));
  is $pkg->{state}, 'new', 'unresolved match needs a person';
  like $pkg->{notice}, qr/New unresolved matches/, 'diff';

  $t->put_ok('/settings/auto-accept.json' => json => {values => {acceptable_risk => 5}})->status_is(200);
  $app->minion->perform_jobs;
  is $pkgs->find($managed)->{state}, 'acceptable', 'accepted with the higher threshold';
  $t->put_ok('/settings/auto-accept.json' => json => {reset => ['acceptable_risk']})->status_is(200);
};

subtest 'Paused automatic acceptance holds' => sub {
  $app->settings->update('tester', {auto_accept => 0});
  my $held = $version->(['managed', 'permissive']);
  is $pkgs->find($held)->{state}, 'new', 'not accepted';
  like $pkgs->find($held)->{notice},
    qr/^Automatic acceptance is paused\n\nOtherwise accepted low risk changes \(2\)\n\nDiff to closest match \d+\n/,
    'names the blocked auto-accept, followed by the diff';

  $t->put_ok('/settings/auto-accept.json' => json => {values => {auto_accept => 1}})->status_is(200);
  $app->minion->perform_jobs;
  is $pkgs->find($held)->{state}, 'acceptable', 'accepted once resumed';
};

subtest 'A later rejection blocks low risk changes' => sub {
  my $rejected = $version->(['weak']);
  is $pkgs->find($rejected)->{state}, 'acceptable', 'accepted';
  $t->post_ok("/reviews/review_package/$rejected" => form => {unacceptable => 1, comment => 'Not with that'})
    ->status_is(200);

  my $pkg = $pkgs->find($version->(['weak', 'copyleft']));
  is $pkg->{state},  'new', 'needs a person';
  is $pkg->{result}, undef, 'no result';
  like $pkg->{notice}, qr/^Diff to closest match \d+\n\n  New licenses \(by risk\)\n    3  Delta-Weak\n$/, 'diff';
};

done_testing;
