use Mojo::Base -strict;

BEGIN { $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll' }

use Test::More;

plan skip_all => 'set TEST_ONLINE to enable this test' unless $ENV{TEST_ONLINE};

use Mojo::File 'tempdir';
use Mojo::Pg;
use Test::Mojo;

# Isolate tests
my $pg = Mojo::Pg->new($ENV{TEST_ONLINE});
$pg->db->query('drop schema if exists login_test cascade');
$pg->db->query('create schema login_test');

# Configure application
my $dir = tempdir;
my $online
  = Mojo::URL->new($ENV{TEST_ONLINE})->query([search_path => 'login_test'])
  ->to_unsafe_string;
my $config = {
  secrets              => ['just_a_test'],
  checkout_dir         => $dir,
  openid               => {provider => 'https://www.opensuse.org/openid/user/'},
  tokens               => ['test_token'],
  pg                   => $online,
  acceptable_risk      => 3,
  index_bucket_average => 100,
  cleanup_bucket_average => 50,
  min_files_short_report => 20,
  max_email_url_size     => 26,
  max_task_memory        => 5_000_000_000,
  max_worker_rss         => 100000,
  max_expanded_files     => 100
};
my $t = Test::Mojo->new(Cavil => $config);
$t->app->pg->migrations->migrate;

# Not authenticated
$t->post_ok('/reviews/review_package/1')->status_is(403)
  ->content_like(qr/Permission/);
$t->post_ok('/reviews/fasttrack_package/1')->status_is(403)
  ->content_like(qr/Permission/);
$t->post_ok('/reviews/add_ignore')->status_is(403)
  ->content_like(qr/Permission/);
$t->post_ok('/reviews/reindex/1')->status_is(403)->content_like(qr/Permission/);
$t->get_ok('/licenses')->status_is(403)->content_like(qr/Permission/);
$t->post_ok('/licenses')->status_is(403)->content_like(qr/Permission/);
$t->get_ok('/licenses/new_pattern')->status_is(403)
  ->content_like(qr/Permission/);
$t->post_ok('/licenses/create_pattern')->status_is(403)
  ->content_like(qr/Permission/);
$t->get_ok('/licenses/1')->status_is(403)->content_like(qr/Permission/);
$t->post_ok('/licenses/1')->status_is(403)->content_like(qr/Permission/);
$t->get_ok('/licenses/edit_pattern/1')->status_is(403)
  ->content_like(qr/Permission/);
$t->post_ok('/licenses/update_pattern/1')->status_is(403)
  ->content_like(qr/Permission/);
$t->delete_ok('/licenses/remove_pattern/1')->status_is(403)
  ->content_like(qr/Permission/);

# OpenID
$t->get_ok('/login')->status_is(302)->header_is(Location => '/openid');

# Dummy
delete $config->{openid};
$t = Test::Mojo->new(Cavil => $config);
$t->get_ok('/licenses')->status_is(403)->content_like(qr/Permission/);
$t->get_ok('/login')->status_is(302)->header_is(Location => '/');
$t->get_ok('/licenses')->status_is(200)->content_like(qr/Licenses/);
$t->get_ok('/logout')->status_is(302)->header_is(Location => '/');
$t->get_ok('/licenses')->status_is(403)->content_like(qr/Permission/);

# Clean up once we are done
$pg->db->query('drop schema login_test cascade');

done_testing;
