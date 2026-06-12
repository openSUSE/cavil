# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Mojo::Base -strict, -signatures;

use FindBin;
use lib "$FindBin::Bin/lib";

use Test::More;
use Test::Mojo;
use Cavil::Test;
use Mojo::JSON qw(true false);

plan skip_all => 'set TEST_ONLINE to enable this test' unless $ENV{TEST_ONLINE};

my $cavil_test = Cavil::Test->new(online => $ENV{TEST_ONLINE}, schema => 'notes_test');
my $t          = Test::Mojo->new(Cavil => $cavil_test->default_config);
$cavil_test->mojo_fixtures($t->app);

# Test-only helper: jump straight into a session as any seeded user, so the
# error-path tests can exercise non-admin perspectives. Dummy /login only
# creates "tester" with admin/manager/classifier; this gives us cheap access
# to lawyer/contributor sessions without standing up OpenID Connect.
$t->app->routes->get(
  '/test/become/:login' => sub ($c) {
    my $login = $c->stash('login');
    my $user  = $c->app->users->find(login => $login);
    return $c->render(text => 'unknown user', status => 404) unless $user;
    $c->session(user => $login);
    $c->render(text => 'ok');
  }
);

# Two perl-Mojolicious packages share the name; notes should be shared.
my $app  = $t->app;
my $pkg1 = $app->packages->find(1);
my $pkg2 = $app->packages->find(2);
is $pkg1->{name},           'perl-Mojolicious',    'package 1 is perl-Mojolicious';
is $pkg2->{name},           'perl-Mojolicious',    'package 2 is perl-Mojolicious (different version)';
isnt $pkg1->{checkout_dir}, $pkg2->{checkout_dir}, 'different checkouts';

# Set up two more users beyond the default test_bot: contrib (contributor),
# lawyer (lawyer), admin (admin). The Test::Mojo session is shared, so we log
# in/out via /login (which creates the dummy "tester" admin user on demand).
my $contrib_id = $app->users->find_or_create(
  login    => 'contrib_user',
  email    => 'contrib@example.com',
  fullname => 'Contributing User',
  roles    => ['contributor']
)->{id};
my $lawyer_id = $app->users->find_or_create(
  login    => 'lawyer_user',
  email    => 'lawyer@example.com',
  fullname => 'Lawyerly User',
  roles    => ['lawyer']
)->{id};

# Helper: log in as the dummy admin "tester"; helper for guests is to just
# clear the session via /logout.
sub login_admin ($t) {
  $t->get_ok('/login')->status_is(302);
}
sub logout ($t) { $t->get_ok('/logout')->status_is(302); }

subtest 'Unauthenticated users cannot use the notes API' => sub {
  $t->get_ok('/reviews/notes/1')->status_is(401);
  $t->get_ok('/reviews/notes/recent')->status_is(401);
  $t->get_ok('/reviews/notes/recent.json')->status_is(401);
  $t->post_ok('/reviews/notes/1' => form => {body => 'nope'})->status_is(401);
  $t->delete_ok('/reviews/notes/1')->status_is(401);
};

subtest 'Empty list returns counters' => sub {
  login_admin($t);
  $t->get_ok('/reviews/notes/1')
    ->status_is(200)
    ->json_is('/notes'               => [])
    ->json_is('/total'               => 0)
    ->json_is('/has_more'            => false)
    ->json_is('/can_lawyer_only'     => true)
    ->json_is('/can_see_lawyer_only' => true);
  logout($t);
};

subtest 'Create + list a public note' => sub {
  login_admin($t);
  $t->post_ok('/reviews/notes/1' => form => {body => "Hello **world**\n"})
    ->status_is(200)
    ->json_is('/note/body' => "Hello **world**\n")
    ->json_like('/note/body_html' => qr{<strong>world</strong>})
    ->json_is('/note/lawyer_only'            => false)
    ->json_is('/note/ai_assisted'            => false)
    ->json_is('/note/author/login'           => 'tester')
    ->json_is('/note/author/badge'           => 'admin')
    ->json_is('/note/original_package/id'    => 1)
    ->json_is('/note/original_package/state' => 'new')
    ->json_is('/note/can_delete'             => true);

  $t->get_ok('/reviews/notes/1')
    ->status_is(200)
    ->json_is('/total'               => 1)
    ->json_is('/notes/0/body'        => "Hello **world**\n")
    ->json_is('/notes/0/ai_assisted' => false)
    ->json_is('/notes/0/can_delete'  => true);
  logout($t);
};

subtest 'AI-assisted notes are exposed in API responses' => sub {
  my $ai_note = $app->notes->add(1, 'perl-Mojolicious', $contrib_id, 'generated note', 0, 1);

  login_admin($t);
  $t->get_ok('/reviews/notes/1')
    ->status_is(200)
    ->json_is('/notes/0/id'          => $ai_note->{id})
    ->json_is('/notes/0/body'        => 'generated note')
    ->json_is('/notes/0/ai_assisted' => true);
  logout($t);

  ok $app->notes->remove($ai_note->{id}), 'removed AI-assisted fixture note';
};

subtest 'Validation' => sub {
  login_admin($t);
  $t->post_ok('/reviews/notes/1'    => form => {body => ''})->status_is(400);
  $t->post_ok('/reviews/notes/1'    => form => {})->status_is(400);
  $t->post_ok('/reviews/notes/9999' => form => {body => 'orphan'})->status_is(404);
  logout($t);
};

subtest 'Notes are shared between package versions' => sub {
  login_admin($t);

  # Note was added against pkg1 in the previous subtest; both pkg ids serve
  # the same list because they share the name.
  $t->get_ok('/reviews/notes/2')
    ->status_is(200)
    ->json_is('/total'                       => 1)
    ->json_is('/notes/0/body'                => "Hello **world**\n")
    ->json_is('/notes/0/original_package/id' => 1);

  # Adding a note from pkg2 also surfaces on pkg1.
  $t->post_ok('/reviews/notes/2' => form => {body => 'from version 2'})->status_is(200);
  $t->get_ok('/reviews/notes/1')->status_is(200)->json_is('/total' => 2);
  $t->get_ok('/reviews/notes/2')
    ->status_is(200)
    ->json_is('/total'                       => 2)
    ->json_is('/notes/0/body'                => 'from version 2')
    ->json_is('/notes/0/original_package/id' => 2)
    ->json_is('/notes/1/original_package/id' => 1);
  logout($t);
};

subtest 'Obsolete package without legal report still exposes notes' => sub {
  login_admin($t);

  my $db       = $app->pg->db;
  my $pkg      = $app->packages->find(2);
  my $report   = $db->select('bot_reports', 'ldig_report', {package => 2})->hash;
  my $original = {obsolete => $pkg->{obsolete}, state => $pkg->{state}, ldig_report => $report->{ldig_report}};

  $db->update('bot_packages', {obsolete => 1, state => 'obsolete'}, {id => 2});
  $db->update('bot_reports', {ldig_report => undef}, {package => 2});

  $t->get_ok('/reviews/details/2')
    ->status_is(200)
    ->content_like(qr/id="report-details"/)
    ->content_like(qr/cavil\.setupReportDetails\(2, true, false, true\)/);

  $t->get_ok('/reviews/report_details/2')
    ->status_is(200)
    ->json_is('/error'              => 'no report')
    ->json_is('/obsolete'           => true)
    ->json_is('/report_unavailable' => true);

  $t->get_ok('/reviews/notes/2')
    ->status_is(200)
    ->json_is('/total'        => 2)
    ->json_is('/notes/0/body' => 'from version 2')
    ->json_is('/notes/1/body' => "Hello **world**\n");

  $db->update('bot_reports', {ldig_report => $original->{ldig_report}}, {package => 2});
  $db->update('bot_packages', {obsolete => $original->{obsolete}, state => $original->{state}}, {id => 2});
  logout($t);
};

subtest 'Lawyer-only visibility + posting permissions' => sub {

  # Direct DB seeding because there is no dummy-login for non-admins.
  my $lawyer_note_id = $app->notes->add(1, 'perl-Mojolicious', $lawyer_id, 'sensitive note', 1)->{id};

  # An admin sees the lawyer-only note and can post lawyer-only.
  login_admin($t);
  $t->get_ok('/reviews/notes/1')
    ->status_is(200)
    ->json_is('/total'                => 3)
    ->json_is('/lawyer_only'          => 1)
    ->json_is('/can_lawyer_only'      => true)
    ->json_is('/notes/0/lawyer_only'  => true)
    ->json_is('/notes/0/author/badge' => 'lawyer');
  logout($t);

  # The admin token in the controller checks roles via the session user.
  # Without dummy-login support for lawyers we exercise the model directly
  # for visibility:
  ok !$app->notes->list('perl-Mojolicious', include_lawyer_only => 0)->{notes}[0]{lawyer_only},
    'public list excludes lawyer-only notes';
  my $public_list = $app->notes->list('perl-Mojolicious', include_lawyer_only => 0);
  is scalar(@{$public_list->{notes}}), 2, 'public list has 2 entries (one lawyer-only hidden)';

  # An admin attempting to post lawyer_only succeeds.
  login_admin($t);
  $t->post_ok('/reviews/notes/1' => form => {body => 'admin-only', lawyer_only => '1'})
    ->status_is(200)
    ->json_is('/note/lawyer_only' => true);
  logout($t);

  # Verify the contributor user cannot post lawyer-only via the model+role
  # combination (controller _can_post_lawyer_only is role-gated).
  ok !$app->users->has_role('contrib_user', 'admin', 'lawyer'), 'contributor has neither admin nor lawyer role';

  # Cleanup so later subtests see a predictable count.
  ok $app->notes->remove($lawyer_note_id), 'removed seeded lawyer-only note';
};

subtest 'Recent notes page and JSON feed' => sub {
  my $recent_public_id = $app->notes->add(2, 'perl-Mojolicious', $contrib_id, 'recent public note',      0)->{id};
  my $recent_lawyer_id = $app->notes->add(1, 'perl-Mojolicious', $lawyer_id,  'recent lawyer-only note', 1)->{id};

  login_admin($t);
  $t->get_ok('/reviews/notes/recent')
    ->status_is(200)
    ->content_like(qr/id="recent-notes"/)
    ->content_like(qr/cavil\.setupRecentNotes\(true\)/);
  $t->get_ok('/reviews/notes/recent.json?limit=abc')
    ->status_is(400)
    ->json_like('/error' => qr/Invalid request parameters/);
  $t->get_ok('/reviews/notes/recent.json?before_id=abc')
    ->status_is(400)
    ->json_like('/error' => qr/Invalid request parameters/);
  logout($t);

  $t->get_ok('/test/become/contrib_user')->status_is(200);
  $t->get_ok('/reviews/notes/recent')
    ->status_is(200)
    ->content_like(qr/id="recent-notes"/)
    ->content_like(qr/cavil\.setupRecentNotes\(false\)/)
    ->content_unlike(qr/Lawyer-only notes/);
  $t->get_ok('/reviews/notes/recent.json?limit=2')
    ->status_is(200)
    ->json_is('/can_see_lawyer_only'         => false)
    ->json_is('/notes/0/id'                  => $recent_public_id)
    ->json_is('/notes/0/body'                => 'recent public note')
    ->json_is('/notes/0/package_name'        => 'perl-Mojolicious')
    ->json_is('/notes/0/original_package/id' => 2);
  my $contrib_notes = $t->tx->res->json('/notes');
  ok !(grep { $_->{id} == $recent_lawyer_id } @$contrib_notes), 'contributor feed hides lawyer-only notes';

  $t->get_ok("/reviews/notes/recent.json?limit=2&before_id=$recent_public_id")->status_is(200);
  my $older = $t->tx->res->json('/notes');
  ok !@$older || $older->[0]{id} < $recent_public_id, 'recent notes cursor moves backward';
  logout($t);

  $t->get_ok('/test/become/lawyer_user')->status_is(200);
  $t->get_ok('/reviews/notes/recent.json?limit=1')
    ->status_is(200)
    ->json_is('/can_see_lawyer_only' => true)
    ->json_is('/notes/0/id'          => $recent_lawyer_id)
    ->json_is('/notes/0/lawyer_only' => true);
  logout($t);
};

subtest 'Pagination via before_id cursor' => sub {
  login_admin($t);

  # Add 25 small notes and verify two pages.
  for my $i (1 .. 25) {
    $app->notes->add(1, 'perl-Mojolicious', $contrib_id, "bulk #$i", 0);
  }

  $t->get_ok('/reviews/notes/1?limit=20')->status_is(200)->json_is('/has_more' => true);
  my $first = $t->tx->res->json('/notes');
  is scalar(@$first), 20, 'first page has 20 notes';

  my $last_id = $first->[-1]{id};
  $t->get_ok("/reviews/notes/1?limit=20&before_id=$last_id")->status_is(200);
  my $second = $t->tx->res->json('/notes');
  ok scalar(@$second) > 0,        'second page has results';
  ok $second->[0]{id} < $last_id, 'cursor moves backward';
  logout($t);
};

subtest 'Delete permissions' => sub {
  login_admin($t);

  # Tester (admin) creates a note, then can delete their own.
  $t->post_ok('/reviews/notes/1' => form => {body => 'admin self-delete'})->status_is(200);
  my $own_id = $t->tx->res->json('/note/id');
  $t->delete_ok("/reviews/notes/$own_id")->status_is(200)->json_is('/removed' => true);

  # Admin can delete another user's note.
  my $other_id = $app->notes->add(1, 'perl-Mojolicious', $contrib_id, 'someone elses', 0)->{id};
  $t->delete_ok("/reviews/notes/$other_id")->status_is(200)->json_is('/removed' => true);

  # 404 for unknown ids.
  $t->delete_ok('/reviews/notes/999999')->status_is(404);
  logout($t);
};

subtest 'Edit notes' => sub {
  login_admin($t);

  # Tester writes a note, edits it, observes the edited marker.
  $t->post_ok('/reviews/notes/1' => form => {body => 'first draft'})->status_is(200);
  my $own_id = $t->tx->res->json('/note/id');
  is $t->tx->res->json('/note/edited_epoch'), undef, 'fresh note has no edited_epoch';
  ok $t->tx->res->json('/note/can_edit'), 'author can edit their own note';

  $t->patch_ok("/reviews/notes/$own_id" => form => {body => 'edited *body*'})
    ->status_is(200)
    ->json_is('/note/body' => 'edited *body*')
    ->json_like('/note/body_html' => qr{<em>body</em>})
    ->json_has('/note/edited_epoch');
  ok $t->tx->res->json('/note/edited_epoch') > 0, 'edited_epoch is set after edit';

  # Validation: empty body rejected; missing note 404s.
  $t->patch_ok("/reviews/notes/$own_id" => form => {body => ''})->status_is(400);
  $t->patch_ok('/reviews/notes/999999'  => form => {body => 'nope'})->status_is(404);

  # Admin can edit a note authored by someone else.
  my $other_id = $app->notes->add(1, 'perl-Mojolicious', $contrib_id, 'someone elses', 0)->{id};
  $t->patch_ok("/reviews/notes/$other_id" => form => {body => 'admin-corrected'})
    ->status_is(200)
    ->json_is('/note/body' => 'admin-corrected');

  logout($t);
};

subtest 'Note preview endpoint' => sub {
  login_admin($t);
  $t->post_ok('/reviews/notes/preview' => form => {body => "# heading\n\n[ok](https://example.com)"})
    ->status_is(200)
    ->json_like('/html' => qr{<h1>heading</h1>})
    ->json_like('/html' => qr{<a href="https://example\.com">ok</a>});

  # Safe-mode sanitization still applies on the preview path: raw HTML is
  # stripped, while markdown that lives in its own paragraph still renders.
  $t->post_ok('/reviews/notes/preview' => form => {body => "<script>alert(1)</script>\n\n**bold**"})
    ->status_is(200)
    ->json_unlike('/html' => qr/<script>/)
    ->json_like('/html' => qr{<strong>bold</strong>});

  # Empty body fails validation rather than rendering an empty preview.
  $t->post_ok('/reviews/notes/preview' => form => {body => ''})->status_is(400);
  logout($t);

  # Unauthenticated callers cannot probe the preview endpoint.
  $t->post_ok('/reviews/notes/preview' => form => {body => 'hello'})->status_is(401);
};

subtest 'Controller error conditions' => sub {
  login_admin($t);

  subtest 'GET list rejects unknown packages and bad query params' => sub {
    $t->get_ok('/reviews/notes/999999')->status_is(404)->json_is('/error' => 'Package not found');
    $t->get_ok('/reviews/notes/1?limit=abc')->status_is(400)->json_like('/error' => qr/Invalid request parameters/);
    $t->get_ok('/reviews/notes/1?before_id=abc')->status_is(400)->json_like('/error' => qr/Invalid request parameters/);
  };

  subtest 'POST rejects bad payloads' => sub {

    # Body too short / missing covered earlier; this targets the lawyer_only
    # enum and the missing-package 404 for completeness.
    $t->post_ok('/reviews/notes/1' => form => {body => 'x', lawyer_only => 'maybe'})
      ->status_is(400)
      ->json_like('/error' => qr/Invalid request parameters/);
    $t->post_ok('/reviews/notes/999999' => form => {body => 'orphan'})->status_is(404);
  };

  subtest 'PATCH rejects bad payloads and unknown ids' => sub {
    $t->patch_ok('/reviews/notes/1' => form => {})
      ->status_is(400)
      ->json_like('/error' => qr/Invalid request parameters/);
    $t->patch_ok('/reviews/notes/999999' => form => {body => 'nope'})->status_is(404);
  };

  logout($t);
};

subtest 'Authorization error paths' => sub {

  # Seed comments owned by different authors so the permissions matrix can be
  # exercised end-to-end via the HTTP API.
  my $contrib_note_id = $app->notes->add(1, 'perl-Mojolicious', $contrib_id, 'contributor note', 0)->{id};
  my $lawyer_note_id  = $app->notes->add(1, 'perl-Mojolicious', $lawyer_id,  'lawyer-only seed', 1)->{id};

  subtest 'Contributor cannot post a lawyer-only note via the API' => sub {
    $t->get_ok('/test/become/contrib_user')->status_is(200);
    $t->post_ok('/reviews/notes/1' => form => {body => 'sneak attempt', lawyer_only => '1'})
      ->status_is(403)
      ->json_like('/error' => qr/Not allowed to post lawyer-only/);

    # Plain post still works (proves the 403 was specifically about lawyer-only,
    # not a blanket no-write rule).
    $t->post_ok('/reviews/notes/1' => form => {body => 'normal post'})->status_is(200);
    logout($t);
  };

  subtest q{Contributor cannot edit or delete another user's note} => sub {
    $t->get_ok('/test/become/contrib_user')->status_is(200);
    $t->patch_ok("/reviews/notes/$lawyer_note_id" => form => {body => 'rewrite'})
      ->status_is(403)
      ->json_like('/error' => qr/Not allowed to edit/);
    $t->delete_ok("/reviews/notes/$lawyer_note_id")->status_is(403)->json_like('/error' => qr/Not allowed to remove/);

    # And the owner CAN edit/delete it (positive sanity check on the gate).
    $t->patch_ok("/reviews/notes/$contrib_note_id" => form => {body => 'self-edit'})->status_is(200);
    $t->delete_ok("/reviews/notes/$contrib_note_id")->status_is(200);
    logout($t);
  };

  subtest 'Contributor list payload hides lawyer-only entries' => sub {
    $t->get_ok('/test/become/contrib_user')->status_is(200);
    $t->get_ok('/reviews/notes/1')
      ->status_is(200)
      ->json_is('/lawyer_only'         => 0)
      ->json_is('/can_lawyer_only'     => false)
      ->json_is('/can_see_lawyer_only' => false);
    my $bodies = $t->tx->res->json('/notes');
    ok !(grep { $_->{lawyer_only} } @$bodies), 'no lawyer-only entries leak into the contributor list';
    logout($t);
  };

  subtest q{Lawyer can post lawyer-only, but not delete other authors' notes} => sub {
    $t->get_ok('/test/become/lawyer_user')->status_is(200);
    $t->post_ok('/reviews/notes/1' => form => {body => 'lawyer-authored', lawyer_only => '1'})
      ->status_is(200)
      ->json_is('/note/lawyer_only' => true);

    # Deleting their own seeded one is fine (owner).
    $t->delete_ok("/reviews/notes/$lawyer_note_id")->status_is(200);

    # Deleting someone else's note is blocked.
    my $foreign = $app->notes->add(1, 'perl-Mojolicious', $contrib_id, 'foreign note', 0)->{id};
    $t->delete_ok("/reviews/notes/$foreign")->status_is(403)->json_like('/error' => qr/Not allowed to remove/);
    logout($t);
  };
};

subtest 'CommonMark renders safely' => sub {
  login_admin($t);
  my $body = "Click [me](javascript:alert(1)) or visit <https://example.com>.\n\n<script>alert(1)</script>";
  $t->post_ok('/reviews/notes/1' => form => {body => $body})->status_is(200);
  my $html = $t->tx->res->json('/note/body_html');
  unlike $html, qr/<script>/,                       'raw <script> stripped';
  unlike $html, qr/href="javascript:/,              'javascript: scheme stripped';
  like $html,   qr{<a href="https://example\.com"}, 'safe link preserved';
  logout($t);
};

done_testing;
