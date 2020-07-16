use Mojo::Base -strict;

BEGIN { $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll' }

use Test::More;

plan skip_all => 'set TEST_ONLINE to enable this test' unless $ENV{TEST_ONLINE};

use Cavil::Util;
use File::Copy 'copy';
use Mojo::File qw(path tempdir);
use Mojo::IOLoop;
use Mojo::Pg;
use Mojo::URL;
use Test::Mojo;

# Isolate tests
my $pg = Mojo::Pg->new($ENV{TEST_ONLINE});
$pg->db->query('drop schema if exists bot_index_test cascade');
$pg->db->query('create schema bot_index_test');

# Create checkout directory
my $dir = tempdir;
my @src = ('package-with-snippets', '2a0737e27a3b75590e7fab112b06a76fe7573615');
my $mojo = $dir->child(@src)->make_path;
copy "$_", $mojo->child($_->basename)
  for path(__FILE__)->dirname->child('legal-bot', @src)->list->each;

# Configure application
my $online
  = Mojo::URL->new($ENV{TEST_ONLINE})->query([search_path => 'bot_index_test'])
  ->to_unsafe_string;
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
my $pkg_id = $t->app->packages->add(
  name            => 'package-with-snippets',
  checkout_dir    => '2a0737e27a3b75590e7fab112b06a76fe7573615',
  api_url         => 'https://api.opensuse.org',
  requesting_user => $usr_id,
  project         => 'devel:languages:perl',
  package         => 'package-with-snippets',
  srcmd5          => '2a0737e27a3b75590e7fab112b06a76fe7573615',
  priority        => 5
);

$t->app->patterns->create(pattern => 'license');
$t->app->patterns->create(pattern => 'GPL', license => 'GPL');
$t->app->patterns->create(
  pattern =>
    'Permission is granted to copy, distribute and/or modify this document
       under the terms of the GNU Free Documentation License, Version 1.1 or any later
       version published by the Free Software Foundation; with no Invariant Sections,
       with no Front-Cover Texts and with no Back-Cover Texts. A copy of the license
       is included in the section entitled "GNU Free Documentation License"',
  license => 'GFDL-1.1-or-later'
);

# Unpack and index with the job queue
my $unpack_id = $t->app->minion->enqueue(unpack => [$pkg_id]);
$t->app->minion->perform_jobs;

like $t->app->packages->find($pkg_id)->{checksum}, qr/^Error-9:\w+/,
  'right shortname';

my $res = $db->select('snippets', 'text', {}, {order_by => 'text'})->hashes;
is_deeply(
  $res,
  [
    {
      text =>
        "\nNow complex: The license might\nbe something cool\nbut we would not\nsay what we can do"
        . "\nand what we can not do\nwith the GPL. The problem\nis that if we continue\nthis line and afterwards"
        . "\ntalk again about the GPL,\nit should really be part\nof the same snippet. We don't\nwant GPL to abort it."
    },
    {
      text =>
        "The GPL might be\nsomething cool\nbut we would not\nsay what we can do\nand what we can not do"
        . "\nwith the license.\n"
    },
    {
      text =>
        "The license might be\nsomething cool\nbut we would not\nsay what we can do\nand what we can not do"
        . "\nwith the GPL."
    }
  ]
);

# Clean up once we are done
$pg->db->query('drop schema bot_index_test cascade');

done_testing();
