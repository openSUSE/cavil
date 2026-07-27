# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later
use Mojo::Base -strict, -signatures;

use FindBin;
use lib "$FindBin::Bin/lib";

use Test::More;
use Test::Mojo;
use Cavil::Test;

plan skip_all => 'set TEST_ONLINE to enable this test' unless $ENV{TEST_ONLINE};

my $cavil_test = Cavil::Test->new(online => $ENV{TEST_ONLINE}, schema => 'comment_templates_test');
my $t          = Test::Mojo->new(Cavil => $cavil_test->default_config);
$cavil_test->mojo_fixtures($t->app);
my $db = $t->app->pg->db;

subtest 'Permission errors' => sub {
  $t->get_ok('/comment-templates')->status_is(403)->content_like(qr/permission/);
  $t->post_ok('/comment-templates')->status_is(403)->content_like(qr/permission/);
  $t->put_ok('/comment-templates/1')->status_is(403)->content_like(qr/permission/);
  $t->delete_ok('/comment-templates/1')->status_is(403)->content_like(qr/permission/);
  $t->get_ok('/pagination/comment-templates')->status_is(403)->content_like(qr/permission/);

  # No role requirement, so this is an authentication and not an authorization failure
  $t->get_ok('/comment-templates/all')->status_is(401);
};

subtest 'Seeded template' => sub {
  my $seed = $db->select('comment_templates', '*', {name => 'Unacceptable-File'})->hash;
  ok $seed, 'template shipped with Cavil exists';
  is $seed->{author}, undef, 'no author, it was not written by a reviewer';
  like $seed->{body}, qr/\[FILE\]/,    'contains a placeholder for the offending file';
  like $seed->{body}, qr/\[LICENSE\]/, 'contains a placeholder for its license';
  is $seed->{edited}, undef, 'never edited';
};

subtest 'Managers can read templates but not manage them' => sub {
  $t->get_ok('/login')->status_is(302)->header_is(Location => '/');
  $db->update('bot_users', {roles => ['manager']}, {login => 'tester'});

  $t->get_ok('/comment-templates/all')->status_is(200)->json_is('/0/name', 'Unacceptable-File');
  $t->get_ok('/comment-templates')->status_is(403);
  $t->post_ok('/comment-templates' => form => {name => 'Nope', body => 'Nope'})->status_is(403);

  $db->update('bot_users', {roles => ['admin']}, {login => 'tester'});
};

subtest 'Manage templates' => sub {
  $t->post_ok('/comment-templates' => form => {name => 'Bundled font'})->status_is(400)->json_like('/error', qr/body/);

  $t->post_ok('/comment-templates' => form => {name => 'Bundled font', body => 'Please unbundle [FONT]'})
    ->status_is(200)
    ->json_has('/id');
  my $id = $t->tx->res->json('/id');

  my $added = $db->select('comment_templates', '*', {id => $id})->hash;
  is $added->{body},   'Please unbundle [FONT]',                                           'body stored verbatim';
  is $added->{edited}, undef,                                                              'not edited yet';
  is $db->select('bot_users', 'login', {id => $added->{author}})->hash->{login}, 'tester', 'author recorded';

  $t->post_ok('/comment-templates' => form => {name => 'Bundled font', body => 'Something else'})
    ->status_is(400)
    ->json_is({error => 'Comment template already exists'});

  $t->get_ok('/comment-templates/all')
    ->status_is(200)
    ->json_is('/0/name', 'Bundled font')
    ->json_is('/0/body', 'Please unbundle [FONT]')
    ->json_is('/1/name', 'Unacceptable-File')
    ->json_hasnt('/2');

  $t->put_ok("/comment-templates/$id" => form => {name => 'Bundled fonts', body => 'Please unbundle [FONTS]'})
    ->status_is(200)
    ->json_is('/name', 'Bundled fonts')
    ->json_is('/body', 'Please unbundle [FONTS]');
  ok $db->select('comment_templates', 'edited', {id => $id})->hash->{edited}, 'edit timestamp set';

  # Renaming to a name that is already taken is a conflict, keeping your own name is not
  $t->put_ok("/comment-templates/$id" => form => {name => 'Unacceptable-File', body => 'Hijack'})
    ->status_is(400)
    ->json_is({error => 'Comment template already exists'});
  $t->put_ok("/comment-templates/$id" => form => {name => 'Bundled fonts', body => 'Please unbundle [FONTS] now'})
    ->status_is(200)
    ->json_is('/body', 'Please unbundle [FONTS] now');

  $t->put_ok('/comment-templates/999999' => form => {name => 'Ghost', body => 'Ghost'})
    ->status_is(400)
    ->json_is({error => 'Comment template does not exist'});

  subtest 'Pagination' => sub {
    $t->get_ok('/pagination/comment-templates')
      ->status_is(200)
      ->json_is('/start',        1)
      ->json_is('/end',          2)
      ->json_is('/total',        2)
      ->json_is('/page/0/name',  'Bundled fonts')
      ->json_is('/page/0/login', 'tester')
      ->json_has('/page/0/created_epoch')
      ->json_has('/page/0/edited_epoch')

      # The seeded template has no author, it must not be dropped by the join
      ->json_is('/page/1/name',         'Unacceptable-File')
      ->json_is('/page/1/login',        undef)
      ->json_is('/page/1/edited_epoch', undef)
      ->json_hasnt('/page/2');

    $t->get_ok('/pagination/comment-templates?filter=fonts')
      ->status_is(200)
      ->json_is('/total',       1)
      ->json_is('/page/0/name', 'Bundled fonts')
      ->json_hasnt('/page/1');

    # The body is searched too, so a reviewer can find a template by its wording
    $t->get_ok('/pagination/comment-templates?filter=unbundle')
      ->status_is(200)
      ->json_is('/total',       1)
      ->json_is('/page/0/name', 'Bundled fonts');

    $t->get_ok('/pagination/comment-templates?filter=whatever')->status_is(200)->json_is('/total', 0);
  };

  my $logs = $t->app->log->capture('trace');
  $t->delete_ok("/comment-templates/$id")->status_is(200)->json_is('ok');
  $t->delete_ok("/comment-templates/$id")->status_is(400)->json_is({error => 'Comment template does not exist'});
  like $logs, qr/User "tester" removed comment template "Bundled fonts"/, 'right message';
  undef $logs;

  $t->get_ok('/comment-templates')->status_is(200)->text_like('title', qr/Comment templates/);
  $t->get_ok('/logout')->status_is(302)->header_is(Location => '/');
};

done_testing;
