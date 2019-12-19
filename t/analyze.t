use Mojo::Base -strict;

BEGIN { $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll' }

use Test::More;

plan skip_all => 'set TEST_ONLINE to enable this test' unless $ENV{TEST_ONLINE};

use Test::Mojo;
use Mojo::File qw(path tempdir);
use Mojo::Pg;
use Mojolicious::Lite;

# Isolate tests
my $pg = Mojo::Pg->new($ENV{TEST_ONLINE});
$pg->db->query('drop schema if exists analyze_test cascade');
$pg->db->query('create schema analyze_test');

# Create checkout directory
my $dir  = tempdir;
my @src  = ('perl-Mojolicious', 'c7cfdab0e71b0bebfdf8b2dc3badfecd');
my $mojo = $dir->child(@src)->make_path;
$_->copy_to($mojo->child($_->basename))
  for path(__FILE__)->dirname->child('legal-bot', @src)->list->each;
@src  = ('perl-Mojolicious', 'da3e32a3cce8bada03c6a9d63c08cd58');
$mojo = $dir->child(@src)->make_path;
$_->copy_to($mojo->child($_->basename))
  for path(__FILE__)->dirname->child('legal-bot', @src)->list->each;

app->log->level('error');

# Configure application
my $online = Mojo::URL->new($ENV{TEST_ONLINE})
  ->query([search_path => 'analyze_test'])->to_unsafe_string;
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
  name            => 'perl-Mojolicious',
  checkout_dir    => 'c7cfdab0e71b0bebfdf8b2dc3badfecd',
  api_url         => 'https://api.opensuse.org',
  requesting_user => $usr_id,
  project         => 'devel:languages:perl',
  package         => 'perl-Mojolicious',
  srcmd5          => 'bd91c36647a5d3dd883d490da2140401',
  priority        => 5
);
$t->app->patterns->create(
  pattern => 'You may obtain a copy of the License at',
  license => 'Apache-2.0'
);
$t->app->patterns->create(
  packname => 'perl-Mojolicious',
  pattern  => 'Licensed under the Apache License, Version 2.0',
  license  => 'Apache-2.0'
);
$t->app->patterns->create(
  pattern => 'License: Artistic-2.0',
  license => 'Artistic-2.0'
);
$t->app->patterns->create(
  pattern => 'License: GPL-1.0+',
  license => 'GPL-1.0+'
);
$t->app->patterns->create(pattern => 'the terms');
$t->app->patterns->create(pattern => 'copyright notice');

# Unpack and index
$t->app->minion->enqueue(unpack => [$pkg_id]);
$t->app->minion->perform_jobs;

# set the first version to acceptable
my $pkg = $t->app->packages->find($pkg_id);
$pkg->{reviewing_user}   = $usr_id;
$pkg->{result}           = 'Sure';
$pkg->{state}            = 'acceptable';
$pkg->{review_timestamp} = 1;
$t->app->packages->update($pkg);

my $pkg2_id = $t->app->packages->add(
  name            => 'perl-Mojolicious',
  checkout_dir    => 'da3e32a3cce8bada03c6a9d63c08cd58',
  api_url         => 'https://api.opensuse.org',
  requesting_user => $usr_id,
  project         => 'devel:languages:perl',
  package         => 'perl-Mojolicious',
  srcmd5          => 'da3e32a3cce8bada03c6a9d63c08cd58',
  priority        => 5
);

# Unpack and index
$t->app->minion->enqueue(unpack => [$pkg2_id]);
$t->app->minion->perform_jobs;

my $res = $db->select('bot_packages', '*', { id => $pkg2_id })->hashes->[0];
is($res->{result}, "Diff to closest match $pkg_id:\n\n  Different spec file license: Artistic-2.0\n\n", 'different spec');
is($res->{state}, 'new', 'not approved');

# Clean up once we are done
$pg->db->query('drop schema analyze_test cascade');

done_testing;
