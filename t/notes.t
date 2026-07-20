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

  # Only the obsolete flag is set; the real state is preserved (as production now does)
  $db->update('bot_packages', {obsolete    => 1},     {id      => 2});
  $db->update('bot_reports',  {ldig_report => undef}, {package => 2});

  $t->get_ok('/reviews/details/2')
    ->status_is(200)
    ->content_like(qr/id="legal-report"/)
    ->content_like(qr{cavil\.setupLegalReport\(2, true, true, false, false, '/reviews/reindex/2', false, true\)});

  $t->get_ok('/reviews/report_details/2')
    ->status_is(200)
    ->json_is('/error'              => 'no report')
    ->json_is('/obsolete'           => true)
    ->json_is('/report_unavailable' => true);

  $t->get_ok('/reviews/notes/2')
    ->status_is(200)
    ->json_is('/total'                             => 2)
    ->json_is('/notes/0/body'                      => 'from version 2')
    ->json_is('/notes/0/original_package/state'    => $original->{state})
    ->json_is('/notes/0/original_package/obsolete' => true)
    ->json_is('/notes/1/body'                      => "Hello **world**\n");

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

  subtest q{Lawyer can post lawyer-only notes and moderate others' notes} => sub {
    $t->get_ok('/test/become/lawyer_user')->status_is(200);
    $t->post_ok('/reviews/notes/1' => form => {body => 'lawyer-authored', lawyer_only => '1'})
      ->status_is(200)
      ->json_is('/note/lawyer_only' => true);

    # Deleting their own seeded one is fine (owner).
    $t->delete_ok("/reviews/notes/$lawyer_note_id")->status_is(200);

    # Lawyers hold the "curate" capability, which includes note moderation, so they may also remove
    # another author's note.
    my $foreign = $app->notes->add(1, 'perl-Mojolicious', $contrib_id, 'foreign note', 0)->{id};
    $t->delete_ok("/reviews/notes/$foreign")->status_is(200)->json_is('/removed' => true);
    logout($t);
  };
};

subtest 'Tags persist through add and surface in the JSON serializer' => sub {
  my $tagged = $app->notes->add(1, 'perl-Mojolicious', $contrib_id, 'tagged via model', 0, 0, ['review', 'demo']);
  is_deeply [sort @{$tagged->{tags}}], ['demo', 'review'], 'tags persisted on add';

  login_admin($t);
  $t->get_ok('/reviews/notes/1')->status_is(200)->json_is('/notes/0/id' => $tagged->{id});
  my $serialized = $t->tx->res->json('/notes/0/tags');
  is_deeply [sort @$serialized], ['demo', 'review'], 'tags surfaced on /reviews/notes/:id';
  logout($t);

  ok $app->notes->remove($tagged->{id}), 'removed tagged fixture';
};

subtest 'Notes::edit updates tags only when explicitly provided' => sub {
  my $note = $app->notes->add(1, 'perl-Mojolicious', $contrib_id, 'tag edit fixture', 0, 0, ['review']);

  my $body_only = $app->notes->edit($note->{id}, 'new body');
  is $body_only->{body}, 'new body', 'body edit applied';
  is_deeply $body_only->{tags}, ['review'], 'tags untouched when omitted';

  my $with_tags = $app->notes->edit($note->{id}, 'new body', ['demo']);
  is_deeply $with_tags->{tags}, ['demo'], 'tags replaced when provided';

  my $cleared = $app->notes->edit($note->{id}, 'new body', []);
  is_deeply $cleared->{tags}, [], 'tags cleared with empty array';

  $app->notes->remove($note->{id});
};

subtest 'paginate_for_package honors tag AND filter and visibility' => sub {
  $app->notes->add(1, 'perl-Mojolicious', $contrib_id, 'review only',   0, 0, ['review']);
  $app->notes->add(1, 'perl-Mojolicious', $contrib_id, 'demo only',     0, 0, ['demo']);
  $app->notes->add(1, 'perl-Mojolicious', $contrib_id, 'review + demo', 0, 0, ['review', 'demo']);
  $app->notes->add(1, 'perl-Mojolicious', $lawyer_id,  'lawyer review', 1, 0, ['review']);

  my $page = $app->notes->paginate_for_package('perl-Mojolicious', tags => ['review']);
  is $page->{total}, 2, 'public review-tagged notes (lawyer-only hidden)';
  ok((grep { $_->{body} eq 'review only' } @{$page->{page}}),   'review-only note present');
  ok((grep { $_->{body} eq 'review + demo' } @{$page->{page}}), 'multi-tagged note present');

  my $both = $app->notes->paginate_for_package('perl-Mojolicious', tags => ['review', 'demo']);
  is $both->{total},         1,               'AND filter narrows to multi-tagged note';
  is $both->{page}[0]{body}, 'review + demo', 'right note returned';

  my $with_lawyer = $app->notes->paginate_for_package('perl-Mojolicious', tags => ['review'], include_lawyer_only => 1);
  is $with_lawyer->{total}, 3, 'lawyer-only review note included when flag set';

  my $no_filter = $app->notes->paginate_for_package('perl-Mojolicious');
  cmp_ok $no_filter->{total}, '>=', 3, 'empty filter returns everything (at least the public seeds)';

  for my $n (@{$no_filter->{page}}, @{$with_lawyer->{page}}) {
    next unless $n->{body} =~ /^(review only|demo only|review \+ demo|lawyer review)$/;
    $app->notes->remove($n->{id});
  }
};

subtest 'PATCH accepts a tags update and persists it' => sub {
  my $note = $app->notes->add(1, 'perl-Mojolicious', $contrib_id, 'patch tags fixture', 0);

  login_admin($t);

  # Repeating-param form (Perl/Mojo idiom).
  $t->patch_ok("/reviews/notes/$note->{id}" => form => {body => 'patched', tags => ['review', 'demo']})->status_is(200);
  my $tags = $t->tx->res->json('/note/tags');
  is_deeply [sort @$tags], ['demo', 'review'], 'PATCH applies tag set';

  # JSON-encoded form (the Vue UI's idiom; mojojs comma-joins arrays so it
  # ships tags this way instead).
  $t->patch_ok("/reviews/notes/$note->{id}" => form => {body => 'patched again', tags_json => '[]'})->status_is(200);
  is_deeply $t->tx->res->json('/note/tags'), [], 'tags_json=[] clears the list';

  $t->patch_ok("/reviews/notes/$note->{id}" => form => {body => 'no tag intent'})->status_is(200);
  is_deeply $t->tx->res->json('/note/tags'), [], 'omitting tags fields leaves them unchanged';
  logout($t);

  $app->notes->remove($note->{id});
};

subtest 'POST rejects malformed tags' => sub {
  login_admin($t);

  my $too_long = 'x' x 33;
  $t->post_ok('/reviews/notes/1' => form => {body => 'over-long tag', tags => [$too_long]})
    ->status_is(400)
    ->json_like('/error' => qr/tag exceeds/);

  $t->post_ok('/reviews/notes/1' => form => {body => 'too many', tags => [map {"t$_"} 1 .. 17]})
    ->status_is(400)
    ->json_like('/error' => qr/too many tags/);
  logout($t);
};

subtest 'all_tags reports distinct tags with counts and honors visibility' => sub {

  # Unique tag names so the assertions stay deterministic regardless of notes
  # left behind by earlier subtests.
  my @ids;
  push @ids,
    $app->notes->add(1, 'perl-Mojolicious', $contrib_id, 'tagstat a', 0, 0, ['zztag-pop', 'zztag-shared'])->{id};
  push @ids, $app->notes->add(1, 'perl-Mojolicious', $contrib_id, 'tagstat b', 0, 0, ['zztag-shared'])->{id};
  push @ids, $app->notes->add(1, 'perl-Mojolicious', $lawyer_id,  'tagstat c', 1, 0, ['zztag-secret'])->{id};

  my %public = map { $_->{tag} => $_->{count} } @{$app->notes->all_tags};
  is $public{'zztag-shared'}, 2,     'shared tag counted across both public notes';
  is $public{'zztag-pop'},    1,     'single-use public tag counted once';
  is $public{'zztag-secret'}, undef, 'tag only on a lawyer-only note is hidden from the public list';

  my %all = map { $_->{tag} => $_->{count} } @{$app->notes->all_tags(include_lawyer_only => 1)};
  is $all{'zztag-secret'}, 1, 'lawyer-only tag surfaces when the flag is set';

  # Ordering is count-desc: the shared tag must precede the single-use one.
  my @ordered     = grep {/^zztag-/} map { $_->{tag} } @{$app->notes->all_tags};
  my ($pop_at)    = grep { $ordered[$_] eq 'zztag-pop' } 0 .. $#ordered;
  my ($shared_at) = grep { $ordered[$_] eq 'zztag-shared' } 0 .. $#ordered;
  ok $shared_at < $pop_at, 'more-used tag is ordered ahead of the less-used one';

  $app->notes->remove($_) for @ids;
};

subtest 'Tags endpoint gates lawyer-only tags by role' => sub {
  my @ids;
  push @ids, $app->notes->add(1, 'perl-Mojolicious', $contrib_id, 'ep public', 0, 0, ['zzep-public'])->{id};
  push @ids, $app->notes->add(1, 'perl-Mojolicious', $lawyer_id,  'ep secret', 1, 0, ['zzep-secret'])->{id};

  login_admin($t);
  $t->get_ok('/reviews/notes/tags.json')->status_is(200);
  my %admin = map { $_->{tag} => $_->{count} } @{$t->tx->res->json('/tags')};
  is $admin{'zzep-public'}, 1, 'admin sees the public tag';
  is $admin{'zzep-secret'}, 1, 'admin sees the lawyer-only tag';
  logout($t);

  $t->get_ok('/test/become/contrib_user')->status_is(200);
  $t->get_ok('/reviews/notes/tags.json')->status_is(200);
  my %contrib = map { $_->{tag} => $_->{count} } @{$t->tx->res->json('/tags')};
  is $contrib{'zzep-public'}, 1,     'contributor sees the public tag';
  is $contrib{'zzep-secret'}, undef, 'contributor never sees the lawyer-only tag';
  logout($t);

  # Unauthenticated callers are bounced like the rest of the notes API.
  $t->get_ok('/reviews/notes/tags.json')->status_is(401);

  $app->notes->remove($_) for @ids;
};

subtest 'Recent feed filters by tag containment' => sub {
  my $a = $app->notes->add(1, 'perl-Mojolicious', $contrib_id, 'recent a', 0, 0, ['zzr-pop', 'zzr-shared'])->{id};
  my $b = $app->notes->add(2, 'perl-Mojolicious', $contrib_id, 'recent b', 0, 0, ['zzr-shared'])->{id};
  my $c = $app->notes->add(1, 'perl-Mojolicious', $lawyer_id,  'recent c', 1, 0, ['zzr-shared'])->{id};

  # Model: AND semantics + lawyer-only visibility.
  my $shared = $app->notes->recent(tags => ['zzr-shared']);
  is scalar(@{$shared->{notes}}), 2, 'public notes carrying the shared tag (lawyer-only hidden)';
  my $both = $app->notes->recent(tags => ['zzr-pop', 'zzr-shared']);
  is scalar(@{$both->{notes}}), 1,          'AND filter narrows to the multi-tagged note';
  is $both->{notes}[0]{body},   'recent a', 'right note returned';
  my $with_lawyer = $app->notes->recent(tags => ['zzr-shared'], include_lawyer_only => 1);
  is scalar(@{$with_lawyer->{notes}}), 3, 'lawyer-only note included when the flag is set';

  # HTTP: the Vue UI ships the filter as a tags_json query param.
  login_admin($t);
  $t->get_ok('/reviews/notes/recent.json?tags_json=' . '%5B%22zzr-pop%22%5D')->status_is(200);
  my $popped = $t->tx->res->json('/notes');
  is scalar(@$popped),   1,          'tags_json filter returns the single matching note';
  is $popped->[0]{body}, 'recent a', 'correct note over HTTP';

  # A malformed filter degrades to "no filter" rather than erroring.
  $t->get_ok('/reviews/notes/recent.json?tags_json=' . '%5B%22' . ('x' x 33) . '%22%5D')->status_is(200);
  ok scalar(@{$t->tx->res->json('/notes')}) >= 1, 'over-long filter tag is ignored, list still returned';
  logout($t);

  # Contributor filtering the shared tag never sees the lawyer-only note.
  $t->get_ok('/test/become/contrib_user')->status_is(200);
  $t->get_ok('/reviews/notes/recent.json?tags_json=' . '%5B%22zzr-shared%22%5D')->status_is(200);
  my $contrib = $t->tx->res->json('/notes');
  ok !(grep { $_->{id} == $c } @$contrib), 'contributor tag filter excludes the lawyer-only note';
  is scalar(@$contrib), 2, 'contributor sees both public shared-tag notes';
  logout($t);

  $app->notes->remove($_) for ($a, $b, $c);
};

subtest 'Relevance: same_report flag and relevant_only filter' => sub {
  my $db = $app->pg->db;

  # Control the license-report checksums of the two same-name packages so the
  # relevance logic is deterministic, then restore them at the end.
  my $orig1 = $app->packages->find(1)->{checksum};
  my $orig2 = $app->packages->find(2)->{checksum};
  $db->update('bot_packages', {checksum => 'rep-IDENT'}, {id => 1});
  $db->update('bot_packages', {checksum => 'rep-IDENT'}, {id => 2});

  # A native note (origin = review #1) and an inherited note from review #2
  # whose report is currently identical. These two are the newest, so they sit
  # at the top of the list.
  my $native = $app->notes->add(1, 'perl-Mojolicious', $contrib_id, 'relevance native note',    0)->{id};
  my $ident  = $app->notes->add(2, 'perl-Mojolicious', $contrib_id, 'relevance identical note', 0)->{id};

  login_admin($t);

  # Identical report -> inherited note is flagged relevant; native note too.
  $t->get_ok('/reviews/notes/1')
    ->status_is(200)
    ->json_is('/notes/0/body'                => 'relevance identical note')
    ->json_is('/notes/0/same_report'         => true)
    ->json_is('/notes/0/original_package/id' => 2)
    ->json_is('/notes/1/body'                => 'relevance native note')
    ->json_is('/notes/1/same_report'         => true)
    ->json_is('/notes/1/original_package/id' => 1);

  # Make review #2 a DIFFERENT report; its note stops being relevant, the native
  # one stays relevant (its origin is the current review).
  $db->update('bot_packages', {checksum => 'rep-OTHER'}, {id => 2});
  $t->get_ok('/reviews/notes/1')
    ->status_is(200)
    ->json_is('/notes/0/body'        => 'relevance identical note')
    ->json_is('/notes/0/same_report' => false)
    ->json_is('/notes/1/body'        => 'relevance native note')
    ->json_is('/notes/1/same_report' => true);

  # The relevant count is below the visible total now that a non-relevant note
  # exists, which is what gates the "Only relevant notes" toggle in the UI.
  my $total    = $t->tx->res->json('/total');
  my $relevant = $t->tx->res->json('/relevant');
  ok $relevant < $total, 'relevant count is below total when a different-report note exists';

  # relevant_only hides the different-report note and keeps the native one.
  $t->get_ok('/reviews/notes/1?relevant_only=1')->status_is(200);
  my $filtered = $t->tx->res->json('/notes');
  ok((grep { $_->{body} eq 'relevance native note' } @$filtered), 'native note kept under relevant_only');
  ok(
    !(grep { $_->{body} eq 'relevance identical note' } @$filtered),
    'different-report note hidden under relevant_only'
  );
  ok(!(grep { $_->{same_report} == false && $_->{original_package}{id} != 1 } @$filtered),
    'no non-relevant notes survive the relevant_only filter');
  logout($t);

  $app->notes->remove($_) for ($native, $ident);
  $db->update('bot_packages', {checksum => $orig1}, {id => 1});
  $db->update('bot_packages', {checksum => $orig2}, {id => 2});
};

subtest 'relevant_tagged_note powers the create guard' => sub {
  my $db    = $app->pg->db;
  my $orig1 = $app->packages->find(1)->{checksum};
  my $orig2 = $app->packages->find(2)->{checksum};
  $db->update('bot_packages', {checksum => 'GUARD-A'}, {id => 1});
  $db->update('bot_packages', {checksum => 'GUARD-A'}, {id => 2});

  my $native  = $app->notes->add(1, 'perl-Mojolicious', $contrib_id, 'guard native',  0, 0, ['gt'])->{id};
  my $sibling = $app->notes->add(2, 'perl-Mojolicious', $contrib_id, 'guard sibling', 0, 0, ['gt2'])->{id};

  # Native tagged note is relevant to its own review.
  is $app->notes->relevant_tagged_note('perl-Mojolicious', 1, 'GUARD-A', 'gt'), $native,
    'native tagged note is found for its own review';

  # Identical-report sibling counts as relevant to review #1.
  is $app->notes->relevant_tagged_note('perl-Mojolicious', 1, 'GUARD-A', 'gt2'), $sibling,
    'identical-report sibling tagged note is relevant';

  # Different report -> sibling no longer relevant.
  is $app->notes->relevant_tagged_note('perl-Mojolicious', 1, 'GUARD-B', 'gt2'), undef,
    'sibling from a different report is not relevant';

  # Unknown tag -> nothing.
  is $app->notes->relevant_tagged_note('perl-Mojolicious', 1, 'GUARD-A', 'nope'), undef, 'unknown tag returns undef';

  # paginate_for_package relevant_only mirrors the same predicate.
  my $rel = $app->notes->paginate_for_package(
    'perl-Mojolicious',
    relevant_only => 1,
    package_id    => 1,
    checksum      => 'GUARD-A',
    tags          => ['gt2']
  );
  is $rel->{total}, 1, 'identical-report sibling included under relevant_only';
  my $none = $app->notes->paginate_for_package(
    'perl-Mojolicious',
    relevant_only => 1,
    package_id    => 1,
    checksum      => 'GUARD-B',
    tags          => ['gt2']
  );
  is $none->{total}, 0, 'different-report sibling excluded under relevant_only';

  $app->notes->remove($_) for ($native, $sibling);
  $db->update('bot_packages', {checksum => $orig1}, {id => 1});
  $db->update('bot_packages', {checksum => $orig2}, {id => 2});
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
