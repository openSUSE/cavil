# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Mojo::Base -strict;

use FindBin;
use lib "$FindBin::Bin/lib";

use Test::More;
use Test::Mojo;
use Cavil::Test;
use Cavil::OBS;
use Cavil::Util qw(incoming_priority md5_file);
use Mojo::File  qw(path tempdir);
use Mojo::JSON  qw(false true);
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
  '/source/:project/perl-Mojolicious' => [project => ['devel:languages:perl']] => (query => {view => 'info'}) =>
    {text => <<'EOF'});
<sourceinfo package="perl-Mojolicious" rev="69" vrev="1"
  srcmd5="236d7b56886a0d2799c0d114eddbb7f1"
  verifymd5="236d7b56886a0d2799c0d114eddbb7f1">
  <filename>perl-Mojolicious.spec</filename>
</sourceinfo>
EOF
$routes->get('/source/:project/perl-Mojolicious' => [project => ['devel:languages:perl']] => (query => {expand => 1}) =>
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
  <entry name="perl-Mojolicious.spec" md5="efab031c960c314a31f39a4a5e68ca50"
    size="2420" mtime="1496988145" />
</directory>
EOF
$routes->get('/source/:project/perl-Mojolicious/_meta' => [project => ['devel:languages:perl']] => {text => <<'EOF'});
<package name="perl-Mojolicious" project="devel:languages:perl">
  <title>The Web In A Box!</title>
  <description>Test package</description>
  <devel project="devel:languages:perl" package="perl-Mojolicious" />
  <url>http://search.cpan.org/dist/Mojolicious</url>
</package>
EOF
my @files = qw(Mojolicious-7.25.tar.gz perl-Mojolicious.changes perl-Mojolicious.spec);
$routes->get("/source/:project/perl-Mojolicious/$_" => [project => ['devel:languages:perl']] =>
    {data => path(__FILE__)->sibling('legal-bot', 'perl-Mojolicious', 'c7cfdab0e71b0bebfdf8b2dc3badfecd', $_)->slurp})
  for @files;
my $api = 'http://127.0.0.1:' . $t->app->obs->ua->server->app($mock_app)->url->port;
$t->app->obs->config({'127.0.0.1' => {user => 'test', password => 'testing'}});

subtest 'Not authenticated' => sub {
  $t->get_ok('/package/1')->status_is(403)->content_like(qr/permission/);
  $t->patch_ok('/package/1')->status_is(403)->content_like(qr/permission/);
  $t->post_ok('/packages')->status_is(403)->content_like(qr/permission/);
  $t->post_ok('/packages/upload')->status_is(403)->content_like(qr/permission/);
  $t->post_ok('/packages/import/1')->status_is(403)->content_like(qr/permission/);
  $t->patch_ok('/products/Foo')->status_is(403)->content_like(qr/permission/);
  $t->post_ok('/requests')->status_is(403)->content_like(qr/permission/);
  $t->get_ok('/requests')->status_is(403)->content_like(qr/permission/);
  $t->delete_ok('/requests')->status_is(403)->content_like(qr/permission/);
  $t->get_ok('/package/1/report')->status_is(403)->content_like(qr/permission/);
  $t->get_ok('/package/1/report.json')->status_is(403)->content_like(qr/permission/);
  $t->get_ok('/package/1/report.txt')->status_is(403)->content_like(qr/permission/);
  $t->get_ok('/source/1')->status_is(403)->content_like(qr/permission/);
};

subtest 'Package not created yet' => sub {
  $t->get_ok('/package/1' => {Authorization => 'Token test_token'})->status_is(404)->content_like(qr/No such package/);
  $t->get_ok('/package/1/report' => {Authorization => 'Token test_token'})
    ->status_is(408)
    ->content_like(qr/unknown package/);
  $t->get_ok('/source/1' => {Authorization => 'Token test_token'})->status_is(404)->content_like(qr/unknown file/);
};

subtest 'Create package' => sub {
  my $form = {api => $api, package => 'perl-Mojolicious', project => 'devel:languages:perl'};
  $t->app->patterns->expire_cache;
  $t->post_ok('/packages' => {Authorization => 'Token test_token'} => form => $form)
    ->status_is(200)
    ->json_is('/saved/checkout_dir', '236d7b56886a0d2799c0d114eddbb7f1')
    ->json_is('/saved/id',           1);

  # Nothing has been indexed yet, which is the only reason there is no report to serve here - the import
  # job being queued is not one
  $t->get_ok('/package/1/report' => {Authorization => 'Token test_token'})
    ->status_is(408)
    ->content_like(qr/not indexed/);
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
              $job->app->obs(Cavil::OBS->new(config => $job->app->obs->config));
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
  $t->get_ok('/package/1' => {Authorization => 'Token test_token'})
    ->status_is(200)
    ->json_is('/state',    'new')
    ->json_is('/priority', 5);
  $t->get_ok('/package/1/report' => {Authorization => 'Token test_token'})
    ->status_is(200)
    ->content_type_like(qr/application\/json/)
    ->json_is('/package/checkout_dir', '236d7b56886a0d2799c0d114eddbb7f1')
    ->json_has('/report/risks');
  $t->get_ok('/package/1/report.json' => {Authorization => 'Token test_token'})
    ->status_is(200)
    ->content_type_like(qr/application\/json/)
    ->json_is('/package/checkout_dir', '236d7b56886a0d2799c0d114eddbb7f1')
    ->json_has('/report/risks');
  for my $field (qw(emails urls)) {
    my $got = $t->tx->res->json("/report/$field");
    is_deeply $got, [sort { $b->[1] <=> $a->[1] || $a->[0] cmp $b->[0] } @$got], "$field stably sorted";
  }
  $t->get_ok('/package/1/report.txt' => {Authorization => 'Token test_token'})
    ->status_is(200)
    ->content_type_like(qr/text\/plain/)
    ->content_like(qr/# Legal Report/)
    ->content_like(qr/Package:.+perl-Mojolicious/)
    ->content_like(qr/Checkout:.+236d7b56886a0d2799c0d114eddbb7f1/)
    ->content_like(qr/Manual review is required because no previous reports are available/)
    ->content_like(qr/### Risk 9 \(Unknown\)/)
    ->content_like(qr/\* .+: 0% similarity to "Keyword", estimated risk 9/)
    ->content_like(qr/### Risk 5 \(Medium\)/)
    ->content_like(qr/\* Apache-2.0: 2 files/)
    ->content_unlike(qr/## Notes/)
    ->content_like(qr/## About/)
    ->content_like(qr/Generated by Cavil\. The HTML and SPDX reports have more detail\./);
  $t->get_ok('/source/1' => {Authorization => 'Token test_token'})
    ->status_is(200)
    ->content_type_like(qr/application\/json/)
    ->json_has('/source/filename');
};

subtest 'Notes in plain text report' => sub {
  my $notes     = $t->app->notes;
  my $tester_id = $t->app->users->find_or_create(login => 'tester',        roles => ['user'])->{id};
  my $lawyer_id = $t->app->users->find_or_create(login => 'report_lawyer', roles => ['lawyer'])->{id};

  # AI-assisted note with a tag, a plain human note, and a lawyer-only note (must never reach the public report)
  $notes->add(1, 'perl-Mojolicious', $tester_id, 'Bundled zlib is fine to redistribute here', 0, 1, ['bundled-code']);
  $notes->add(1, 'perl-Mojolicious', $lawyer_id, 'Confirmed Apache-2.0 headers across the tree',    0, 0);
  $notes->add(1, 'perl-Mojolicious', $lawyer_id, 'Internal-only: escalate to legal before release', 1, 0);

  # Written on another review of the same package name that has since been
  # removed, so it is not relevant to this report and would normally be
  # filtered out. A pin is the reviewer saying it applies to every review.
  my $pinned = $notes->add(undef, 'perl-Mojolicious', $lawyer_id, 'Ships a patented codec, always check', 0, 0);
  $t->get_ok('/package/1/report.txt' => {Authorization => 'Token test_token'})
    ->status_is(200)
    ->content_unlike(qr/Ships a patented codec/);
  $notes->set_pinned($pinned->{id}, 1);

  $t->get_ok('/package/1/report.txt' => {Authorization => 'Token test_token'})
    ->status_is(200)
    ->content_type_like(qr/text\/plain/)
    ->content_like(qr/## Notes/)
    ->content_like(qr/### tester on .+ - AI-assisted - tags: bundled-code/)
    ->content_like(qr/> Bundled zlib is fine to redistribute here/)
    ->content_like(qr/### report_lawyer on /)
    ->content_like(qr/> Confirmed Apache-2\.0 headers across the tree/)
    ->content_like(qr/### report_lawyer on .+ - pinned/)
    ->content_like(qr/> Ships a patented codec, always check/)
    ->content_unlike(qr/Internal-only: escalate to legal/)
    ->content_like(qr/## Notes.+## About/s);

  # A pin does not override the lawyer-only exclusion; these reports are public.
  my $secret = $notes->add(undef, 'perl-Mojolicious', $lawyer_id, 'Pinned but lawyer-only, never public', 1, 0);
  $notes->set_pinned($secret->{id}, 1);
  $t->get_ok('/package/1/report.txt' => {Authorization => 'Token test_token'})
    ->status_is(200)
    ->content_unlike(qr/Pinned but lawyer-only/);
};

subtest 'Update priority' => sub {
  $t->patch_ok('/package/1' => {Authorization => 'Token test_token'} => form => {priority => 7})->status_is(200);
  $t->get_ok('/package/1' => {Authorization => 'Token test_token'})
    ->status_is(200)
    ->json_is('/state',    'new')
    ->json_is('/priority', 7);
};

subtest 'Request not created yet' => sub {
  $t->get_ok('/requests' => {Authorization => 'Token test_token'})->status_is(200)->json_is('/requests', []);
};

subtest 'Create a requests' => sub {
  $t->post_ok(
    '/requests' => {Authorization => 'Token test_token'} => form => {external_link => 'obs#123', package => 1})
    ->status_is(200)
    ->json_is('/created', 'obs#123');
};

subtest 'Request has been created' => sub {
  $t->get_ok('/requests' => {Authorization => 'Token test_token'})
    ->status_is(200)
    ->json_is('/requests/0/external_link', 'obs#123')
    ->json_is('/requests/0/packages',      [1])
    ->json_is('/requests/0/checkouts',     ['236d7b56886a0d2799c0d114eddbb7f1']);
};

subtest 'Remove request again' => sub {
  $t->delete_ok('/requests' => {Authorization => 'Token test_token'} => form => {external_link => 'obs#123'})
    ->status_is(200);
  $t->get_ok('/requests' => {Authorization => 'Token test_token'})->status_is(200)->json_is('/requests', []);
};

subtest 'Products' => sub {
  $t->patch_ok('/products/openSUSE:Factory' => {Authorization => 'Token test_token'} => form => {id => 1})
    ->status_is(200)
    ->json_is('/updated', 1);
  $t->patch_ok('/products/openSUSE:Leap:15.0' => {Authorization => 'Token test_token'} => form => {id => 1})
    ->status_is(200)
    ->json_is('/updated', 2);
  is_deeply $t->app->products->for_package(1), ['openSUSE:Factory', 'openSUSE:Leap:15.0'], 'right products';

  $t->patch_ok('/products/openSUSE:RemoveMe' => {Authorization => 'Token test_token'} => form => {id => 1})
    ->status_is(200)
    ->json_is('/updated', 3);
  $t->delete_ok('/products' => {Authorization => 'Token test_token'} => form => {name => 'openSUSE:RemoveMe'})
    ->status_is(200)
    ->json_is('/removed', 1);
  $t->delete_ok('/products' => {Authorization => 'Token test_token'} => form => {name => 'openSUSE:DoesNotExistAtAll'})
    ->status_is(200)
    ->json_is('/removed', 0);
  $t->delete_ok('/products' => {Authorization => 'Token test_token'})->status_is(400);
  is_deeply $t->app->products->for_package(1), ['openSUSE:Factory', 'openSUSE:Leap:15.0'], 'right products';
};

subtest 'Acceptable risk' => sub {
  is $t->app->reports->risk_is_acceptable(''),                 undef, 'not acceptable';
  is $t->app->reports->risk_is_acceptable('Whatever 123'),     undef, 'not acceptable';
  is $t->app->reports->risk_is_acceptable('Unknown-9:w6Hs'),   undef, 'not acceptable';
  is $t->app->reports->risk_is_acceptable('GPL-2.0+-9:Hwo6'),  undef, 'not acceptable';
  is $t->app->reports->risk_is_acceptable('GPL-2.0+-10:Hwo6'), undef, 'not acceptable';
  is $t->app->reports->risk_is_acceptable('GPL-2.0+-0:Hwo6'),  0,     'acceptable';
  is $t->app->reports->risk_is_acceptable('Unknown-0:w6Ht'),   0,     'acceptable';
  is $t->app->reports->risk_is_acceptable('Unknown-1:w6Ht'),   1,     'acceptable';
  is $t->app->reports->risk_is_acceptable('GPL-2.0+-1:Hwo6'),  1,     'acceptable';
  is $t->app->reports->risk_is_acceptable('GPL-2.0+-2:Hwo6'),  2,     'acceptable';
  is $t->app->reports->risk_is_acceptable('GPL-2.0+-3:Hwo6'),  3,     'acceptable';
  is $t->app->reports->risk_is_acceptable('GPL-2.0+-4:Hwo6'),  4,     'acceptable';
  is $t->app->reports->risk_is_acceptable('GPL-2.0+-5:Hwo6'),  undef, 'not acceptable';
};

subtest 'Identify package' => sub {
  $t->get_ok('/api/1.0/identify/perl-Mojolicious/236d7b56886a0d2799c0d114eddbb7f1')->status_is(200)->json_is('/id', 1);
  $t->get_ok('/api/1.0/identify/perl-Test/236d7b56886a0d2799c0d114eddbb7f1')
    ->status_is(404)
    ->json_is('/error', 'Package not found');
  $t->get_ok('/api/1.0/identify/perl-Mojolicious/236d7b56886a0d2799c0d114eddbb7f2')
    ->status_is(404)
    ->json_is('/error', 'Package not found');
};

subtest 'Package status' => sub {
  $t->get_ok('/api/1.0/package/perl-Mojolicious')
    ->status_is(200)
    ->json_is('/package',             'perl-Mojolicious')
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

  $t->get_ok('/requests' => {Authorization => 'Token test_token'})
    ->status_is(200)
    ->json_is('/requests/0/packages' => \@ids);

  my @in_product = @ids[0, 2, 4];
  $t->patch_ok('/products/openSUSE:Test' => {Authorization => 'Token test_token'} => form => {id => \@in_product})
    ->status_is(200)
    ->json_is('/updated', 4);
  is_deeply $t->app->products->for_package($ids[0]), ['openSUSE:Test'], 'right products';
  is_deeply $t->app->products->for_package($ids[1]), [],                'right products';
  is_deeply $t->app->products->for_package($ids[2]), ['openSUSE:Test'], 'right products';
  is_deeply $t->app->products->for_package($ids[3]), [],                'right products';
  is_deeply $t->app->products->for_package($ids[4]), ['openSUSE:Test'], 'right products';

  $t->delete_ok('/requests' => {Authorization => 'Token test_token'} => form => {external_link => 'openSUSE:Test'})
    ->status_is(200);
  $t->get_ok('/requests' => {Authorization => 'Token test_token'})->status_is(200)->json_is('/requests', []);

  # Packages no longer in a product are flagged obsolete, but their state is
  # preserved as an audit trail (they were never overwritten to "obsolete")
  is $pkgs->find($ids[0])->{state}, 'new', 'right state';
  is $pkgs->find($ids[1])->{state}, 'new', 'right state';
  is $pkgs->find($ids[2])->{state}, 'new', 'right state';
  is $pkgs->find($ids[3])->{state}, 'new', 'right state';
  is $pkgs->find($ids[4])->{state}, 'new', 'right state';
  ok !$pkgs->is_obsolete($ids[0]), 'still in product, not obsolete';
  ok $pkgs->is_obsolete($ids[1]),  'not in product, obsolete';
  ok !$pkgs->is_obsolete($ids[2]), 'still in product, not obsolete';
  ok $pkgs->is_obsolete($ids[3]),  'not in product, obsolete';
  ok !$pkgs->is_obsolete($ids[4]), 'still in product, not obsolete';
};

subtest 'Lawyer rejection survives obsoletion' => sub {
  my $pkgs = $t->app->packages;
  my $id   = $pkgs->add(
    name            => 'test-rejected',
    checkout_dir    => '2a0737e27a3b75590e7fab112b06a76fe7573699',
    api_url         => 'https://api.opensuse.org',
    requesting_user => 1,
    project         => 'devel:languages:perl',
    package         => 'test-rejected',
    srcmd5          => '2a0737e27a3b75590e7fab112b06a76fe7573699',
    priority        => 5
  );
  $pkgs->imported($id);

  # Lawyer rejects the review
  my $pkg = $pkgs->find($id);
  $pkg->{state}            = 'unacceptable';
  $pkg->{reviewing_user}   = 1;
  $pkg->{review_timestamp} = 1;
  $pkg->{result}           = 'Rejected by lawyer';
  $pkgs->update($pkg);
  is $pkgs->find($id)->{state}, 'unacceptable', 'rejected by lawyer';

  # Bot links the package to a request, then the request is closed
  $t->post_ok('/requests' => {Authorization => 'Token test_token'} => form =>
      {external_link => 'openSUSE:Rejected', package => $id})->status_is(200);
  $t->delete_ok('/requests' => {Authorization => 'Token test_token'} => form => {external_link => 'openSUSE:Rejected'})
    ->status_is(200);

  # State is preserved, but the package is flagged obsolete
  is $pkgs->find($id)->{state}, 'unacceptable', 'lawyer rejection preserved';
  ok $pkgs->is_obsolete($id), 'package is obsolete';
};

subtest 'Pagination' => sub {
  subtest 'Search' => sub {
    $t->get_ok('/pagination/search/perl-Mojolicious')
      ->json_is('/start',          1)
      ->json_is('/end',            1)
      ->json_is('/total',          1)
      ->json_is('/page/0/package', 'perl-Mojolicious')
      ->json_is('/page/0/id',      1)
      ->json_is('/page/0/state',   'new')
      ->json_has('/page/0/checksum')
      ->json_has('/page/0/comment')
      ->json_has('/page/0/user')
      ->json_has('/page/0/created_epoch')
      ->json_has('/page/0/imported_epoch')
      ->json_has('/page/0/indexed_epoch')
      ->json_has('/page/0/unpacked_epoch')
      ->json_is('/page/0/active_jobs'        => 0)
      ->json_is('/page/0/failed_jobs'        => 0)
      ->json_is('/page/0/unresolved_matches' => 6)
      ->json_hasnt('/page/1');
    $t->get_ok('/pagination/search/perl-Mojolicious?notObsolete=true')
      ->json_is('/start', 1)
      ->json_is('/end',   0)
      ->json_is('/total', 0)
      ->json_hasnt('/page/0');
    $t->get_ok('/pagination/search/perl-Mojolicious?filter=Artistic')
      ->json_is('/start',     1)
      ->json_is('/end',       1)
      ->json_is('/total',     1)
      ->json_is('/page/0/id', 1)
      ->json_hasnt('/page/1');
    $t->get_ok('/pagination/search/perl-Mojolicious?filter=MIT')
      ->json_is('/start', 1)
      ->json_is('/end',   0)
      ->json_is('/total', 0)
      ->json_hasnt('/page/0');
  };

  subtest 'Products' => sub {
    $t->get_ok('/pagination/products/known')
      ->json_is('/start',          1)
      ->json_is('/end',            3)
      ->json_is('/total',          3)
      ->json_is('/page/0/name',    'openSUSE:Test')
      ->json_is('/page/0/streams', 1)
      ->json_like('/page/0/updated_epoch', qr/\d+/)
      ->json_is('/page/0/new_packages',          3)
      ->json_is('/page/0/reviewed_packages',     0)
      ->json_is('/page/0/unacceptable_packages', 0)
      ->json_hasnt('/page/3');
    $t->get_ok('/pagination/products/known?filter=Factory')
      ->json_is('/start',       1)
      ->json_is('/end',         1)
      ->json_is('/total',       1)
      ->json_is('/page/0/name', 'openSUSE:Factory')
      ->json_hasnt('/page/1');

    $t->get_ok('/pagination/products/openSUSE:Test')
      ->json_is('/start',        1)
      ->json_is('/end',          3)
      ->json_is('/total',        3)
      ->json_is('/page/0/id',    6)
      ->json_is('/page/0/state', 'new')
      ->json_is('/page/0/name',  'test-package-5')
      ->json_has('/page/0/checksum')
      ->json_has('/page/0/imported_epoch')
      ->json_has('/page/0/indexed_epoch')
      ->json_has('/page/0/unpacked_epoch')
      ->json_is('/page/0/active_jobs'        => 0)
      ->json_is('/page/0/failed_jobs'        => 0)
      ->json_is('/page/0/unresolved_matches' => 0);
    $t->get_ok('/pagination/products/openSUSE:Test?filter=package-3')
      ->json_is('/start',     1)
      ->json_is('/end',       1)
      ->json_is('/total',     1)
      ->json_is('/page/0/id', 4)
      ->json_hasnt('/page/1');

    $t->get_ok('/pagination/products/openSUSE:Test?attention=true')
      ->json_is('/start',     1)
      ->json_is('/end',       3)
      ->json_is('/total',     3)
      ->json_is('/page/0/id', 6)
      ->json_hasnt('/page/3');

    $t->get_ok('/pagination/products/openSUSE:Test?unresolvedMatches=true')
      ->json_is('/start', 1)
      ->json_is('/end',   0)
      ->json_is('/total', 0)
      ->json_hasnt('/page/0');
  };

  subtest 'Product annotations and grouping' => sub {
    my $products = $t->app->products;

    # The curator annotation endpoint is gated by the 'curate' capability
    $t->put_ok('/products/openSUSE:Factory/annotation' => form => {product => 'Tumbleweed'})->status_is(403);
    is $products->find('openSUSE:Factory')->{product}, undef, 'annotation unchanged for anonymous user';

    # Two codestreams of one deliverable, sharing a package, plus a differently named codestream
    my $s1 = $products->find_or_create('SUSE:SLE-15-SP7:Update:Products:MLM51')->{id};
    my $s2 = $products->find_or_create('SUSE:SLE-15-SP7:Update:Products:MLM51:Update')->{id};
    $products->update($s1, [1, 4]);
    $products->update($s2, [1, 5]);

    # Annotate both to the same product (mirrors what the curator UI PUT does)
    is $products->set_annotation('SUSE:SLE-15-SP7:Update:Products:MLM51', 'Multi-Linux Manager'),
      'Multi-Linux Manager', 'annotation stored';
    $products->set_annotation('SUSE:SLE-15-SP7:Update:Products:MLM51:Update', 'Multi-Linux Manager');

    # for_package_products carries the annotation alongside the raw codestream name
    my $memberships = $products->for_package_products(4);
    ok
      scalar(grep { $_->{name} eq 'SUSE:SLE-15-SP7:Update:Products:MLM51' && $_->{product} eq 'Multi-Linux Manager' }
        @$memberships), 'annotation returned for package';

    # The two codestreams collapse into a single group row in the listing, and a package shared by both
    # (package 1) is counted once, not once per codestream - so the group's three packages (1, 4, 5) are
    # three, not four
    $t->get_ok('/pagination/products/known?filter=Multi-Linux')
      ->json_is('/total',               1)
      ->json_is('/page/0/name',         'Multi-Linux Manager')
      ->json_is('/page/0/streams',      2)
      ->json_is('/page/0/new_packages', 3)
      ->json_hasnt('/page/1');

    # The flat view lists each codestream on its own, exposing its annotation
    $t->get_ok('/pagination/products/known?grouped=false&filter=MLM51')
      ->json_is('/total',             2)
      ->json_is('/page/0/streams',    1)
      ->json_is('/page/0/annotation', 'Multi-Linux Manager')
      ->json_hasnt('/page/2');

    # Querying the group name aggregates packages across both codestreams, de-duplicated (1, 4, 5)
    $t->get_ok('/pagination/products/Multi-Linux%20Manager')->json_is('/total', 3)->json_hasnt('/page/3');

    # A raw codestream name still resolves to just its own packages
    $t->get_ok('/pagination/products/SUSE:SLE-15-SP7:Update:Products:MLM51')->json_is('/total', 2);

    # Clearing the annotation restores the raw-name fallback
    $products->set_annotation('SUSE:SLE-15-SP7:Update:Products:MLM51',        '');
    $products->set_annotation('SUSE:SLE-15-SP7:Update:Products:MLM51:Update', '');
    is $products->find('SUSE:SLE-15-SP7:Update:Products:MLM51')->{product}, undef, 'annotation cleared';
    $t->get_ok('/pagination/products/known?filter=Multi-Linux')->json_is('/total', 0);
  };

  subtest 'Licenses' => sub {
    $t->get_ok('/pagination/licenses/known')
      ->json_is('/start',            1)
      ->json_is('/end',              6)
      ->json_is('/total',            6)
      ->json_is('/page/0/license',   '')
      ->json_is('/page/0/spdx',      '')
      ->json_is('/page/0/risks',     [5])
      ->json_is('/page/1/license',   'Apache-2.0')
      ->json_is('/page/1/spdx',      '')
      ->json_is('/page/1/spdx_html', '')
      ->json_is('/page/1/risks',     [5])
      ->json_hasnt('/page/6');
    $t->get_ok('/pagination/licenses/known?filter=Artistic')
      ->json_is('/start',          1)
      ->json_is('/end',            1)
      ->json_is('/total',          1)
      ->json_is('/page/0/license', 'Artistic-2.0')
      ->json_hasnt('/page/1');
    $t->get_ok('/pagination/licenses/known?filter=MIT')
      ->json_is('/start',          1)
      ->json_is('/end',            2)
      ->json_is('/total',          2)
      ->json_is('/page/0/license', 'MIT')
      ->json_is('/page/1/license', 'MIT-CMU')
      ->json_hasnt('/page/2');
  };

  subtest 'Reviews' => sub {
    $t->get_ok('/pagination/reviews/open')
      ->json_is('/start',           1)
      ->json_is('/end',             3)
      ->json_is('/total',           3)
      ->json_is('/page/0/id',       2)
      ->json_is('/page/0/state',    'new')
      ->json_is('/page/0/priority', 5)
      ->json_is('/page/0/name',     'test-package-1')
      ->json_has('/page/0/checksum')
      ->json_has('/page/0/external_link')
      ->json_is('/page/0/external_link_data', undef)
      ->json_has('/page/0/created_epoch')
      ->json_has('/page/0/imported_epoch')
      ->json_has('/page/0/indexed_epoch')
      ->json_has('/page/0/unpacked_epoch')
      ->json_is('/page/0/active_jobs'        => 0)
      ->json_is('/page/0/failed_jobs'        => 0)
      ->json_is('/page/0/unresolved_matches' => 0)
      ->json_hasnt('/page/3');
    $t->get_ok('/pagination/reviews/open?filter=package-3')
      ->json_is('/start',     1)
      ->json_is('/end',       1)
      ->json_is('/total',     1)
      ->json_is('/page/0/id', 4)
      ->json_hasnt('/page/1');
    $t->get_ok('/pagination/reviews/open?notEmbargoed=true')
      ->json_is('/start',     1)
      ->json_is('/end',       3)
      ->json_is('/total',     3)
      ->json_is('/page/0/id', 2)
      ->json_hasnt('/page/3');
  };
};

subtest 'Upload package' => sub {
  my $auth    = {Authorization => 'Token test_token'};
  my $tarball = path(__FILE__)
    ->sibling('legal-bot', 'perl-Mojolicious', 'c7cfdab0e71b0bebfdf8b2dc3badfecd', 'Mojolicious-7.25.tar.gz');
  my $tarball_md5 = md5_file($tarball);
  is $tarball_md5, 'c1ffb4256878c64eb0e40c48f36d24d2', 'known fixture checksum';

  my $count_packages = sub { $t->app->pg->db->query('SELECT count(*) FROM bot_packages')->array->[0] };
  my $count_unpacks  = sub { $t->app->minion->jobs({tasks => ['unpack']})->total };

  subtest 'Validation' => sub {

    # Missing everything, then each required field in turn
    $t->post_ok('/packages/upload', $auth)->status_is(400);
    $t->post_ok('/packages/upload', $auth,
      form => {name => 'upload-test', priority => 5, tarball => {file => $tarball->to_string}})->status_is(400);
    $t->post_ok('/packages/upload', $auth, form => {name => 'upload-test', priority => 5, checksum => $tarball_md5})
      ->status_is(400);
  };

  subtest 'Checksum mismatch leaves no trace' => sub {
    my $before_pkgs    = $count_packages->();
    my $before_unpacks = $count_unpacks->();

    $t->post_ok(
      '/packages/upload',
      $auth,
      form => {
        name     => 'upload-test',
        priority => 5,
        checksum => 'ffffffffffffffffffffffffffffffff',
        tarball  => {file => $tarball->to_string}
      }
    )->status_is(400)->json_is('/error', 'Checksum mismatch');

    is $count_packages->(), $before_pkgs,    'no package row created';
    is $count_unpacks->(),  $before_unpacks, 'no unpack job enqueued';
    ok !$t->app->packages->find_by_name_and_md5('upload-test', $tarball_md5), 'no package for this content';
    ok !-d $dir->child('upload-test', $tarball_md5),                          'no checkout directory left behind';
  };

  my $uploaded_id;
  subtest 'Successful upload' => sub {
    my $before_unpacks = $count_unpacks->();

    $t->post_ok(
      '/packages/upload',
      $auth,
      form => {
        name          => 'upload-test',
        priority      => 6,
        checksum      => $tarball_md5,
        external_link => 'gh#acme/mojo!42@b352a49',
        tarball       => {file => $tarball->to_string}
      }
    )->status_is(200)->json_has('/saved/id')->json_is('/duplicate', false);

    $uploaded_id = $t->tx->res->json->{saved}{id};

    my $pkg = $t->app->packages->find($uploaded_id);
    is $pkg->{name},            'upload-test',                       'right name';
    is $pkg->{checkout_dir},    $tarball_md5,                        'checkout_dir is the archive content hash';
    is $pkg->{external_link},   'gh#acme/mojo!42@b352a49',           'external link persisted';
    is $pkg->{priority},        6,                                   'priority from the request';
    is $pkg->{requesting_user}, $t->app->users->licensedigger->{id}, 'requested by the bot user';
    ok -f $dir->child('upload-test', $tarball_md5, 'Mojolicious-7.25.tar.gz'), 'tarball on disk';

    is $count_unpacks->(), $before_unpacks + 1, 'one unpack job enqueued';
    my $unpack = $t->app->minion->jobs({tasks => ['unpack'], states => ['inactive']})->next;
    is $unpack->{priority}, incoming_priority(6), 'queued in the incoming band for the request priority';
  };

  subtest 'Indexing produces a report' => sub {
    $t->app->minion->perform_jobs;
    $t->get_ok("/package/$uploaded_id/report" => $auth)->status_is(200)->json_is('/package/name', 'upload-test');
  };

  subtest 'Idempotent retry' => sub {
    my $before_pkgs    = $count_packages->();
    my $before_unpacks = $count_unpacks->();

    $t->post_ok(
      '/packages/upload',
      $auth,
      form => {
        name          => 'upload-test',
        priority      => 6,
        checksum      => $tarball_md5,
        external_link => 'gh#acme/mojo!42@b352a49',
        tarball       => {file => $tarball->to_string}
      }
    )->status_is(200)->json_is('/saved/id', $uploaded_id)->json_is('/duplicate', true);

    is $count_packages->(), $before_pkgs,    'no duplicate package row';
    is $count_unpacks->(),  $before_unpacks, 'no second unpack job';
  };

  subtest 'Same name with different content creates a distinct package' => sub {
    my $tmp = tempdir;
    my $src = $tmp->child('src')->make_path;
    $src->child('file.txt')->spew("something else entirely\n");
    my $archive = $tmp->child('other.tar.gz');
    is system('tar', '-czf', $archive->to_string, '-C', $src->to_string, '.'), 0, 'archive created';

    $t->post_ok(
      '/packages/upload',
      $auth,
      form => {
        name     => 'upload-test',
        priority => 5,
        checksum => md5_file($archive),
        tarball  => {file => $archive->to_string}
      }
    )->status_is(200)->json_is('/duplicate', false);
    isnt $t->tx->res->json->{saved}{id}, $uploaded_id, 'distinct package for different content under the same name';
  };
};

done_testing;
