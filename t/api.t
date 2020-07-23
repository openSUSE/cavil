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

BEGIN { $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll' }

use Test::More;

plan skip_all => 'set TEST_ONLINE to enable this test' unless $ENV{TEST_ONLINE};

use Cavil::OBS;
use Mojo::File qw(path tempdir);
use Mojo::IOLoop;
use Mojo::Pg;
use Mojo::Server::Daemon;
use Mojolicious;
use Test::Mojo;

# Isolate tests
my $pg = Mojo::Pg->new($ENV{TEST_ONLINE});
$pg->db->query('drop schema if exists bot_api_test cascade');
$pg->db->query('create schema bot_api_test');

# Configure application
my $dir    = tempdir;
my $online = Mojo::URL->new($ENV{TEST_ONLINE})->query([search_path => 'bot_api_test'])->to_unsafe_string;
my $config = {
  secrets                => ['just_a_test'],
  checkout_dir           => $dir,
  openid                 => {provider => 'https://www.opensuse.org/openid/user/', secret => 's3cret'},
  tokens                 => ['test_token'],
  pg                     => $online,
  acceptable_risk        => 3,
  index_bucket_average   => 100,
  cleanup_bucket_average => 50,
  min_files_short_report => 20,
  max_email_url_size     => 26,
  max_task_memory        => 5_000_000_000,
  max_worker_rss         => 100000,
  max_expanded_files     => 100
};
my $t = Test::Mojo->new(Cavil => $config);
$t->app->pg->migrations->migrate;

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

# Not authenticated
$t->get_ok('/package/1')->status_is(403)->content_like(qr/Permission/);

# Package not created yet
$t->get_ok('/package/1' => {Authorization => 'Token test_token'})->status_is(404)->content_like(qr/No such package/);

# Create package
my $form = {api => $api, package => 'perl-Mojolicious', project => 'devel:languages:perl'};
$t->app->patterns->expire_cache;
$t->post_ok('/packages' => {Authorization => 'Token test_token'} => form => $form)->status_is(200)
  ->json_is('/saved/checkout_dir', '236d7b56886a0d2799c0d114eddbb7f1')->json_is('/saved/id', 1);
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
ok -d $checkout, 'directory exists';
ok -f $checkout->child('Mojolicious-7.25.tar.gz'),  'file exists';
ok -f $checkout->child('perl-Mojolicious.changes'), 'file exists';
ok -f $checkout->child('perl-Mojolicious.spec'),    'file exists';
ok !-d $checkout->child('Mojolicious'),             'directory does not exist yet';

# Package has been created
$t->get_ok('/package/1' => {Authorization => 'Token test_token'})->status_is(200)->json_is('/state', 'new')
  ->json_is('/priority', 5);

# Update priority
$t->patch_ok('/package/1' => {Authorization => 'Token test_token'} => form => {priority => 7})->status_is(200);
$t->get_ok('/package/1' => {Authorization => 'Token test_token'})->status_is(200)->json_is('/state', 'new')
  ->json_is('/priority', 7);

# Request not created yet
$t->get_ok('/requests' => {Authorization => 'Token test_token'})->status_is(200)->json_is('/requests', []);

# Create a requests
$t->post_ok('/requests' => {Authorization => 'Token test_token'} => form => {external_link => 'obs#123', package => 1})
  ->status_is(200)->json_is('/created', 'obs#123');

# Request has been created
$t->get_ok('/requests' => {Authorization => 'Token test_token'})->status_is(200)
  ->json_is('/requests/0/external_link', 'obs#123')->json_is('/requests/0/packages', [1]);

# Remove request again
$t->delete_ok('/requests' => {Authorization => 'Token test_token'} => form => {external_link => 'obs#123'})
  ->status_is(200);
$t->get_ok('/requests' => {Authorization => 'Token test_token'})->status_is(200)->json_is('/requests', []);

# Products
$t->patch_ok('/products/openSUSE:Factory' => {Authorization => 'Token test_token'} => form => {id => 1})
  ->status_is(200)->json_is('/updated', 1);
$t->patch_ok('/products/openSUSE:Leap:15.0' => {Authorization => 'Token test_token'} => form => {id => 1})
  ->status_is(200)->json_is('/updated', 2);
is_deeply $t->app->products->for_package(1), ['openSUSE:Factory', 'openSUSE:Leap:15.0'], 'right products';

# Acceptable risk
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

# Clean up once we are done
$pg->db->query('drop schema bot_api_test cascade');

done_testing;
