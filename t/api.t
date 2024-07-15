# Copyright (C) 2018-2020 SUSE LLC
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
use Cavil::Test;
use Cavil::OBS;
use Mojo::File qw(path);
use Mojo::Server::Daemon;
use Mojolicious;

plan skip_all => 'set TEST_ONLINE to enable this test' unless $ENV{TEST_ONLINE};

my $cavil_test = Cavil::Test->new(online => $ENV{TEST_ONLINE}, schema => 'api_test');
my $config     = $cavil_test->default_config;
$config->{openid} = {provider => 'https://www.opensuse.org/openid/user/', secret => 's3cret'};
my $t = Test::Mojo->new(Cavil => $config);
$cavil_test->just_patterns_fixtures($t->app);
my $dir = $cavil_test->checkout_dir;

# Mock OBS
my $mock_app = Mojolicious->new;
my $routes   = $mock_app->routes;
$routes->add_condition(
  query => sub {
    my ($route, $c, $captures, $hash) = @_;

    for my $key (keys %$hash) {
      my $param = $c->req->url->query->param($key);
      return undef unless defined $param && $param eq $hash->{$key};
    }

    return 1;
  }
);
$routes->get(
  '/public/source/:project/perl-Mojolicious' => [project => ['devel:languages:perl']] => (query => {view => 'info'}) =>
    {text => <<'EOF'});
<sourceinfo package="perl-Mojolicious" rev="69" vrev="1"
  srcmd5="236d7b56886a0d2799c0d114eddbb7f1"
  verifymd5="236d7b56886a0d2799c0d114eddbb7f1">
  <filename>perl-Mojolicious.spec</filename>
</sourceinfo>
EOF
$routes->get(
  '/public/source/:project/perl-Mojolicious' => [project => ['devel:languages:perl']] => (query => {expand => 1}) =>
    {text => <<'EOF'});
<directory name="perl-Mojolicious" rev="4bf9ea937901cae5816321f8ebbf2ee1"
  vrev="160" srcmd5="4bf9ea937901cae5816321f8ebbf2ee1">
  <linkinfo project="openSUSE:Factory" package="perl-Mojolicious"
    srcmd5="236d7b56886a0d2799c0d114eddbb7f1"
    baserev="236d7b56886a0d2799c0d114eddbb7f1"
    lsrcmd5="cdfae5a75f3bd8e404788e65b0338184" />
  <entry name="Mojolicious-7.25.tar.gz" md5="c1ffb4256878c64eb0e40c48f36d24d2"
    size="675142" mtime="1496988144" />
  <entry name="perl-Mojolicious.changes" md5="46c99c12bdce7adad475de28916975ef"
    size="81924" mtime="1496988145" />
  <entry name="perl-Mojolicious.spec" md5="4d480d6329a7ea52f7bb3a479d72b8fe"
    size="2420" mtime="1496988145" />
</directory>
EOF
$routes->get(
  '/public/source/:project/perl-Mojolicious/_meta' => [project => ['devel:languages:perl']] => {text => <<'EOF'});
<package name="perl-Mojolicious" project="devel:languages:perl">
  <title>The Web In A Box!</title>
  <description>Test package</description>
  <devel project="devel:languages:perl" package="perl-Mojolicious" />
  <url>http://search.cpan.org/dist/Mojolicious</url>
</package>
EOF
my @files = qw(Mojolicious-7.25.tar.gz perl-Mojolicious.changes perl-Mojolicious.spec);
$routes->get("/public/source/:project/perl-Mojolicious/$_" => [project => ['devel:languages:perl']] =>
    {data => path(__FILE__)->sibling('legal-bot', 'perl-Mojolicious', 'c7cfdab0e71b0bebfdf8b2dc3badfecd', $_)->slurp})
  for @files;
my $api = 'http://127.0.0.1:' . $t->app->obs->ua->server->app($mock_app)->url->port;

subtest 'Not authenticated' => sub {
  $t->get_ok('/package/1')->status_is(403)->content_like(qr/permission/);
  $t->patch_ok('/package/1')->status_is(403)->content_like(qr/permission/);
  $t->post_ok('/packages')->status_is(403)->content_like(qr/permission/);
  $t->post_ok('/packages/import/1')->status_is(403)->content_like(qr/permission/);
  $t->patch_ok('/products/Foo')->status_is(403)->content_like(qr/permission/);
  $t->post_ok('/requests')->status_is(403)->content_like(qr/permission/);
  $t->get_ok('/requests')->status_is(403)->content_like(qr/permission/);
  $t->delete_ok('/requests')->status_is(403)->content_like(qr/permission/);
  $t->get_ok('/package/1/report')->status_is(403)->content_like(qr/permission/);
  $t->get_ok('/source/1')->status_is(403)->content_like(qr/permission/);
};

subtest 'Package not created yet' => sub {
  $t->get_ok('/package/1' => {Authorization => 'Token test_token'})->status_is(404)->content_like(qr/No such package/);
  $t->get_ok('/package/1/report' => {Authorization => 'Token test_token'})->status_is(408)
    ->content_like(qr/unknown package/);
  $t->get_ok('/source/1' => {Authorization => 'Token test_token'})->status_is(404)->content_like(qr/unknown file/);
};

subtest 'Create package' => sub {
  my $form = {api => $api, package => 'perl-Mojolicious', project => 'devel:languages:perl'};
  $t->app->patterns->expire_cache;
  $t->post_ok('/packages' => {Authorization => 'Token test_token'} => form => $form)->status_is(200)
    ->json_is('/saved/checkout_dir', '236d7b56886a0d2799c0d114eddbb7f1')->json_is('/saved/id', 1);
  $t->get_ok('/package/1/report' => {Authorization => 'Token test_token'})->status_is(408)
    ->content_like(qr/package being processed/);
  $t->app->minion->on(
    worker => sub {
      my ($minion, $worker) = @_;
      $worker->on(
        dequeue => sub {
          my ($worker, $job) = @_;
          $job->on(
            start => sub {
              my $job = shift;
              return unless $job->task eq 'obs_import';
              $job->app->obs(Cavil::OBS->new);
              my $api = 'http://127.0.0.1:' . $job->app->obs->ua->server->app($mock_app)->url->port;
              $job->args->[1]{api} = $api;
            }
          );
        }
      );
    }
  );
  $t->get_ok('/api/1.0/source' => form => $form)->status_is(200)->json_is('/review' => 1, '/history' => []);
  $t->app->minion->perform_jobs;
  my $checkout = $dir->child('perl-Mojolicious', '236d7b56886a0d2799c0d114eddbb7f1');
  ok -d $checkout,                                    'directory exists';
  ok -f $checkout->child('Mojolicious-7.25.tar.gz'),  'file exists';
  ok -f $checkout->child('perl-Mojolicious.changes'), 'file exists';
  ok -f $checkout->child('perl-Mojolicious.spec'),    'file exists';
  ok !-d $checkout->child('Mojolicious'),             'directory does not exist yet';
};

subtest 'Package has been created' => sub {
  $t->get_ok('/package/1' => {Authorization => 'Token test_token'})->status_is(200)->json_is('/state', 'new')
    ->json_is('/priority', 5);
  $t->get_ok('/package/1/report' => {Authorization => 'Token test_token'})->status_is(200)
    ->content_type_like(qr/application\/json/)->json_is('/package/checkout_dir', '236d7b56886a0d2799c0d114eddbb7f1')
    ->json_has('/report/risks');
  $t->get_ok('/source/1' => {Authorization => 'Token test_token'})->status_is(200)
    ->content_type_like(qr/application\/json/)->json_has('/source/filename');
};

subtest 'Update priority' => sub {
  $t->patch_ok('/package/1' => {Authorization => 'Token test_token'} => form => {priority => 7})->status_is(200);
  $t->get_ok('/package/1' => {Authorization => 'Token test_token'})->status_is(200)->json_is('/state', 'new')
    ->json_is('/priority', 7);
};

subtest 'Request not created yet' => sub {
  $t->get_ok('/requests' => {Authorization => 'Token test_token'})->status_is(200)->json_is('/requests', []);
};

subtest 'Create a requests' => sub {
  $t->post_ok(
    '/requests' => {Authorization => 'Token test_token'} => form => {external_link => 'obs#123', package => 1})
    ->status_is(200)->json_is('/created', 'obs#123');
};

subtest 'Request has been created' => sub {
  $t->get_ok('/requests' => {Authorization => 'Token test_token'})->status_is(200)
    ->json_is('/requests/0/external_link', 'obs#123')->json_is('/requests/0/packages', [1]);
};

subtest 'Remove request again' => sub {
  $t->delete_ok('/requests' => {Authorization => 'Token test_token'} => form => {external_link => 'obs#123'})
    ->status_is(200);
  $t->get_ok('/requests' => {Authorization => 'Token test_token'})->status_is(200)->json_is('/requests', []);
};

subtest 'Products' => sub {
  $t->patch_ok('/products/openSUSE:Factory' => {Authorization => 'Token test_token'} => form => {id => 1})
    ->status_is(200)->json_is('/updated', 1);
  $t->patch_ok('/products/openSUSE:Leap:15.0' => {Authorization => 'Token test_token'} => form => {id => 1})
    ->status_is(200)->json_is('/updated', 2);
  is_deeply $t->app->products->for_package(1), ['openSUSE:Factory', 'openSUSE:Leap:15.0'], 'right products';
};

subtest 'Acceptable risk' => sub {
  is $t->app->reports->risk_is_acceptable(''),                 undef, 'not acceptable';
  is $t->app->reports->risk_is_acceptable('Whatever 123'),     undef, 'not acceptable';
  is $t->app->reports->risk_is_acceptable('Error-9:w6Hs'),     undef, 'not acceptable';
  is $t->app->reports->risk_is_acceptable('GPL-2.0+-9:Hwo6'),  undef, 'not acceptable';
  is $t->app->reports->risk_is_acceptable('GPL-2.0+-10:Hwo6'), undef, 'not acceptable';
  is $t->app->reports->risk_is_acceptable('GPL-2.0+-0:Hwo6'),  0,     'acceptable';
  is $t->app->reports->risk_is_acceptable('Error-0:w6Ht'),     0,     'acceptable';
  is $t->app->reports->risk_is_acceptable('Error-1:w6Ht'),     1,     'acceptable';
  is $t->app->reports->risk_is_acceptable('GPL-2.0+-1:Hwo6'),  1,     'acceptable';
  is $t->app->reports->risk_is_acceptable('GPL-2.0+-2:Hwo6'),  2,     'acceptable';
  is $t->app->reports->risk_is_acceptable('GPL-2.0+-3:Hwo6'),  3,     'acceptable';
  is $t->app->reports->risk_is_acceptable('GPL-2.0+-4:Hwo6'),  undef, 'not acceptable';
};

subtest 'Identify package' => sub {
  $t->get_ok('/api/1.0/identify/perl-Mojolicious/236d7b56886a0d2799c0d114eddbb7f1')->status_is(200)->json_is('/id', 1);
  $t->get_ok('/api/1.0/identify/perl-Test/236d7b56886a0d2799c0d114eddbb7f1')->status_is(404)
    ->json_is('/error', 'Package not found');
  $t->get_ok('/api/1.0/identify/perl-Mojolicious/236d7b56886a0d2799c0d114eddbb7f2')->status_is(404)
    ->json_is('/error', 'Package not found');
};

subtest 'Package status' => sub {
  $t->get_ok('/api/1.0/package/perl-Mojolicious')->status_is(200)->json_is('/package', 'perl-Mojolicious')
    ->json_is('/requests/0/checkout', '236d7b56886a0d2799c0d114eddbb7f1');
};

subtest 'Remove request (but keep packages that are still part of a product)' => sub {
  my $pkgs = $t->app->packages;
  my @ids;
  for my $i (1 .. 5) {
    my $id = $pkgs->add(
      name            => "test-package-$i",
      checkout_dir    => "2a0737e27a3b75590e7fab112b06a76fe757361$i",
      api_url         => 'https://api.opensuse.org',
      requesting_user => 1,
      project         => 'devel:languages:perl',
      package         => "test-package-$i",
      srcmd5          => "2a0737e27a3b75590e7fab112b06a76fe757361$i",
      priority        => 5
    );
    push @ids, $id;
    $pkgs->imported($id);

    $t->post_ok('/requests' => {Authorization => 'Token test_token'} => form =>
        {external_link => 'openSUSE:Test', package => $id})->status_is(200)->json_is('/created', 'openSUSE:Test');
  }

  is $pkgs->find($ids[0])->{state}, 'new', 'right state';
  is $pkgs->find($ids[1])->{state}, 'new', 'right state';
  is $pkgs->find($ids[2])->{state}, 'new', 'right state';
  is $pkgs->find($ids[3])->{state}, 'new', 'right state';
  is $pkgs->find($ids[4])->{state}, 'new', 'right state';

  $t->get_ok('/requests' => {Authorization => 'Token test_token'})->status_is(200)
    ->json_is('/requests/0/packages' => \@ids);

  my @in_product = @ids[0, 2, 4];
  $t->patch_ok('/products/openSUSE:Test' => {Authorization => 'Token test_token'} => form => {id => \@in_product})
    ->status_is(200)->json_is('/updated', 3);
  is_deeply $t->app->products->for_package($ids[0]), ['openSUSE:Test'], 'right products';
  is_deeply $t->app->products->for_package($ids[1]), [],                'right products';
  is_deeply $t->app->products->for_package($ids[2]), ['openSUSE:Test'], 'right products';
  is_deeply $t->app->products->for_package($ids[3]), [],                'right products';
  is_deeply $t->app->products->for_package($ids[4]), ['openSUSE:Test'], 'right products';

  $t->delete_ok('/requests' => {Authorization => 'Token test_token'} => form => {external_link => 'openSUSE:Test'})
    ->status_is(200);
  $t->get_ok('/requests' => {Authorization => 'Token test_token'})->status_is(200)->json_is('/requests', []);

  is $pkgs->find($ids[0])->{state}, 'new',      'right state';
  is $pkgs->find($ids[1])->{state}, 'obsolete', 'right state';
  is $pkgs->find($ids[2])->{state}, 'new',      'right state';
  is $pkgs->find($ids[3])->{state}, 'obsolete', 'right state';
  is $pkgs->find($ids[4])->{state}, 'new',      'right state';
};

subtest 'Pagination' => sub {
  subtest 'Search' => sub {
    $t->get_ok('/pagination/search/perl-Mojolicious')->json_is('/start', 1)->json_is('/end', 1)->json_is('/total', 1)
      ->json_is('/page/0/package', 'perl-Mojolicious')->json_is('/page/0/id', 1)->json_is('/page/0/state', 'obsolete')
      ->json_has('/page/0/checksum')->json_has('/page/0/comment')->json_has('/page/0/user')
      ->json_has('/page/0/created_epoch')->json_has('/page/0/imported_epoch')->json_has('/page/0/indexed_epoch')
      ->json_has('/page/0/unpacked_epoch')->json_is('/page/0/active_jobs' => 0)->json_is('/page/0/failed_jobs' => 0)
      ->json_is('/page/0/unresolved_matches' => 6)->json_hasnt('/page/1');
    $t->get_ok('/pagination/search/perl-Mojolicious?notObsolete=true')->json_is('/start', 1)->json_is('/end', 0)
      ->json_is('/total', 0)->json_hasnt('/page/0');
    $t->get_ok('/pagination/search/perl-Mojolicious?filter=Artistic')->json_is('/start', 1)->json_is('/end', 1)
      ->json_is('/total', 1)->json_is('/page/0/id', 1)->json_hasnt('/page/1');
    $t->get_ok('/pagination/search/perl-Mojolicious?filter=MIT')->json_is('/start', 1)->json_is('/end', 0)
      ->json_is('/total', 0)->json_hasnt('/page/0');
  };

  subtest 'Products' => sub {
    $t->get_ok('/pagination/products/known')->json_is('/start', 1)->json_is('/end', 3)->json_is('/total', 3)
      ->json_is('/page/0/id', 3)->json_is('/page/0/name', 'openSUSE:Test')->json_is('/page/0/new_packages', 3)
      ->json_is('/page/0/reviewed_packages', 0)->json_is('/page/0/unacceptable_packages', 0)->json_hasnt('/page/3');
    $t->get_ok('/pagination/products/known?filter=Factory')->json_is('/start', 1)->json_is('/end', 1)
      ->json_is('/total', 1)->json_is('/page/0/id', 1)->json_hasnt('/page/1');

    $t->get_ok('/pagination/products/openSUSE:Test')->json_is('/start', 1)->json_is('/end', 3)->json_is('/total', 3)
      ->json_is('/page/0/id', 6)->json_is('/page/0/state', 'new')->json_is('/page/0/name', 'test-package-5')
      ->json_has('/page/0/checksum')->json_has('/page/0/imported_epoch')->json_has('/page/0/indexed_epoch')
      ->json_has('/page/0/unpacked_epoch')->json_is('/page/0/active_jobs' => 0)->json_is('/page/0/failed_jobs' => 0)
      ->json_is('/page/0/unresolved_matches' => 0);
    $t->get_ok('/pagination/products/openSUSE:Test?filter=package-3')->json_is('/start', 1)->json_is('/end', 1)
      ->json_is('/total', 1)->json_is('/page/0/id', 4)->json_hasnt('/page/1');

    $t->get_ok('/pagination/products/openSUSE:Test?attention=true')->json_is('/start', 1)->json_is('/end', 3)
      ->json_is('/total', 3)->json_is('/page/0/id', 6)->json_hasnt('/page/3');

    $t->get_ok('/pagination/products/openSUSE:Test?unresolvedMatches=true')->json_is('/start', 1)->json_is('/end', 0)
      ->json_is('/total', 0)->json_hasnt('/page/0');
  };

  subtest 'Licenses' => sub {
    $t->get_ok('/pagination/licenses/known')->json_is('/start', 1)->json_is('/end', 4)->json_is('/total', 4)
      ->json_is('/page/0/license', '')->json_is('/page/0/spdx', '')->json_is('/page/1/license', 'Apache-2.0')
      ->json_is('/page/1/spdx',    '')->json_hasnt('/page/4');
    $t->get_ok('/pagination/licenses/known?filter=Artistic')->json_is('/start', 1)->json_is('/end', 1)
      ->json_is('/total', 1)->json_is('/page/0/license', 'Artistic-2.0')->json_hasnt('/page/1');
  };

  subtest 'Reviews' => sub {
    $t->get_ok('/pagination/reviews/open')->json_is('/start', 1)->json_is('/end', 3)->json_is('/total', 3)
      ->json_is('/page/0/id',   2)->json_is('/page/0/state', 'new')->json_is('/page/0/priority', 5)
      ->json_is('/page/0/name', 'test-package-1')->json_has('/page/0/checksum')->json_has('/page/0/external_link')
      ->json_has('/page/0/created_epoch')->json_has('/page/0/imported_epoch')->json_has('/page/0/indexed_epoch')
      ->json_has('/page/0/unpacked_epoch')->json_is('/page/0/active_jobs' => 0)->json_is('/page/0/failed_jobs' => 0)
      ->json_is('/page/0/unresolved_matches' => 0)->json_hasnt('/page/3');
    $t->get_ok('/pagination/reviews/open?filter=package-3')->json_is('/start', 1)->json_is('/end', 1)
      ->json_is('/total', 1)->json_is('/page/0/id', 4)->json_hasnt('/page/1');
  };
};

done_testing;
