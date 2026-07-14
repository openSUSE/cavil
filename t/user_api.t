# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Mojo::Base -strict;

use FindBin;
use lib "$FindBin::Bin/lib";

use Test::More;
use Test::Mojo;
use Cavil::Test;
use Mojo::File qw(path);
use Mojo::Date;
use Mojo::JSON qw(true false);

plan skip_all => 'set TEST_ONLINE to enable this test' unless $ENV{TEST_ONLINE};

my $cavil_test = Cavil::Test->new(online => $ENV{TEST_ONLINE}, schema => 'user_api_test');
my $t          = Test::Mojo->new(Cavil => $cavil_test->default_config);
$cavil_test->mojo_fixtures($t->app);

# Add patterns for known incompatible licenses
$t->app->patterns->create(pattern => 'SPDX-License-Identifier: Apache-2.0',   license => 'Apache-2.0');
$t->app->patterns->create(pattern => 'SPDX-License-Identifier: GPL-2.0-only', license => 'GPL-2.0-only');
$t->app->pg->db->query('UPDATE license_patterns SET spdx = $1 WHERE license = $1', $_) for qw(Apache-2.0 GPL-2.0-only);

# Add licenses for prediction
$t->app->patterns->create(pattern => 'SPDX-License-Identifier: LGPL-2.1-or-later', license => 'LGPL-2.1-or-later');
$t->app->patterns->create(pattern => 'SPDX-License-Identifier: MPL-2.0-only',      license => 'MPL-2.0-only');
$t->app->patterns->create(pattern => 'SPDX-License-Identifier: MPL-2.0-or-later',  license => 'MPL-2.0-or-later');
$t->app->patterns->create(
  pattern => 'SPDX-License-Identifier: MIT AND LGPL-2.1-or-later',
  license => 'MIT AND LGPL-2.1-or-later'
);
$t->app->patterns->create(
  pattern => 'SPDX-License-Identifier: MIT AND MPL-2.0-only',
  license => 'MIT AND MPL-2.0-only'
);
$t->app->patterns->create(
  pattern => 'SPDX-License-Identifier: MIT AND MPL-2.0-or-later',
  license => 'MIT AND MPL-2.0-or-later'
);
$t->app->patterns->create(
  pattern => 'SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0',
  license => 'GPL-2.0-only WITH Classpath-exception-2.0'
);

# Add files with incompatible licenses
my $pkg = $t->app->packages->find(1);
my $dir = path($cavil_test->checkout_dir, $pkg->{name}, $pkg->{checkout_dir});
$dir->child('apache_file.txt')->spurt("# SPDX-License-Identifier: Apache-2.0\n\nThis is a test file.\n");
$dir->child('gpl2_file.txt')->spurt("# SPDX-License-Identifier: GPL-2.0-only\n\nThis is another test file.\n");

# Unpack and index
$t->app->minion->enqueue(unpack => [1]);
$t->app->minion->perform_jobs;

subtest 'API keys' => sub {
  my $key           = '';
  my $expires_epoch = time + 36000;
  my $expires       = Mojo::Date->new($expires_epoch)->to_datetime =~ s/:\d{2}Z$//r;

  subtest 'Create API key' => sub {
    $t->get_ok('/login')->status_is(302)->header_is(Location => '/');

    $t->post_ok('/api_keys' => form => {expires => $expires, type => 'read-only', description => 'Test key'})
      ->status_is(200)
      ->json_is('/created' => 1);
    $t->get_ok('/api_keys/meta')
      ->status_is(200)
      ->json_is('/keys/0/id'    => 1)
      ->json_is('/keys/0/owner' => 2)
      ->json_like('/keys/0/api_key' => qr/^[a-f0-9\-]{20,}$/i)
      ->json_is('/keys/0/description'          => 'Test key')
      ->json_is('/keys/0/write_access'         => 0)
      ->json_is('/keys/0/can_finalize_reviews' => 0)
      ->json_has('/keys/0/expires_epoch');
    $key = $t->tx->res->json('/keys/0/api_key');

    $t->get_ok('/logout')->status_is(302)->header_is(Location => '/');
  };

  subtest 'can_finalize_reviews flag respects type and explicit opt-in' => sub {
    $t->get_ok('/login')->status_is(302);

    # Read-only key with the flag asserted true: flag must be coerced off.
    $t->post_ok('/api_keys' => form =>
        {expires => $expires, type => 'read-only', description => 'RO with flag attempt', can_finalize_reviews => '1'})
      ->status_is(200);

    # Read-write key without the flag: default off.
    $t->post_ok('/api_keys' => form => {expires => $expires, type => 'read-write', description => 'RW default'})
      ->status_is(200);

    # Read-write key with the explicit opt-in: flag on.
    $t->post_ok('/api_keys' => form =>
        {expires => $expires, type => 'read-write', description => 'RW with finalize', can_finalize_reviews => '1'})
      ->status_is(200);

    $t->get_ok('/api_keys/meta')->status_is(200);
    my $keys    = $t->tx->res->json('/keys');
    my %by_desc = map { $_->{description} => $_ } @$keys;
    is $by_desc{'RO with flag attempt'}{can_finalize_reviews}, 0, 'read-only ignores opt-in';
    is $by_desc{'RO with flag attempt'}{write_access},         0, 'still read-only';
    is $by_desc{'RW default'}{can_finalize_reviews},           0, 'read-write defaults off';
    is $by_desc{'RW default'}{write_access},                   1, 'is read-write';
    is $by_desc{'RW with finalize'}{can_finalize_reviews},     1, 'opt-in respected';

    # Cleanup so other subtests still see a known key set.
    for my $k (@$keys) {
      next if $k->{description} eq 'Test key';
      $t->delete_ok("/api_keys/$k->{id}")->status_is(200);
    }

    $t->get_ok('/logout')->status_is(302);
  };

  subtest 'Access API without key' => sub {
    $t->get_ok('/api/v1/whoami')
      ->status_is(403)
      ->json_is('/error' => 'It appears you have insufficient permissions for accessing this resource');
    $t->get_ok('/api/v1/reports')
      ->status_is(403)
      ->json_is('/error' => 'It appears you have insufficient permissions for accessing this resource');
    $t->get_ok('/api/v1/report/1.json')
      ->status_is(403)
      ->json_is('/error' => 'It appears you have insufficient permissions for accessing this resource');
    $t->get_ok('/api/v1/report/1.txt')
      ->status_is(403)
      ->json_is('/error' => 'It appears you have insufficient permissions for accessing this resource');
    $t->get_ok('/api/v1/report/1.mcp')
      ->status_is(403)
      ->json_is('/error' => 'It appears you have insufficient permissions for accessing this resource');
    $t->get_ok('/api/v1/spdx/1')
      ->status_is(403)
      ->json_is('/error' => 'It appears you have insufficient permissions for accessing this resource');
  };

  subtest 'Access API with key' => sub {
    $t->get_ok('/api/v1/whoami' => {Authorization => "Bearer $key"})
      ->status_is(200)
      ->json_is('/id', 2)
      ->json_is('/user'         => 'tester')
      ->json_is('/roles'        => ['admin', 'classifier', 'manager'])
      ->json_is('/write_access' => false);
  };

  subtest 'Access reports with API key' => sub {
    $t->get_ok('/api/v1/report/1.json' => {Authorization => "Bearer $key"})
      ->status_is(200)
      ->json_is('/package/id'                      => 1)
      ->json_is('/package/checkout_dir'            => 'c7cfdab0e71b0bebfdf8b2dc3badfecd')
      ->json_is('/report/licenses/Apache-2.0/spdx' => 'Apache-2.0');

    $t->get_ok('/api/v1/report/1.txt' => {Authorization => "Bearer $key"})
      ->status_is(200)
      ->content_like(qr/Package:.+perl-Mojolicious/)
      ->content_like(qr/Checkout:.+c7cfdab0e71b0bebfdf8b2dc3badfecd/)
      ->content_like(qr/Unpacked:.+files/)
      ->content_like(qr/Apache-2.0:.+3 files/);

    $t->get_ok('/api/v1/report/1.mcp' => {Authorization => "Bearer $key"})
      ->status_is(200)
      ->content_like(qr/Package:.+perl-Mojolicious/)
      ->content_like(qr/Checkout:.+c7cfdab0e71b0bebfdf8b2dc3badfecd/)
      ->content_like(qr/Apache-2.0:.+3 files/)
      ->content_like(qr/## Unmatched Snippets/)
      ->content_like(qr/^\* \d+x snippet \d+ /m)
      ->content_like(qr/cavil_search_snippets\(package_id=1\)/);
  };

  subtest 'Access SPDX with API key' => sub {
    $t->get_ok('/api/v1/spdx/1' => {Authorization => "Bearer $key"})
      ->status_is(408)
      ->content_like(qr/Your SPDX report is being generated/)
      ->content_unlike(qr/<nav>/);
    $t->get_ok('/api/v1/spdx/1' => {Authorization => "Bearer $key"})
      ->status_is(408)
      ->content_like(qr/Your SPDX report is being generated/)
      ->content_unlike(qr/<nav>/);
    $t->app->minion->perform_jobs;
    $t->get_ok('/api/v1/spdx/1' => {Authorization => "Bearer $key"})
      ->status_is(200)
      ->content_type_is('application/json')
      ->json_is('/@context' => 'https://spdx.org/rdf/3.0.1/spdx-context.jsonld');
  };

  subtest 'List reports by external link' => sub {
    subtest 'Find by open request link' => sub {
      $t->post_ok(
        '/requests' => {Authorization => 'Token test_token'} => form => {external_link => 'obs#123', package => 2})
        ->status_is(200)
        ->json_is('/created', 'obs#123');
      $t->post_ok(
        '/requests' => {Authorization => 'Token test_token'} => form => {external_link => 'obs#123', package => 1})
        ->status_is(200)
        ->json_is('/created', 'obs#123');
      $t->get_ok('/api/v1/reports' => {Authorization => "Bearer $key"} => form => {external_link => 'obs#123'})
        ->status_is(200)
        ->json_is('/reports/0/id', 1)
        ->json_is('/reports/1/id', 2)
        ->json_hasnt('/reports/2');
      $t->delete_ok('/requests' => {Authorization => 'Token test_token'} => form => {external_link => 'obs#123'})
        ->status_is(200);
    };

    subtest 'Find by package link' => sub {
      subtest 'Not obsolete' => sub {
        $t->app->pg->db->query('UPDATE bot_packages SET obsolete = false WHERE id = 1');
        $t->get_ok('/api/v1/reports' => {Authorization => "Bearer $key"} => form => {external_link => 'mojo#1'})
          ->status_is(200)
          ->json_is('/reports/0/id', 1)
          ->json_hasnt('/reports/1');
      };

      subtest 'Obsolete' => sub {
        $t->app->pg->db->query('UPDATE bot_packages SET obsolete = true WHERE id = 1');
        $t->get_ok('/api/v1/reports' => {Authorization => "Bearer $key"} => form => {external_link => 'mojo#1'})
          ->status_is(200)
          ->json_hasnt('/reports/0');
        $t->app->pg->db->query('UPDATE bot_packages SET obsolete = false WHERE id = 1');
      };
    };

    subtest 'Find by mixed links' => sub {
      $t->post_ok(
        '/requests' => {Authorization => 'Token test_token'} => form => {external_link => 'mojo#1', package => 1})
        ->status_is(200)
        ->json_is('/created', 'mojo#1');
      $t->get_ok('/api/v1/reports' => {Authorization => "Bearer $key"} => form => {external_link => 'mojo#1'})
        ->status_is(200)
        ->json_is('/reports/0/id', 1)
        ->json_hasnt('/reports/1');
      $t->delete_ok('/requests' => {Authorization => 'Token test_token'} => form => {external_link => 'mojo#1'})
        ->status_is(200);
    };
  };

  subtest 'API keys from multiple users' => sub {
    my $key = $t->app->api_keys->create(owner => 1, description => 'Other user key', type => 'read-write',
      expires => $expires);

    $t->get_ok('/login')->status_is(302)->header_is(Location => '/');
    $t->get_ok('/api_keys/meta')
      ->status_is(200)
      ->json_is('/keys/0/id'    => 1)
      ->json_is('/keys/0/owner' => 2)
      ->json_hasnt('/keys/1');
    $t->get_ok('/logout')->status_is(302)->header_is(Location => '/');

    $t->get_ok('/api/v1/whoami' => {Authorization => "Bearer $key->{api_key}"})
      ->status_is(200)
      ->json_is('/id', 1)
      ->json_is('/user'         => 'test_bot')
      ->json_is('/roles'        => ['user'])
      ->json_is('/write_access' => true);
  };

  subtest 'Expired API key' => sub {
    $t->app->pg->db->query("UPDATE api_keys SET expires = NOW() - INTERVAL '1 hour' WHERE api_key = ?", $key);
    $t->get_ok('/api/v1/whoami' => {Authorization => "Bearer $key"})
      ->status_is(403)
      ->json_is('/error' => 'It appears you have insufficient permissions for accessing this resource');

    $t->app->pg->db->query("UPDATE api_keys SET expires = NOW() + INTERVAL '10 hours' WHERE api_key = ?", $key);
    $t->get_ok('/api/v1/whoami' => {Authorization => "Bearer $key"})
      ->status_is(200)
      ->json_is('/id', 2)
      ->json_is('/user' => 'tester');
  };

  subtest 'Remove API key' => sub {
    $t->get_ok('/login')->status_is(302)->header_is(Location => '/');

    $t->delete_ok('/api_keys/1')->status_is(200)->json_is('/removed' => 1);
    $t->get_ok('/api/v1/whoami' => {Authorization => "Bearer $key"})
      ->status_is(403)
      ->json_is('/error' => 'It appears you have insufficient permissions for accessing this resource');

    $t->get_ok('/logout')->status_is(302)->header_is(Location => '/');
  };

  subtest 'Removing another users keys is not allowed' => sub {
    $t->get_ok('/login')->status_is(302)->header_is(Location => '/');
    $t->delete_ok('/api_keys/2')->status_is(200)->json_is('/removed' => 0);
    $t->get_ok('/logout')->status_is(302)->header_is(Location => '/');
  }
};

subtest 'License prediction' => sub {
  subtest 'Exact matches' => sub {
    my $exact = $t->app->patterns->closest_licenses('GPL-2.0-only');
    is $exact->{exact}{license}, 'GPL-2.0-only', 'exact identifier match returns -only license';

    $exact = $t->app->patterns->closest_licenses('LGPL-2.1-or-later');
    is $exact->{exact}{license}, 'LGPL-2.1-or-later', 'exact identifier match returns -or-later license';

    $exact = $t->app->patterns->closest_licenses('MPL-2.0+');
    is $exact->{exact}{license}, 'MPL-2.0-or-later', '"+" is treated as the SPDX "-or-later" suffix';

    $exact = $t->app->patterns->closest_licenses('  mit AND   mpl-2.0-only ');
    is $exact->{exact}{license}, 'MIT AND MPL-2.0-only', 'case and whitespace differences still match exactly';
  };

  subtest 'Close matches' => sub {
    my $matches = $t->app->patterns->closest_licenses('MIT LGPL-2.1');
    is_deeply [map { $_->{license} } @{$matches->{closest}}], ['MIT AND LGPL-2.1-or-later', 'LGPL-2.1-or-later'],
      'ranks the compound expression above the bare identifier';

    $matches = $t->app->patterns->closest_licenses('mit lgpl-2.1-or-later');
    is_deeply [map { $_->{license} } @{$matches->{closest}}],
      ['MIT AND LGPL-2.1-or-later', 'LGPL-2.1-or-later', 'MIT AND MPL-2.0-or-later', 'MPL-2.0-or-later'],
      'case-insensitive ranking by trigram similarity';

    $matches = $t->app->patterns->closest_licenses('GPL-2.0 Classpath-exception-2.0');
    is_deeply [map { $_->{license} } @{$matches->{closest}}], ['GPL-2.0-only WITH Classpath-exception-2.0'],
      'ranks the matching WITH-exception license first';

    $matches = $t->app->patterns->closest_licenses('MPL-2.0');
    is_deeply [map { $_->{license} } @{$matches->{closest}}],
      ['MPL-2.0-only', 'MPL-2.0-or-later', 'MIT AND MPL-2.0-only', 'MIT AND MPL-2.0-or-later', 'GPL-2.0-only'],
      'closest standalone identifier ranks ahead of compound expressions';

    $matches = $t->app->patterns->closest_licenses('LicenseRef-MPL-2');
    is_deeply [map { $_->{license} } @{$matches->{closest}}],
      ['MPL-2.0-only', 'MPL-2.0-or-later', 'MIT AND MPL-2.0-only'], 'LicenseRef- prefix is stripped before ranking';

    $matches = $t->app->patterns->closest_licenses('MPL-2-or-later');
    is_deeply [map { $_->{license} } @{$matches->{closest}}],
      ['MPL-2.0-or-later', 'MIT AND MPL-2.0-or-later', 'LGPL-2.1-or-later', 'MIT AND LGPL-2.1-or-later',
      'MPL-2.0-only'], 'ranks the matching -or-later identifier first';

    $matches = $t->app->patterns->closest_licenses('MPL-2+');
    is_deeply [map { $_->{license} } @{$matches->{closest}}],
      ['MPL-2.0-or-later', 'MIT AND MPL-2.0-or-later', 'LGPL-2.1-or-later', 'MIT AND LGPL-2.1-or-later',
      'MPL-2.0-only'], '"+" normalizes to "-or-later" and ranks identically to MPL-2-or-later';

    $matches = $t->app->patterns->closest_licenses('MPL-2-only');
    is_deeply [map { $_->{license} } @{$matches->{closest}}],
      ['MPL-2.0-only', 'MIT AND MPL-2.0-only', 'GPL-2.0-only', 'MPL-2.0-or-later'],
      'ranks the matching -only identifier first';

    $matches = $t->app->patterns->closest_licenses('mpl');
    is_deeply [map { $_->{license} } @{$matches->{closest}}], ['MPL-2.0-only'],
      'a short fragment only matches the closest identifier above threshold';

    $matches = $t->app->patterns->closest_licenses('MIT OR MPL-2.0');
    is_deeply [map { $_->{license} } @{$matches->{closest}}],
      [
      'MIT AND MPL-2.0-or-later',
      'MPL-2.0-or-later',
      'MIT AND MPL-2.0-only',
      'MPL-2.0-only',
      'MIT AND LGPL-2.1-or-later'
      ],
      'suggests the closest known expressions for an unknown OR expression';

    $matches = $t->app->patterns->closest_licenses('MIT AND MPL-2.0');
    is_deeply [map { $_->{license} } @{$matches->{closest}}],
      [
      'MIT AND MPL-2.0-only',
      'MIT AND MPL-2.0-or-later',
      'MPL-2.0-only',
      'MIT AND LGPL-2.1-or-later',
      'MPL-2.0-or-later'
      ],
      'suggests the closest known expressions for an unknown AND expression';
  };

  subtest 'No matches' => sub {
    my $matches = $t->app->patterns->closest_licenses('BSD-2-Clause');
    ok !$matches->{exact}, 'unknown expression has no exact match';
    is_deeply $matches->{closest}, [], 'unknown expression has no close matches';
  };
};

subtest 'Package search API' => sub {
  my $db  = $t->app->pg->db;
  my $usr = $db->select('bot_users', 'id', undef, {limit => 1})->hash->{id};

  my $ro = $t->app->api_keys->create(
    owner       => $usr,
    type        => 'read-only',
    description => 'component search',
    expires     => Mojo::Date->new(time + 36000)->to_datetime
  );
  my $auth = {Authorization => "Bearer $ro->{api_key}"};

  # Two packages that both ship the same vulnerable component; one is embargoed and must stay hidden
  my %common = (api_url => 'https://api.opensuse.org', requesting_user => $usr, project => 'devel:test', priority => 5);
  my $clean  = $t->app->packages->add(
    %common,
    name         => 'security-clean',
    package      => 'security-clean',
    checkout_dir => 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    srcmd5       => 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
  );
  my $emb = $t->app->packages->add(
    %common,
    name         => 'security-embargoed',
    package      => 'security-embargoed',
    checkout_dir => 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
    srcmd5       => 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
  );
  $db->update('bot_packages', {embargoed => 1}, {id => $emb});

  # A third package that also ships the component but is obsolete (superseded) - must also stay hidden
  my $obs = $t->app->packages->add(
    %common,
    name         => 'security-obsolete',
    package      => 'security-obsolete',
    checkout_dir => 'cccccccccccccccccccccccccccccccc',
    srcmd5       => 'cccccccccccccccccccccccccccccccc'
  );
  $db->update('bot_packages', {obsolete => 1}, {id => $obs});

  for my $pid ($clean, $emb, $obs) {
    $db->insert(
      'package_components',
      {
        package => $pid,
        purl    => 'pkg:npm/lodash@4.17.19',
        type    => 'npm',
        name    => 'lodash',
        version => '4.17.19',
        license => 'MIT'
      }
    );
  }

  # A second, non-matching component on the clean package, to prove only matches are attached
  $db->insert(
    'package_components',
    {
      package => $clean,
      purl    => 'pkg:npm/react@18.2.0',
      type    => 'npm',
      name    => 'react',
      version => '18.2.0',
      license => 'MIT'
    }
  );

  subtest 'Requires authentication' => sub {
    $t->get_ok('/api/v1/search' => form => {component => 'lodash'})->status_is(403);
  };

  subtest 'Finds packages by component name, embargoed and obsolete hidden' => sub {
    $t->get_ok('/api/v1/search' => $auth => form => {component => 'lodash'})->status_is(200);
    my $json  = $t->tx->res->json;
    my %by_id = map { $_->{id} => $_ } @{$json->{packages}};
    ok $by_id{$clean}, 'clean package is returned';
    ok !$by_id{$emb},  'embargoed package is not returned even though its component matches';
    ok !$by_id{$obs},  'obsolete package is not returned even though its component matches';
    is_deeply [map { $_->{purl} } @{$by_id{$clean}{components}}], ['pkg:npm/lodash@4.17.19'],
      'only the matching component is attached, with its exact version';
    is $by_id{$clean}{name}, 'security-clean', 'package name in the result';
    ok exists $by_id{$clean}{state},    'state field present';
    ok exists $by_id{$clean}{checksum}, 'checksum field present';
  };

  subtest 'Finds packages by exact purl' => sub {
    $t->get_ok('/api/v1/search' => $auth => form => {component => 'pkg:npm/lodash@4.17.19'})->status_is(200);
    my %by_id = map { $_->{id} => 1 } @{$t->tx->res->json->{packages}};
    ok $by_id{$clean}, 'exact purl finds the package';
  };

  subtest 'Absent component' => sub {
    $t->get_ok('/api/v1/search' => $auth => form => {component => 'no-such-component'})
      ->status_is(200)
      ->json_is('/total'    => 0)
      ->json_is('/packages' => []);
  };

  subtest 'Baseline package search by name (no component)' => sub {
    $t->get_ok('/api/v1/search' => $auth => form => {name => 'security-clean'})->status_is(200);
    my %by_id = map { $_->{id} => $_ } @{$t->tx->res->json->{packages}};
    ok $by_id{$clean}, 'exact package name finds the package';
    is_deeply $by_id{$clean}{components}, [], 'no component query means no components attached';
  };

  subtest 'Embargoed is hidden from a plain name search too' => sub {
    $t->get_ok('/api/v1/search' => $auth => form => {name => 'security-embargoed'})
      ->status_is(200)
      ->json_is('/packages' => []);
  };

  subtest 'No parameters returns a paginated package listing' => sub {
    $t->get_ok('/api/v1/search' => $auth => form => {limit => 5})->status_is(200);
    my $json = $t->tx->res->json;
    ok $json->{total} >= 1,       'returns the package set';
    ok @{$json->{packages}} <= 5, 'respects the limit';
  };

  subtest 'Combining name and component (AND)' => sub {

    # security-clean ships both lodash and react; narrowing by component changes which are attached
    $t->get_ok('/api/v1/search' => $auth => form => {name => 'security-clean', component => 'react'})->status_is(200);
    my $json = $t->tx->res->json;
    is scalar(@{$json->{packages}}), 1,      'name and component both match the clean package';
    is $json->{packages}[0]{id},     $clean, 'the clean package';
    is_deeply [map { $_->{purl} } @{$json->{packages}[0]{components}}], ['pkg:npm/react@18.2.0'],
      'attaches only the queried component';

    # Name matches but the component does not: AND semantics yield nothing
    $t->get_ok('/api/v1/search' => $auth => form => {name => 'security-clean', component => 'no-such'})
      ->status_is(200)
      ->json_is('/total' => 0);
  };

  subtest 'Pagination with limit and offset' => sub {
    my $all = $t->get_ok('/api/v1/search' => $auth => form => {limit => 100})->status_is(200)->tx->res->json;
    ok $all->{total} >= 2, 'at least two visible packages to page through';

    my $p1 = $t->get_ok('/api/v1/search' => $auth => form => {limit => 1, offset => 0})->status_is(200)->tx->res->json;
    my $p2 = $t->get_ok('/api/v1/search' => $auth => form => {limit => 1, offset => 1})->status_is(200)->tx->res->json;
    is scalar(@{$p1->{packages}}), 1,                      'first page holds one package';
    is scalar(@{$p2->{packages}}), 1,                      'second page holds one package';
    isnt $p1->{packages}[0]{id},   $p2->{packages}[0]{id}, 'consecutive pages do not overlap';
    is $p1->{total},               $all->{total},          'total is the full count regardless of the page size';
  };

  subtest 'Invalid parameters are rejected' => sub {
    $t->get_ok('/api/v1/search' => $auth => form => {limit  => 'lots'})->status_is(400);
    $t->get_ok('/api/v1/search' => $auth => form => {offset => 'x'})->status_is(400);
  };
};

done_testing;
