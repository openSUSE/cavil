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
$pg->db->query('drop schema if exists classifier_test cascade');
$pg->db->query('create schema classifier_test');

# Create checkout directory
my $dir  = tempdir;
my @src  = ('perl-Mojolicious', 'c7cfdab0e71b0bebfdf8b2dc3badfecd');
my $mojo = $dir->child(@src)->make_path;
$_->copy_to($mojo->child($_->basename))
  for path(__FILE__)->dirname->child('legal-bot', @src)->list->each;

app->log->level('error');

post '/' => sub {
  my $c = shift;

  my $text = $c->req->body;
  if ($text =~ /Fixed copyright notice/) {
    return $c->render(json => {license => \1, confidence => '98.123'});
  }
  else {
    $c->render(json => {license => \0, confidence => '55.321'});
  }
};

get '/*whatever' => {whatever => ''} => {text => '', status => 404};

# Configure application
my $online = Mojo::URL->new($ENV{TEST_ONLINE})
  ->query([search_path => 'classifier_test'])->to_unsafe_string;
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
  max_expanded_files     => 100,
  classifier             => "http://127.0.0.1:5000"
};
my $t = Test::Mojo->new(Cavil => $config);
$t->app->pg->migrations->migrate;

# Connect mock server
my $classifier = $t->app->classifier;
is $classifier->url, 'http://127.0.0.1:5000', 'URL has been configured';
my $url = 'http://127.0.0.1:' . $classifier->ua->server->app(app)->url->port;
$classifier->url($url);

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
$t->app->patterns->expire_cache;
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
  pattern => 'powerful web development toolkit',
  license => 'SUSE-NotALicense'
);
$t->app->patterns->create(pattern => 'the terms');
$t->app->patterns->create(pattern => 'copyright notice');

# Unpack and index
$t->app->minion->enqueue(unpack => [$pkg_id]);
$t->app->minion->perform_jobs;

# Not yet classified
my $snippet = $t->app->pg->db->select('snippets', '*', {id => 1})->hash;
is $snippet->{id},         1,                          'right id';
is $snippet->{classified}, 0,                          'not classified';
is $snippet->{license},    0,                          'not a license';
is $snippet->{confidence}, 0,                          'not confidence';
like $snippet->{text},     qr/Fixed copyright notice/, 'right text';
$snippet = $t->app->pg->db->select('snippets', '*', {id => 2})->hash;
is $snippet->{id},         2,                            'right id';
is $snippet->{classified}, 0,                            'not classified';
is $snippet->{license},    0,                            'not a license';
is $snippet->{confidence}, 0,                            'not confidence';
like $snippet->{text},     qr/This license establishes/, 'right text';

# Classify
my $classify_id = $t->app->minion->enqueue('classify');
$t->app->minion->perform_jobs;

# Classified
$snippet = $t->app->pg->db->select('snippets', '*', {id => 1})->hash;
is $snippet->{id},         1,                          'right id';
is $snippet->{classified}, 1,                          'classified';
is $snippet->{license},    1,                          'license';
is $snippet->{confidence}, 98,                         'confidence';
like $snippet->{text},     qr/Fixed copyright notice/, 'right text';
$snippet = $t->app->pg->db->select('snippets', '*', {id => 2})->hash;
is $snippet->{id},         2,                            'right id';
is $snippet->{classified}, 1,                            'classified';
is $snippet->{license},    0,                            'not a license';
is $snippet->{confidence}, 55,                           'confidence';
like $snippet->{text},     qr/This license establishes/, 'right text';

# Clean up once we are done
$pg->db->query('drop schema classifier_test cascade');

done_testing;
