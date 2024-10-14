# Copyright (C) 2024 SUSE LLC
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, see <http://www.gnu.org/licenses/>.

use Mojo::Base -strict;

use FindBin;
use lib "$FindBin::Bin/lib";

use Test::More;
use Test::Mojo;
use Cavil::OBS;
use Cavil::Test;
use Mojolicious::Lite;
use Mojo::File qw(path);

plan skip_all => 'set TEST_ONLINE to enable this test' unless $ENV{TEST_ONLINE};

app->log->level('error');

app->routes->add_condition(
  query => sub {
    my ($route, $c, $captures, $hash) = @_;

    for my $key (keys %$hash) {
      my $values = ref $hash->{$key} ? $hash->{$key} : [$hash->{$key}];
      my $param  = $c->req->url->query->param($key);
      return undef unless defined $param && grep { $param eq $_ } @$values;
    }

    return 1;
  }
);

get '/public/source/:project/perl-Mojolicious.SUSE_SLE-15-SP2_Update' => [project => ['SUSE:Maintenance:4321']] =>
  (query => {view => 'info'})                                         => {text => <<'EOF'};
<sourceinfo package="perl-Mojolicious" rev="69" vrev="1"
  srcmd5="236d7b56886a0d2799c0d114eddbb7ff"
  verifymd5="236d7b56886a0d2799c0d114eddbb7ff">
  <filename>perl-Mojolicious.spec</filename>
</sourceinfo>
EOF

get '/public/source/:project/perl-Mojolicious.SUSE_SLE-15-SP2_Update' => [project => ['SUSE:Maintenance:4321']] =>
  (query => {expand => 1})                                            => {text => <<'EOF'};
<directory name="perl-Mojolicious.SUSE_SLE-15-SP2_Update" rev="4bf9ea937901cae5816321f8ebbf2ee1"
  vrev="160" srcmd5="4bf9ea937901cae5816321f8ebbf2ee1">
  <linkinfo project="openSUSE:Factory" package="perl-Mojolicious.SUSE_SLE-15-SP2_Update"
    srcmd5="236d7b56886a0d2799c0d114eddbb7ff"
    baserev="236d7b56886a0d2799c0d114eddbb7ff"
    lsrcmd5="cdfae5a75f3bd8e404788e65b0338184" />
  <entry name="Mojolicious-7.25.tar.gz" md5="c1ffb4256878c64eb0e40c48f36d24d2"
    size="675142" mtime="1496988144" />
  <entry name="perl-Mojolicious.changes" md5="46c99c12bdce7adad475de28916975ef"
    size="81924" mtime="1496988145" />
  <entry name="perl-Mojolicious.spec" md5="4d480d6329a7ea52f7bb3a479d72b8fe"
    size="2420" mtime="1496988145" />
</directory>
EOF

get '/public/source/:project/perl-Mojolicious.SUSE_SLE-15-SP2_Update/_meta' =>
  [project => ['SUSE:Maintenance:4321']] => {text => <<'EOF'};
<package name="perl-Mojolicious.SUSE_SLE-15-SP2_Update" project="SUSE:Maintenance:4321">
  <title>Job Queue</title>
  <description>Test package</description>
  <devel project="SUSE:Maintenance:4321" package="perl-Mojolicious" />
  <url>http://search.cpan.org/dist/Minion</url>
</package>
EOF

my @files = qw(Mojolicious-7.25.tar.gz perl-Mojolicious.changes perl-Mojolicious.spec);
get("/public/source/:project/perl-Mojolicious.SUSE_SLE-15-SP2_Update//$_" => [project => ['SUSE:Maintenance:4321']] =>
    {data => path(__FILE__)->sibling('legal-bot', 'perl-Mojolicious', 'c7cfdab0e71b0bebfdf8b2dc3badfecd', $_)->slurp})
  for @files;

get '/public/request/4321' => {text => <<'EOF'};
<request id="4321" creator="test2">
  <action type="maintenance_release">
    <source project="SUSE:Maintenance:4321" package="perl-Mojolicious.SUSE_SLE-15-SP2_Update"
      rev="961b20692bc317a3c6ab3166312425da"/>
    <target project="SUSE:SLE-15-SP2:Update" package="perl-Mojolicious.33127"/>
  </action>
  <description>requesting release</description>
</request>
EOF

get '/public/source/:project/_attribute' => [project => 'SUSE:Maintenance:4321'] => {text => <<'EOF'};
<attributes>
  <attribute name="EmbargoDate" namespace="OBS">
    <value>2024-03-27 07:00 UTC</value>
  </attribute>
</attributes>
EOF

get '/*whatever' => {whatever => ''} => {text => '', status => 404};

my $cavil_test = Cavil::Test->new(online => $ENV{TEST_ONLINE}, schema => 'embargo_test');
my $t          = Test::Mojo->new(Cavil => $cavil_test->default_config);
$cavil_test->embargo_fixtures($t->app);
my $dir = $cavil_test->checkout_dir;

# Connect mock web service
my $mock_app = app;
my $api      = 'http://127.0.0.1:' . $t->app->obs->ua->server->app($mock_app)->url->port;

subtest 'Embargoed package does not existy yet' => sub {
  $t->get_ok('/package/3' => {Authorization => 'Token test_token'})->status_is(404)->content_like(qr/No such package/);
};

subtest 'Existing packages are not embargoed' => sub {
  $t->get_ok('/package/1' => {Authorization => 'Token test_token'})->status_is(200)->json_is('/embargoed', 0);
  $t->get_ok('/package/2' => {Authorization => 'Token test_token'})->status_is(200)->json_is('/embargoed', 0);
};

subtest 'Embargoed packages' => sub {
  my $form = {
    api           => $api,
    package       => 'perl-Mojolicious.SUSE_SLE-15-SP2_Update',
    project       => 'SUSE:Maintenance:4321',
    external_link => 'ibs#4321'
  };
  $t->app->minion->on(
    worker => sub {
      my ($minion, $worker) = @_;
      $worker->on(
        dequeue => sub {
          my ($worker, $job) = @_;
          $job->on(
            start => sub {
              my $job  = shift;
              my $task = $job->task;
              return unless $task eq 'obs_import' || $task eq 'obs_embargo';
              $job->app->obs(Cavil::OBS->new);
              my $api = 'http://127.0.0.1:' . $job->app->obs->ua->server->app($mock_app)->url->port;
              $job->args->[1]{api} = $api;
            }
          );
        }
      );
    }
  );

  subtest 'Create package with embargo (detected via OBS API)' => sub {
    $t->post_ok('/packages' => {Authorization => 'Token test_token'} => form => $form)->status_is(200)
      ->json_is('/saved/checkout_dir', '236d7b56886a0d2799c0d114eddbb7ff')->json_is('/saved/id', 3);
    $t->get_ok('/package/3/report' => {Authorization => 'Token test_token'})->status_is(408)
      ->content_like(qr/package being processed/);
    $t->get_ok('/api/1.0/source' => form => $form)->status_is(200)->json_is('/review' => 3, '/history' => []);
    $t->app->minion->perform_jobs;
    my $checkout = $dir->child('perl-Mojolicious.SUSE_SLE-15-SP2_Update', '236d7b56886a0d2799c0d114eddbb7ff');
    ok -d $checkout,                                    'directory exists';
    ok -f $checkout->child('Mojolicious-7.25.tar.gz'),  'file exists';
    ok -f $checkout->child('perl-Mojolicious.changes'), 'file exists';
    ok -f $checkout->child('perl-Mojolicious.spec'),    'file exists';
    ok !-d $checkout->child('Mojolicious'),             'directory does not exist yet';
  };

  subtest 'Embargoed package has been created' => sub {
    $t->get_ok('/package/3' => {Authorization => 'Token test_token'})->status_is(200)->json_is('/state', 'new')
      ->json_is('/priority', 5)->json_is('/embargoed', 1)->json_is('/external_link', 'ibs#4321');
    $t->get_ok('/package/3/report' => {Authorization => 'Token test_token'})->status_is(200)
      ->content_type_like(qr/application\/json/)->json_is('/package/checkout_dir', '236d7b56886a0d2799c0d114eddbb7ff')
      ->json_has('/report/risks');
    $t->get_ok('/source/3' => {Authorization => 'Token test_token'})->status_is(200)
      ->content_type_like(qr/application\/json/)->json_has('/source/filename');
  };

  subtest 'Check embargo status on re-import' => sub {
    $t->app->packages->obsolete_if_not_in_product(3);
    is $t->app->minion->jobs({tasks => ['obs_import']})->total,  1, 'one import job';
    is $t->app->minion->jobs({tasks => ['obs_embargo']})->total, 0, 'no embargo jobs';

    $t->post_ok('/packages' => {Authorization => 'Token test_token'} => form => $form)->status_is(200)
      ->json_is('/saved/checkout_dir', '236d7b56886a0d2799c0d114eddbb7ff')->json_is('/saved/id', 3);
    $t->app->minion->perform_jobs;
    $t->post_ok('/packages/import/3' => {Authorization => 'Token test_token'} => form => {state => 'new'})
      ->status_is(200)->json_is('/imported/id', 3)->json_is('/imported/state', 'new');
    $t->get_ok('/package/3' => {Authorization => 'Token test_token'})->status_is(200)->json_is('/state', 'new')
      ->json_is('/priority', 5)->json_is('/embargoed', 1)->json_is('/external_link', 'ibs#4321');
    is $t->app->minion->jobs({tasks => ['obs_import']})->total,  1, 'one import job';
    is $t->app->minion->jobs({tasks => ['obs_embargo']})->total, 1, 'one embargo job';
  };
};

subtest 'Embargoed snippets' => sub {
  subtest 'Unembargoed snippet does not become embargoed again' => sub {
    my $unembargoed_snippet = $t->app->snippets->find_or_create(
      {hash => 'manual:236d7b56836a4d2759c061147dd8b7ab', text => 'This is an embargo test', package => 1});
    is $t->app->pg->db->select('snippets', '*', {id => $unembargoed_snippet})->hash->{package}, 1,
      'linked to unembargoed package';
    is $t->app->snippets->find_or_create(
      {hash => 'manual:236d7b56836a4d2759c061147dd8b7ab', text => 'This is an embargo test', package => 3}),
      $unembargoed_snippet, 'no new snippet created';
    is $t->app->pg->db->select('snippets', '*', {id => $unembargoed_snippet})->hash->{package}, 1,
      'still linked to unembargoed package';
  };

  subtest 'Package specific snippets are embargoed' => sub {
    $t->get_ok('/login')->status_is(302)->header_is(Location => '/');

    $t->get_ok('/snippets/meta?confidence=100&isClassified=false&isApproved=false&isLegal=true&notLegal=true')
      ->status_is(200)->json_is('/snippets/0/embargoed', 0)->json_like('/snippets/0/text', qr/This is an embargo test/)
      ->json_is('/snippets/1/package', 3)->json_is('/snippets/1/embargoed', 1)
      ->json_like('/snippets/1/text', qr/added EXPERIMENTAL support for IPv6/)->json_is('/snippets/2/package', 3)
      ->json_is('/snippets/2/embargoed', 1)->json_like('/snippets/2/text', qr/added EXPERIMENTAL xml attribute/);

    $t->get_ok('/logout')->status_is(302)->header_is(Location => '/');
  };

  subtest 'Embargoed snippets become unembargoed when they are referenced by unembargoed packages' => sub {
    $t->get_ok('/login')->status_is(302)->header_is(Location => '/');

    subtest 'Snippets are linked to first unembargoed package' => sub {
      ok $t->app->packages->unpack(1), 'indexing first unembargoed package';
      ok $t->app->packages->unpack(2), 'indexing second unembargoed package';
      $t->app->minion->perform_jobs;
      $t->get_ok('/snippets/meta?confidence=100&isClassified=false&isApproved=false&isLegal=true&notLegal=true')
        ->status_is(200)->json_is('/snippets/0/embargoed', 0)
        ->json_like('/snippets/0/text', qr/This is an embargo test/)->json_is('/snippets/1/package', 1)
        ->json_is('/snippets/1/filepackage', 2)->json_is('/snippets/1/embargoed', 0)
        ->json_like('/snippets/1/text', qr/added EXPERIMENTAL support for IPv6/)->json_is('/snippets/2/package', 1)
        ->json_is('/snippets/2/filepackage', 2)->json_is('/snippets/2/embargoed', 0)
        ->json_like('/snippets/2/text', qr/added EXPERIMENTAL xml attribute/);
      $t->get_ok('/snippets/meta?before=5&onfidence=100&isClassified=false&isApproved=false&isLegal=true&notLegal=true')
        ->status_is(200)->json_is('/total', 4);
    };

    $t->get_ok('/logout')->status_is(302)->header_is(Location => '/');
  };
};

done_testing;
