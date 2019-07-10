use Mojo::Base -strict;

BEGIN { $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll' }

use Test::More;

plan skip_all => 'set TEST_ONLINE to enable this test' unless $ENV{TEST_ONLINE};

use Mojo::File 'tempdir';
use Mojo::Pg;
use Test::Mojo;

# Isolate tests
my $pg = Mojo::Pg->new($ENV{TEST_ONLINE});
$pg->db->query('drop schema if exists bot_snippet_test cascade');
$pg->db->query('create schema bot_snippet_test');

# Configure application
my $dir    = tempdir;
my $online = Mojo::URL->new($ENV{TEST_ONLINE})
  ->query([search_path => 'bot_snippet_test'])->to_unsafe_string;
my $config = {
  secrets                => ['just_a_test'],
  checkout_dir           => $dir,
  tokens                 => [],
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

# Prepare database
my $db   = $t->app->pg->db;
my $pkgs = $t->app->packages;

# Basic search with suggestion
$t->get_ok('/snippets')->status_is(200)
  ->content_like(qr/No snippets left/, 'no risk, only fun');

my $id = $t->app->snippets->find_or_create('0000', 'Licenses are cool');
$t->get_ok('/snippets')->status_is(200)
  ->content_unlike(qr/No snippets left/, 'snippets to check');
$t->get_ok('/snippets')->status_is(200)->element_exists("#good_$id")
  ->element_exists("input[name=g_$id][value='0']")
  ->element_exists_not('input[type="submit"]');

$t->post_ok('/snippets' => form => {"g_$id" => 0})->status_is(403);

# now test with login
$t->get_ok('/login')->status_is(302)->header_is(Location => '/');
$t->get_ok('/snippets')->status_is(200)->element_exists("#good_$id")
  ->element_exists("input[name=g_$id][value='0']")
  ->element_exists('input[type="submit"]');
$t->post_ok('/snippets' => form => {"g_$id" => 0})->status_is(302)
  ->header_is(Location => '/snippets');
$t->get_ok('/snippets')->status_is(200)
  ->content_like(qr/No snippets left/, 'All done');

my $res = $db->select('snippets', [qw(classified approved license)])->hash;
is_deeply(
  $res,
  {classified => 1, approved => 1, license => 0},
  'all fields updated'
);

# Clean up once we are done
$pg->db->query('drop schema bot_snippet_test cascade');

done_testing();
