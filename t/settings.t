# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Mojo::Base -strict, -signatures;

use FindBin;
use lib "$FindBin::Bin/lib";

use Test::More;
use Test::Mojo;
use Cavil::Test;

plan skip_all => 'set TEST_ONLINE to enable this test' unless $ENV{TEST_ONLINE};

my $cavil_test = Cavil::Test->new(online => $ENV{TEST_ONLINE}, schema => 'settings_test');
my $t          = Test::Mojo->new(Cavil => $cavil_test->default_config);
$cavil_test->mojo_fixtures($t->app);
my $app       = $t->app;
my $db        = $app->pg->db;
my $set_roles = sub (@roles) { $db->update('bot_users', {roles => [@roles]}, {login => 'tester'}) };
my $events    = sub ($type) { $db->select('audit_events', '*', {type => $type}, {order_by => 'id'})->expand->hashes };

subtest 'Permission errors' => sub {
  $t->get_ok('/settings/auto-accept')->status_is(403);
  $t->put_ok('/settings/auto-accept.json' => json => {values => {}})->status_is(403);
  $t->post_ok('/settings/excluded-files')->status_is(403);
  $t->get_ok('/pagination/settings/excluded-files')->status_is(403);

  $t->get_ok('/settings')->status_is(401);
  $t->get_ok('/settings/api-keys')->status_is(401);

  $t->get_ok('/login')->status_is(302);
  for my $role (qw(user manager lawyer)) {
    $set_roles->($role);
    $t->get_ok('/settings/auto-accept')->status_is(403);
    $t->get_ok('/settings/auto-accept.json')->status_is(403);
    $t->delete_ok('/settings/excluded-files/1')->status_is(403);
    $t->get_ok('/settings')->status_is(302)->header_is(Location => '/settings/api-keys');
    $t->get_ok('/settings/api-keys')->status_is(200);
  }

  $t->get_ok('/settings/api-keys')
    ->content_like(qr/setupSettings\('api-keys', false, true\)/, 'lawyers also see comment templates');
  $t->get_ok('/settings/comment-templates')->status_is(200);
  $set_roles->('user');
  $t->get_ok('/settings/api-keys')
    ->content_like(qr/setupSettings\('api-keys', false, false\)/, 'everybody else only their own keys');
  $t->get_ok('/settings/comment-templates')->status_is(403);
  $t->get_ok('/api_keys')->status_is(302)->header_is(Location => '/settings/api-keys');
  $set_roles->('admin');
};

subtest 'Pages' => sub {
  $t->get_ok('/settings')->status_is(302)->header_is(Location => '/settings/api-keys');
  $t->get_ok('/settings/auto-accept')->status_is(200)->content_like(qr/setupSettings\('auto-accept', true, true\)/);
  $t->get_ok('/settings/excluded-files')
    ->status_is(200)
    ->content_like(qr/setupSettings\('excluded-files', true, true\)/);
  $t->get_ok('/settings/nothing')->status_is(404);
};

subtest 'Registry' => sub {
  my $settings = $app->settings;
  my $defaults = $settings->defaults;
  is_deeply $defaults,
    {
    acceptable_risk     => 4,
    auto_accept_risk    => 2,
    acceptable_packages => [qw(000product 000release-packages 000package-groups)],
    sbom_creator_name   => '',
    sbom_creator_email  => '',
    sbom_creator_url    => ''
    },
    'defaults match the old configuration';
  is $settings->value('auto_accept_risk'), 0, 'test harness override';
  is $settings->value('acceptable_risk'),  4, 'default without a row';
  eval { $settings->value('acceptable_rsk') };
  like $@, qr/Unknown setting: acceptable_rsk/, 'typo dies';

  $db->insert('settings', {name => 'retired_setting', value => {-json => 1}});
  is_deeply [sort keys %{$settings->get}], [sort keys %$defaults], 'rows for settings that no longer exist are ignored';
  is_deeply $settings->update('tester', {retired_setting => 2})->{errors}, {retired_setting => 'Unknown setting'},
    'unknown settings cannot be changed';

  $db->insert('settings', {name => 'acceptable_risk', value => {-json => 'high'}});
  eval { $settings->get };
  like $@, qr/Stored setting acceptable_risk is invalid/, 'invalid stored value dies instead of using the default';
  eval { $settings->value('acceptable_risk') };
  like $@, qr/Stored setting acceptable_risk is invalid/, 'for single values too';
  $db->delete('settings', {name => [qw(acceptable_risk retired_setting)]});
};

subtest 'Read and update' => sub {
  $t->get_ok('/settings/auto-accept.json')
    ->status_is(200)
    ->json_is('/values/auto_accept_risk',   0)
    ->json_is('/values/acceptable_risk',    4)
    ->json_is('/defaults/auto_accept_risk', 2)
    ->json_is('/custom',                    ['auto_accept_risk'])
    ->json_is('/last_change',               undef);

  $t->put_ok('/settings/auto-accept.json' => json => {values => {acceptable_risk => 10}})
    ->status_is(400)
    ->json_like('/errors/acceptable_risk', qr/risk level/);
  $t->put_ok('/settings/auto-accept.json' => json => {values => {acceptable_packages => ['two words']}})
    ->status_is(400)
    ->json_like('/errors/acceptable_packages', qr/spaces/);
  $t->put_ok('/settings/auto-accept.json' => json => {values => {nope => 1}})
    ->status_is(400)
    ->json_is('/errors/nope', 'Not part of this section');
  $t->put_ok('/settings/auto-accept.json' => json => {values => {sbom_creator_name => 'ACME'}})
    ->status_is(400)
    ->json_is('/errors/sbom_creator_name', 'Not part of this section');
  $t->put_ok('/settings/auto-accept.json' => json => {values => {auto_accept_risk => 5}})
    ->status_is(400)
    ->json_like('/errors/auto_accept_risk', qr/Cannot be higher/);
  $t->put_ok('/settings/auto-accept.json' => json => [])->status_is(400)->json_is('/error', 'Invalid request');
  is $events->('settings.changed')->size, 0, 'nothing recorded for rejected changes';

  $t->put_ok('/settings/auto-accept.json' => json =>
      {values => {acceptable_packages => [' 000product ', 'foo', 'foo', ''], acceptable_risk => 4}})
    ->status_is(200)
    ->json_is('/values/acceptable_packages', ['000product', 'foo'])
    ->json_is('/values/auto_accept_risk',    0,                                      'other settings untouched')
    ->json_is('/custom', [qw(acceptable_packages acceptable_risk auto_accept_risk)], 'default value is pinned')
    ->json_is('/rechecked',         0)
    ->json_is('/last_change/login', 'tester');
  my $changed = $events->('settings.changed');
  is $changed->size, 1, 'one event';
  is_deeply $changed->last->{data},
    {changes =>
      {acceptable_packages => [[qw(000product 000release-packages 000package-groups)], ['000product', 'foo']]}},
    'only the value that changed is recorded';

  $t->put_ok('/settings/auto-accept.json' => json => {reset => ['acceptable_packages', 'acceptable_risk']})
    ->status_is(200)
    ->json_is('/values/acceptable_packages', [qw(000product 000release-packages 000package-groups)])
    ->json_is('/custom',                     ['auto_accept_risk']);
  is_deeply $events->('settings.changed')->last->{data},
    {
    changes => {acceptable_packages => [['000product', 'foo'], [qw(000product 000release-packages 000package-groups)]]},
    reset   => [qw(acceptable_packages acceptable_risk)]
    },
    'reset recorded, also for the value that did not change';
};

subtest 'Looser settings check open reviews again' => sub {
  $app->minion->enqueue(unpack => [$_]) for 1, 2;
  $app->minion->perform_jobs;
  is $app->packages->find($_)->{state}, 'new', "package $_ waits for a review" for 1, 2;

  $t->put_ok('/settings/auto-accept.json' => json => {values => {acceptable_risk => 3}})
    ->status_is(200)
    ->json_is('/rechecked', 0, 'tightening checks nothing again');

  $t->put_ok('/settings/auto-accept.json' => json => {values => {acceptable_risk => 9, auto_accept_risk => 9}})
    ->status_is(200)
    ->json_is('/rechecked', 2, 'both risk 9 reviews are covered now');
  $app->minion->perform_jobs;
  is $app->packages->find($_)->{state}, 'acceptable', "package $_ accepted" for 1, 2;
  like $app->packages->find(1)->{result}, qr/auto-accept risk threshold \(9\)/, 'by the new threshold';

  $t->put_ok('/settings/auto-accept.json' => json => {values => {acceptable_risk => 4, auto_accept_risk => 0}})
    ->status_is(200)
    ->json_is('/rechecked', 0);
  is $app->packages->find(1)->{state}, 'acceptable', 'tightening never revokes a decision';

  $db->update('bot_packages', {state => 'new', result => undef}, {id => 2});
  $t->put_ok('/settings/auto-accept.json' => json => {values => {acceptable_packages => ['perl-Mojolicious']}})
    ->status_is(200)
    ->json_is('/rechecked', 1, 'added package name');
  $app->minion->perform_jobs;
  is $app->packages->find(2)->{result}, 'Accepted because of package name (perl-Mojolicious)', 'accepted by name';
};

subtest 'Excluded files' => sub {
  $t->get_ok('/pagination/settings/excluded-files')
    ->status_is(200)
    ->json_is('/total',       0)
    ->json_is('/last_change', undef);

  $t->post_ok('/settings/excluded-files' => form => {package_glob => 'rust*',     file => ''})->status_is(400);
  $t->post_ok('/settings/excluded-files' => form => {package_glob => 'two words', file => 'a.tar'})->status_is(400);
  $t->post_ok('/settings/excluded-files' => form => {package_glob => 'gcc{12',    file => 'a.tar'})
    ->status_is(400)
    ->json_is('/error', 'The package pattern is not valid');
  $t->post_ok('/settings/excluded-files' => form => {package_glob => 'gcc', file => 'a|b.tar'})
    ->status_is(400)
    ->json_like('/error', qr/cannot contain/);
  $t->post_ok('/settings/excluded-files' => form => {package_glob => 'gcc{12,13}', file => 'a.tar'})->status_is(200);
  $t->post_ok('/settings/excluded-files' => form => {package_glob => ' rust* ', file => 'r.zip', reason => 'Zip bomb'})
    ->status_is(200);
  $t->post_ok('/settings/excluded-files' => form => {package_glob => 'rust*', file => 'r.zip'})
    ->status_is(400)
    ->json_like('/error', qr/already excluded/);
  $t->post_ok('/settings/excluded-files' => form => {package_glob => 'gcc1?', file => 'huge.bin'})->status_is(200);

  $t->get_ok('/pagination/settings/excluded-files?filter=bomb')
    ->status_is(200)
    ->json_is('/total',               1)
    ->json_is('/page/0/package_glob', 'rust*')
    ->json_is('/page/0/reason',       'Zip bomb')
    ->json_is('/page/0/login',        'tester')
    ->json_is('/last_change/login',   'tester');

  my $exclusions = $app->unpack_exclusions;
  is_deeply $exclusions->for_package('rust1.80'), ['r.zip'],             'glob matches the package family';
  is_deeply $exclusions->for_package('gcc13'),    ['a.tar', 'huge.bin'], 'single character glob';
  is_deeply $exclusions->for_package('gcc'),      [],                    'no match';

  my $id = $db->select('unpack_exclusions', 'id', {file => 'r.zip'})->hash->{id};
  $t->delete_ok("/settings/excluded-files/$id")->status_is(200);
  $t->delete_ok("/settings/excluded-files/$id")->status_is(400);
  is_deeply $exclusions->for_package('rust1.80'), [], 'removed';

  is_deeply [
    map { [$_->{type}, $_->{data}{file}] } $db->query(
      q{SELECT * FROM audit_events
      WHERE type LIKE 'unpack_exclusion.%' ORDER BY id}
    )->expand->hashes->each
    ],
    [
    ['unpack_exclusion.added',   'a.tar'],
    ['unpack_exclusion.added',   'r.zip'],
    ['unpack_exclusion.added',   'huge.bin'],
    ['unpack_exclusion.removed', 'r.zip']
    ],
    'audited';
  $t->get_ok('/pagination/audit?category=settings')->status_is(200)->json_is('/total', 10);
};

subtest 'SBOM creator' => sub {
  $t->get_ok('/settings/sbom.json')
    ->status_is(200)
    ->json_is('/values',         {sbom_creator_name => '', sbom_creator_email => '', sbom_creator_url => ''})
    ->json_is('/fallbacks/name', 'cavil.example.com', 'empty fields show what SBOMs say instead')
    ->json_is('/fallbacks/url',  undef,               'no made up web address')
    ->json_is('/last_change',    undef,               'acceptance changes are not counted for this section')
    ->json_hasnt('/values/acceptable_risk');

  $t->put_ok('/settings/sbom.json' => json => {values => {sbom_creator_email => 'not-an-address'}})
    ->status_is(400)
    ->json_like('/errors/sbom_creator_email', qr/email/);
  $t->put_ok('/settings/sbom.json' => json => {values => {sbom_creator_url => 'ftp://acme.example'}})
    ->status_is(400)
    ->json_like('/errors/sbom_creator_url', qr/web address/);
  $t->put_ok('/settings/sbom.json' => json => {values => {sbom_creator_name => "two\nlines"}})
    ->status_is(400)
    ->json_like('/errors/sbom_creator_name', qr/single line/);
  $t->put_ok('/settings/sbom.json' => json => {values => {auto_accept_risk => 1}})
    ->status_is(400)
    ->json_is('/errors/auto_accept_risk', 'Not part of this section');

  $t->put_ok('/settings/sbom.json' => json =>
      {values => {sbom_creator_name => ' ACME Corp ', sbom_creator_email => 'sbom@acme.example'}})
    ->status_is(200)
    ->json_is('/values/sbom_creator_name', 'ACME Corp')
    ->json_is('/fallbacks/name',           'ACME Corp')
    ->json_is('/rechecked',                0)
    ->json_is('/last_change/login',        'tester');
  is_deeply $app->spdx->creator, {name => 'ACME Corp', email => 'sbom@acme.example', url => undef},
    'SBOMs use the new creator';
  $t->get_ok('/settings/auto-accept.json')->status_is(200)->json_is('/last_change/login', 'tester');
};

subtest 'Bot tokens' => sub {
  my $bot = sub ($token) { {Authorization => "Token $token"} };
  $t->get_ok('/package/1' => $bot->('test_token'))->status_is(200);

  $t->post_ok('/settings/bot-tokens' => form => {description => 'Short', token => 'too-short'})
    ->status_is(400)
    ->json_like('/error', qr/at least 16/);
  $t->post_ok('/settings/bot-tokens' => form => {description => 'Spaces', token => 'has spaces in the token'})
    ->status_is(400);
  $t->post_ok('/settings/bot-tokens' => form => {description => 'OBS bot', token => 'existing-obs-bot-token'})
    ->status_is(200);
  $t->post_ok('/settings/bot-tokens' => form => {description => 'Again', token => 'existing-obs-bot-token'})
    ->status_is(400)
    ->json_like('/error', qr/already exists/);
  $t->post_ok('/settings/bot-tokens' => form => {description => 'Gitea bot', token => ''})->status_is(200);

  $t->get_ok('/settings/bot-tokens.json')
    ->status_is(200)
    ->json_is('/tokens/0/description', 'Gitea bot')
    ->json_like('/tokens/0/token', qr/^[0-9a-f-]{36}$/, 'generated when left empty')
    ->json_is('/tokens/0/login',    'tester')
    ->json_is('/tokens/1/token',    'existing-obs-bot-token')
    ->json_is('/last_change/login', 'tester');
  my $generated = $t->tx->res->json('/tokens/0/token');

  $t->get_ok('/package/1' => $bot->('existing-obs-bot-token'))->status_is(200);
  $t->get_ok('/package/1' => $bot->($generated))->status_is(200);
  $t->get_ok('/package/1' => $bot->('unknown-token-for-the-bot-api'))->status_is(403);
  $t->get_ok('/package/1')->status_is(403);

  my $audit = $db->query(q{SELECT data::text FROM audit_events WHERE type LIKE 'bot_token.%'})->arrays->flatten;
  is $audit->size, 2, 'both tokens audited';
  ok !(grep {/existing-obs-bot-token|\Q$generated\E/} @$audit), 'tokens never end up in the audit log';

  my $id = $db->select('bot_tokens', 'id', {token => 'existing-obs-bot-token'})->hash->{id};
  $t->delete_ok("/settings/bot-tokens/$id")->status_is(200);
  $t->delete_ok("/settings/bot-tokens/$id")->status_is(400);
  $t->get_ok('/package/1' => $bot->('existing-obs-bot-token'))->status_is(403, 'removing a token locks its bot out');

  $db->delete('bot_tokens');
  $t->get_ok('/package/1' => $bot->('test_token'))->status_is(403);
  $t->get_ok('/package/1')->status_is(403, 'without any token the bot API refuses everything');
  $db->insert('bot_tokens', {token => 'test_token'});
};

done_testing;
