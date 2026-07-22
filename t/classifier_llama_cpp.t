# Copyright 2026 SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Mojo::Base -strict;

use FindBin;
use lib "$FindBin::Bin/lib";

use Test::More;
use Test::Mojo;
use Cavil::Test;
use Mojolicious::Lite;

plan skip_all => 'set TEST_ONLINE to enable this test' unless $ENV{TEST_ONLINE};

my $cavil_test = Cavil::Test->new(online => $ENV{TEST_ONLINE}, schema => 'classifier_llama_cpp_test');
my $config     = $cavil_test->default_config;
$config->{classifier} = {type => 'llama_cpp', url => 'http://127.0.0.1:5000', token => 'TEST:TOKEN:12345'};
my $t = Test::Mojo->new(Cavil => $config);
$cavil_test->mojo_fixtures($t->app);

app->log->level('error');

my $TOKEN  = 'MISSING TOKEN';
my $PROMPT = 'MISSING PROMPT';

post '/completion' => sub {
  my $c = shift;

  $TOKEN = $1 if ($c->req->headers->authorization // '') =~ /Bearer\s+(\S+)$/;

  my $input = $c->req->json;
  my $text  = $PROMPT = $input->{prompt};
  if ($text =~ /Fixed copyright notice/) {
    return $c->render(json => {content => 'yes', completion_probabilities => [{logprob => '-0.09171'}]});
  }
  elsif ($text =~ /This one is broken/) {
    return $c->render(json => {error => 'Classifier is broken'}, status => 400);
  }
  else {
    $c->render(json => {content => 'no', completion_probabilities => [{logprob => '-0.62496'}]});
  }
};

get '/*whatever' => {whatever => ''} => {text => '', status => 404};

# Connect mock server
my $classifier = $t->app->classifier;
is $classifier->type,  'llama_cpp',             'type has been configured';
is $classifier->url,   'http://127.0.0.1:5000', 'URL has been configured';
is $classifier->token, 'TEST:TOKEN:12345',      'token has been configured';
my $url = 'http://127.0.0.1:' . $classifier->ua->server->app(app)->url->port;
$classifier->url($url);

# Unpack and index. With a classifier configured, analysis enqueues the classify job for the snippets a
# package brings in, so processing a package also classifies them.
$t->app->minion->enqueue(unpack => [1]);
$t->app->minion->perform_jobs;
$t->app->pg->db->update('bot_packages', {embargoed => 1}, {id => 2});
my $embargoed_id = $t->app->pg->db->insert(
  'snippets',
  {hash      => 'manual:12345678890abcdef', text => 'Embargoed license text', package => 2},
  {returning => 'id'}
)->hash->{id};
$t->app->minion->enqueue(unpack => [2]);
$t->app->minion->perform_jobs;

subtest 'Classified automatically after indexing' => sub {
  my $snippet = $t->app->pg->db->select('snippets', '*', {id => 1})->hash;
  is $snippet->{id},         1,  'right id';
  is $snippet->{classified}, 1,  'classified';
  is $snippet->{license},    1,  'a license';
  is $snippet->{confidence}, 91, 'right confidence';
  like $snippet->{text}, qr/Fixed copyright notice/, 'right text';
  $snippet = $t->app->pg->db->select('snippets', '*', {id => 2})->hash;
  is $snippet->{id},         2,  'right id';
  is $snippet->{classified}, 1,  'classified';
  is $snippet->{license},    0,  'not a license';
  is $snippet->{confidence}, 54, 'right confidence';
  like $snippet->{text}, qr/This license establishes/, 'right text';

  # Embargoed snippets are left for humans and never sent to the classifier
  $snippet = $t->app->pg->db->select('snippets', '*', {id => $embargoed_id})->hash;
  is $snippet->{id},         $embargoed_id, 'right id';
  is $snippet->{classified}, 0,             'not classified';
  is $snippet->{license},    0,             'not a license';
  is $snippet->{confidence}, 0,             'not confidence';
  like $snippet->{text}, qr/Embargoed license text/, 'right text';
};

subtest 'Broken classifier is retryable' => sub {
  my $broken_id = $t->app->pg->db->insert(
    'snippets',
    {hash      => 'manual:12345678890abcde1', text => 'This one is broken', package => 1},
    {returning => 'id'}
  )->hash->{id};

  my $classify_id = $t->app->minion->enqueue('classify');
  $t->app->minion->perform_jobs;
  is $t->app->minion->job($classify_id)->info->{state}, 'failed', 'job is failed';
  like $t->app->minion->job($classify_id)->info->{result}, qr/Classifier is broken/, 'right error message';

  $t->app->pg->db->delete('snippets', {id => $broken_id});
  $t->app->minion->job($classify_id)->retry;
  $t->app->minion->perform_jobs;
  is $t->app->minion->job($classify_id)->info->{state}, 'finished', 'job finishes once the broken snippet is gone';
};

subtest 'Token authentication and prompt format' => sub {
  is_deeply $t->app->classifier->classify('Fixed copyright notice'), {confidence => '91.24', license => 1},
    'is legal text';
  is $TOKEN, 'TEST:TOKEN:12345', 'right token';
  like $PROMPT, qr/\[CODE\]Fixed copyright notice\[\/CODE\]/, 'right prompt';
};

done_testing;
