# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Mojo::Base -strict, -signatures;

use FindBin;
use lib "$FindBin::Bin/lib";

use Test::More;
use Test::Mojo;
use Cavil::Test;

plan skip_all => 'set TEST_ONLINE to enable this test' unless $ENV{TEST_ONLINE};

my $cavil_test = Cavil::Test->new(online => $ENV{TEST_ONLINE}, schema => 'limited_test');
my $t          = Test::Mojo->new(Cavil => $cavil_test->default_config);
$cavil_test->mojo_fixtures($t->app);
my $app  = $t->app;
my $db   = $app->pg->db;
my $pkgs = $app->packages;

my $analyze = sub ($id) {
  $app->minion->enqueue(analyzed => [$id]);
  $app->minion->perform_jobs;
  return $pkgs->find($id);
};
my $limit = sub ($id, $body) {
  $t->post_ok("/reviews/notes/$id" => form => {body => $body, limitation => 1})
    ->status_is(200)
    ->json_is('/note/limitation', 1);
  my $note_id = $t->tx->res->json('/note/id');
  $app->minion->perform_jobs;
  return $note_id;
};
my $lift = sub ($note_id) {
  $t->delete_ok("/reviews/notes/$note_id")->status_is(200)->json_is('/removed', 1);
  $app->minion->perform_jobs;
};

# A copy of package 1 with the same report, like a resubmission of the same sources
my $copy = sub ($state = 'new', $checksum = undef) {
  my $src = $pkgs->find(1);
  my $id  = $pkgs->add(
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
     SELECT ?, ldig_report, declarations, rolemodel FROM bot_reports WHERE package = 1', $id
  );
  $db->query(
    'UPDATE bot_packages SET indexed = NOW(), checksum = ?, state = ? WHERE id = ?',
    $checksum // $src->{checksum},
    $state, $id
  );
  $db->query('UPDATE bot_packages SET reviewed = NOW(), reviewing_user = 1 WHERE id = ?', $id) if $state ne 'new';
  return $id;
};

$app->minion->enqueue(unpack => [$_]) for 1, 2;
$app->minion->perform_jobs;
$t->get_ok('/login')->status_is(302);

my $header       = "Limitation noted in 1\n\n  Only with approval\n\n  See ticket 42";
my $same_license = 'Otherwise accepted same license as 1';
my $note_id;

subtest 'Only curators add limitations' => sub {
  $db->update('bot_users', {roles => ['manager']}, {login => 'tester'});
  $t->post_ok('/reviews/notes/1' => form => {body => 'Only with approval', limitation => 1})
    ->status_is(403)
    ->json_is('/error', 'Not allowed to add limitations');
  $t->get_ok('/reviews/notes/1')->status_is(200)->json_is('/can_limitation', 0);

  $db->update('bot_users', {roles => ['admin']}, {login => 'tester'});
  $t->get_ok('/reviews/notes/1')->status_is(200)->json_is('/can_limitation', 1);
  $t->post_ok('/reviews/notes/1' => form => {body => 'Only with approval', limitation => 1, lawyer_only => 1})
    ->status_is(400)
    ->json_is('/error', 'Limitations cannot be lawyer-only');
  is_deeply $app->notes->limitations('perl-Mojolicious'), [], 'nothing added';

  $t->post_ok('/reviews/review_package/1' => form => {acceptable => 1, comment => 'Checked'})->status_is(200);
  $note_id = $limit->(1, "Only with approval\n\nSee ticket 42");
  is $pkgs->find(1)->{state}, 'acceptable', 'the decision itself is a plain accept';
};

subtest 'Real diff, nothing would have been accepted' => sub {
  my $pkg = $analyze->(2);
  is $pkg->{state}, 'new', 'not accepted';
  is $pkg->{notice}, "$header\n\nDiff to closest match 1\n\n  Declared license  Artistic-2.0 -> GPL-1.0-or-later\n",
    'limitation quoted, followed by the diff';
};

my $same = $copy->();

subtest 'Same license blocked' => sub {
  my $pkg = $analyze->($same);
  is $pkg->{state},  'new',                      'not accepted';
  is $pkg->{result}, undef,                      'no result';
  is $pkg->{notice}, "$header\n\n$same_license", 'names the blocked auto-accept';
};

subtest 'Low risk and no significant difference blocked' => sub {
  my $pkg = $analyze->($copy->('new', 'perl-Mojolicious-1:low'));
  is $pkg->{state},  'new',                                        'not accepted';
  is $pkg->{notice}, "$header\n\nOtherwise accepted low risk (1)", 'names the blocked auto-accept';

  $pkg = $analyze->($copy->('new', 'perl-Mojolicious-9:high'));
  is $pkg->{state}, 'new', 'not accepted';
  like $pkg->{notice}, qr/^\Q$header\E\n\nOtherwise accepted no significant difference against \d+$/,
    'names the blocked auto-accept';

  $pkg = $analyze->($copy->('new', 'perl-Mojolicious-0:zero'));
  is $pkg->{state}, 'new', 'not accepted';
  like $pkg->{notice}, qr/^\Q$header\E\n\nNot found any significant difference against \d+$/,
    'risk 0 would not have been accepted either';
};

subtest 'Package name fast-track blocked' => sub {
  local $app->config->{acceptable_packages} = ['perl-Mojolicious'];
  my $pkg = $analyze->($same);
  is $pkg->{state},  'new',                                        'not accepted';
  is $pkg->{notice}, "$header\n\nOtherwise accepted package name", 'names the blocked auto-accept';
};

subtest 'Inherited lawyer sign-off blocked' => sub {
  my $lawyer = $copy->('acceptable_by_lawyer');
  $same_license = "Otherwise accepted same license as $lawyer";
  my $accepted = $copy->('acceptable');
  is $analyze->($accepted)->{state}, 'acceptable', 'not upgraded while the name has a limitation';
  is $analyze->(1)->{state},         'acceptable', 'the review the limitation was noted on is not upgraded either';
};

subtest 'Several limitations' => sub {
  my $second = $limit->($same, 'Not for SLE Micro');
  is $pkgs->find($same)->{notice}, "Limitation noted in $same\n\n  Not for SLE Micro\n\n$header\n\n$same_license",
    'waiting version quotes both, newest first';
  $t->get_ok("/reviews/notes/$same")
    ->status_is(200)
    ->json_is('/pinned/0/id',         $second)
    ->json_is('/pinned/1/id',         $note_id)
    ->json_is('/pinned/1/limitation', 1);

  $lift->($second);
  is $pkgs->find($same)->{notice}, "$header\n\n$same_license", 'back to one';
};

subtest 'Origin review purged' => sub {
  my $ephemeral = $copy->();
  $db->update('bot_packages', {ephemeral => 1}, {id => $ephemeral});
  my $orphan = $limit->($ephemeral, 'Ask legal first');
  $app->minion->enqueue(purge_batch => [$ephemeral]);
  $app->minion->perform_jobs;
  ok !$pkgs->find($ephemeral), 'purged';
  is $analyze->($same)->{notice}, "Limitation noted\n\n  Ask legal first\n\n$header\n\n$same_license",
    'the limitation survives without its review';
  $lift->($orphan);
};

subtest 'Obsolete origin still holds' => sub {
  $db->update('bot_packages', {obsolete => 1}, {id => 1});
  is $analyze->($same)->{state}, 'new', 'the limitation belongs to the name, not the review';
  $db->update('bot_packages', {obsolete => 0}, {id => 1});
};

subtest 'Fasttrack refused' => sub {
  $db->update('bot_users', {roles => ['manager']}, {login => 'tester'});
  $t->post_ok("/reviews/fasttrack_package/$same" => form => {comment => 'ok'})
    ->status_is(403)
    ->json_is('/error', 'Limitations apply to this package, it needs a review by a curator or lawyer');
  is $pkgs->find($same)->{state}, 'new', 'held version not fasttracked';
  $db->update('bot_users', {roles => ['admin']}, {login => 'tester'});
};

subtest 'Removing the last limitation lifts the block' => sub {
  $t->post_ok('/reviews/notes/1' => form => {body => 'Just context', pinned => 1})->status_is(200);
  $lift->($note_id);
  is_deeply $app->notes->limitations('perl-Mojolicious'), [], 'no limitations left';
  is $pkgs->find($same)->{state}, 'acceptable_by_lawyer',
    'waiting version auto-accepted without a reindex, pinned or not';

  my $waiting = $copy->();
  $db->update('bot_users', {roles => ['manager']}, {login => 'tester'});
  $t->post_ok("/reviews/fasttrack_package/$waiting" => form => {comment => 'ok'})->status_is(200);
  is $pkgs->find($waiting)->{state}, 'acceptable', 'fasttracked again';
  $db->update('bot_users', {roles => ['admin']}, {login => 'tester'});
};

subtest 'Waiting versions follow added and edited limitations' => sub {
  my $waiting = $copy->();
  $note_id = $limit->(1, 'Only with approval');
  my $pkg = $pkgs->find($waiting);
  is $pkg->{state},  'new',                                                            'still waiting';
  is $pkg->{notice}, "Limitation noted in 1\n\n  Only with approval\n\n$same_license", 'held as soon as it is added';

  $t->patch_ok("/reviews/notes/$note_id" => form => {body => "Only with approval\n\nSee ticket 42"})->status_is(200);
  $app->minion->perform_jobs;
  is $pkgs->find($waiting)->{notice}, "$header\n\n$same_license", 'quotes the edit';
};

my $bot = {Authorization => 'Token test_token'};

subtest 'The report attached for packagers leads with the limitations' => sub {
  $t->get_ok('/package/1/report.txt' => $bot)
    ->status_is(200)
    ->content_like(qr/Unpacked: [^\n]+\n\n\n\n## Limitations\n\nEvery new version of this package needs/)
    ->content_like(qr/## Limitations\n.+\n### tester on .+\n\n> Only with approval\n> \n> See ticket 42\n\n\n\n## /s)
    ->content_like(qr/## Notes\n\n### tester on [^\n]+ - pinned\n\n> Just context\n\n## About/)
    ->content_unlike(qr/## Notes.+See ticket 42/s);
};

subtest 'A new request needs a human decision again' => sub {
  $t->post_ok('/requests' => $bot => form => {external_link => 'obs#100', package => 2})->status_is(200);
  is $pkgs->find(2)->{state}, 'new', 'a request for a package in review changes nothing';

  $t->post_ok('/requests' => $bot => form => {external_link => 'obs#100', package => 1})->status_is(200);
  $t->get_ok('/package/1' => $bot)->status_is(200)->json_is('/state', 'new')->json_is('/result', 'Checked');
  $app->minion->perform_jobs;
  my $pkg = $pkgs->find(1);
  is $pkg->{state},  'new',                      'still waiting after the auto review';
  is $pkg->{notice}, "$header\n\n$same_license", 'quotes the limitation';

  $t->post_ok('/reviews/review_package/1' => form => {acceptable => 1, comment => 'Checked again'})->status_is(200);
  $t->post_ok('/requests' => $bot => form => {external_link => 'obs#100', package => 1})->status_is(200);
  $app->minion->perform_jobs;
  is $pkgs->find(1)->{state}, 'acceptable', 'a request it has already seen changes nothing';
};

subtest 'A new request without limitations changes nothing' => sub {
  $lift->($note_id);
  $t->post_ok('/requests' => $bot => form => {external_link => 'obs#101', package => 1})->status_is(200);
  $app->minion->perform_jobs;
  my $pkg = $pkgs->find(1);
  is $pkg->{state},  'acceptable',    'still accepted';
  is $pkg->{result}, 'Checked again', 'decision kept';
  $t->get_ok('/package/1/report.txt' => $bot)->status_is(200)->content_unlike(qr/## Limitations/);
};

done_testing;
