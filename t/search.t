use Mojo::Base -strict;

BEGIN { $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll' }

use Test::More;

plan skip_all => 'set TEST_ONLINE to enable this test' unless $ENV{TEST_ONLINE};

use Mojo::File 'tempdir';
use Mojo::Pg;
use Test::Mojo;

# Isolate tests
my $pg = Mojo::Pg->new($ENV{TEST_ONLINE});
$pg->db->query('drop schema if exists bot_search_test cascade');
$pg->db->query('create schema bot_search_test');

# Configure application
my $dir    = tempdir;
my $online = Mojo::URL->new($ENV{TEST_ONLINE})
  ->query([search_path => 'bot_search_test'])->to_unsafe_string;
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
my $db = $t->app->pg->db;
my $usr_id
  = $db->insert('bot_users', {login => 'test_bot'}, {returning => 'id'})
  ->hash->{id};
my $pkgs   = $t->app->packages;
my $pkg_id = $pkgs->add(
  name            => 'perl-Mojolicious',
  checkout_dir    => 'c7cfdab0e71b0bebfdf8b2dc3badfecd',
  api_url         => 'https://api.opensuse.org',
  requesting_user => $usr_id,
  project         => 'devel:languages:perl',
  package         => 'perl-Mojolicious',
  srcmd5          => 'bd91c36647a5d3dd883d490da2140401',
  priority        => 5
);
$pkgs->update(
  {
    id               => $pkg_id,
    state            => 'correct',
    result           => 'Perfect',
    checksum         => 'Artistic-2.0-3:Hsyo',
    review_timestamp => 1
  }
);
$pkg_id = $pkgs->add(
  name            => 'perl',
  checkout_dir    => 'c7cfdab0e71b0bebfdf8b2dc3badfecd',
  api_url         => 'https://api.opensuse.org',
  requesting_user => $usr_id,
  project         => 'devel:languages:perl',
  package         => 'perl',
  srcmd5          => 'bd91c36647a5d3dd883d490da2140401',
  priority        => 5
);
$pkgs->update(
  {
    id               => $pkg_id,
    state            => 'correct',
    result           => 'The best',
    checksum         => 'Artistic-1.0-3:PeRl',
    review_timestamp => 1
  }
);

# Basic search with suggestion
$t->get_ok('/')->status_is(200)
  ->element_exists('form[action=/search] input[name=q]');
$t->get_ok('/search?q=perl')->status_is('200')
  ->element_exists('form[action=/search] input[name=q][value=perl]')
  ->text_like('#results .state',      qr/correct/)
  ->text_like('#results .result',     qr/The best/)
  ->text_like('#results .checksum a', qr/Artistic-1\.0/)
  ->text_like('#suggestions td a',    qr/perl-Mojolicious/);
$t->get_ok('/search?q=perl-Mojolicious')->status_is('200')
  ->element_exists('form[action=/search] input[name=q][value=perl-Mojolicious]')
  ->text_like('#results .state',      qr/correct/)
  ->text_like('#results .result',     qr/Perfect/)
  ->text_like('#results .checksum a', qr/Artistic-2\.0/)
  ->element_exists_not('#suggestions');

# Clean up once we are done
$pg->db->query('drop schema bot_search_test cascade');

done_testing();
