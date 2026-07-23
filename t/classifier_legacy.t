# Copyright 2018-2026 SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Mojo::Base -strict, -signatures;

use FindBin;
use lib "$FindBin::Bin/lib";

use Test::More;
use Test::Mojo;
use Cavil::Test;
use Mojolicious::Lite;

plan skip_all => 'set TEST_ONLINE to enable this test' unless $ENV{TEST_ONLINE};

my $cavil_test = Cavil::Test->new(online => $ENV{TEST_ONLINE}, schema => 'classifier_legacy_test');
my $config     = $cavil_test->default_config;
$config->{classifier} = {type => 'legacy', url => 'http://127.0.0.1:5000', token => 'TEST:TOKEN:12345'};
my $t = Test::Mojo->new(Cavil => $config);
$cavil_test->mojo_fixtures($t->app);

app->log->level('error');

my $TOKEN = 'MISSING TOKEN';

post '/' => sub {
  my $c = shift;

  $TOKEN = $1 if ($c->req->headers->authorization // '') =~ /Token\s+(\S+)$/;

  my $text = $c->req->body;
  if ($text =~ /Fixed copyright notice/) {
    return $c->render(json => {license => \1, confidence => '98.123'});
  }
  elsif ($text =~ /This one is broken/) {
    return $c->render(json => {error => 'Classifier is broken'}, status => 400);
  }
  elsif (length($text) > 8000) {
    return $c->render(json => {error => 'Payload too large'}, status => 413);
  }
  else {
    $c->render(json => {license => \0, confidence => '55.321'});
  }
};

get '/*whatever' => {whatever => ''} => {text => '', status => 404};

# Connect mock server
my $classifier = $t->app->classifier;
is $classifier->type,  'legacy',                'type has been configured';
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
  is $snippet->{confidence}, 98, 'right confidence';
  like $snippet->{text}, qr/Fixed copyright notice/, 'right text';
  $snippet = $t->app->pg->db->select('snippets', '*', {id => 2})->hash;
  is $snippet->{id},         2,  'right id';
  is $snippet->{classified}, 1,  'classified';
  is $snippet->{license},    0,  'not a license';
  is $snippet->{confidence}, 55, 'right confidence';
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

subtest 'Token authentication' => sub {
  is_deeply $t->app->classifier->classify('Fixed copyright notice'), {confidence => '98.123', license => 1},
    'is legal text';
  is $TOKEN, 'TEST:TOKEN:12345', 'right token';
};

subtest 'Ultra-long minified lines are resolved as non-license without hitting the classifier' => sub {

  # A minified bundle: a short license comment, then the whole file as one enormous line. A real
  # classifier chokes on a payload this size (the mock returns 413 to mirror that), so the guard must
  # resolve it as non-license without sending it - otherwise the whole classify job would fail.
  my $giant = '/*! license */ ' . ('a' x 20000);
  my $sid   = $t->app->pg->db->insert(
    'snippets',
    {hash      => 'manual:giant-minified-line', text => $giant, package => 1},
    {returning => 'id'}
  )->hash->{id};

  my $classify_id = $t->app->minion->enqueue('classify');
  $t->app->minion->perform_jobs;
  is $t->app->minion->job($classify_id)->info->{state}, 'finished', 'classify finished despite the oversized snippet';

  my $snippet = $t->app->pg->db->select('snippets', '*', {id => $sid})->hash;
  is $snippet->{classified}, 1, 'oversized snippet was resolved';
  is $snippet->{license},    0, 'as non-license (machine code, never sent to the classifier)';
};

subtest 'Classified manually' => sub {
  $t->app->pg->db->update('snippets', {license => 0, approved => 0, classified => 0});
  my $snippet = $t->app->pg->db->select('snippets', '*', {id => 1})->hash;
  is $snippet->{id},         1, 'right id';
  is $snippet->{classified}, 0, 'classified';
  is $snippet->{license},    0, 'license';
  $snippet = $t->app->pg->db->select('snippets', '*', {id => 2})->hash;
  is $snippet->{id},         2, 'right id';
  is $snippet->{classified}, 0, 'classified';
  is $snippet->{license},    0, 'license';
  $snippet = $t->app->pg->db->select('snippets', '*', {id => $embargoed_id})->hash;
  is $snippet->{id},         $embargoed_id, 'right id';
  is $snippet->{classified}, 0,             'classified';
  is $snippet->{license},    0,             'license';

  $t->get_ok('/login')->status_is(302);

  my $mark_non_license = sub ($sid, $hash) {
    $t->post_ok('/snippet/batch_decision' => json =>
        {actions => [{kind => 'mark-non-license', snippetId => $sid + 0, formData => {hash => $hash}}]})
      ->status_is(200);
  };

  $mark_non_license->(2, '3c376fca10ff8a41d0d51c9d46a3bdae');
  $snippet = $t->app->pg->db->select('snippets', '*', {id => 1})->hash;
  is $snippet->{id},         1, 'right id';
  is $snippet->{classified}, 0, 'classified';
  is $snippet->{license},    0, 'license';
  $snippet = $t->app->pg->db->select('snippets', '*', {id => 2})->hash;
  is $snippet->{id},         2, 'right id';
  is $snippet->{classified}, 1, 'classified';
  is $snippet->{license},    0, 'license';

  $mark_non_license->(1, '81efb065de14988c4bd808697de1df51');
  $snippet = $t->app->pg->db->select('snippets', '*', {id => 1})->hash;
  is $snippet->{id},         1, 'right id';
  is $snippet->{classified}, 1, 'classified';
  is $snippet->{license},    0, 'license';

  $mark_non_license->($embargoed_id, 'manual:12345678890abcdef');
  $snippet = $t->app->pg->db->select('snippets', '*', {id => $embargoed_id})->hash;
  is $snippet->{id},         $embargoed_id, 'right id';
  is $snippet->{classified}, 1,             'classified';
  is $snippet->{license},    0,             'license';
};

done_testing;
