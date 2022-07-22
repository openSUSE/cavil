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

use FindBin;
use lib "$FindBin::Bin/lib";

use Test::More;
use Test::Mojo;
use Cavil::Test;
use Mojolicious::Lite;

plan skip_all => 'set TEST_ONLINE to enable this test' unless $ENV{TEST_ONLINE};

my $cavil_test = Cavil::Test->new(online => $ENV{TEST_ONLINE}, schema => 'classifier_test');
my $config     = $cavil_test->default_config;
$config->{classifier} = 'http://127.0.0.1:5000';
my $t = Test::Mojo->new(Cavil => $config);
$cavil_test->mojo_fixtures($t->app);

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

# Connect mock server
my $classifier = $t->app->classifier;
is $classifier->url, 'http://127.0.0.1:5000', 'URL has been configured';
my $url = 'http://127.0.0.1:' . $classifier->ua->server->app(app)->url->port;
$classifier->url($url);

# Unpack and index
$t->app->minion->enqueue(unpack => [1]);
$t->app->minion->perform_jobs;

subtest 'Not yet classified' => sub {
  my $snippet = $t->app->pg->db->select('snippets', '*', {id => 1})->hash;
  is $snippet->{id},         1, 'right id';
  is $snippet->{classified}, 0, 'not classified';
  is $snippet->{license},    0, 'not a license';
  is $snippet->{confidence}, 0, 'not confidence';
  like $snippet->{text}, qr/Fixed copyright notice/, 'right text';
  $snippet = $t->app->pg->db->select('snippets', '*', {id => 2})->hash;
  is $snippet->{id},         2, 'right id';
  is $snippet->{classified}, 0, 'not classified';
  is $snippet->{license},    0, 'not a license';
  is $snippet->{confidence}, 0, 'not confidence';
  like $snippet->{text}, qr/This license establishes/, 'right text';
};

# Classify
my $classify_id = $t->app->minion->enqueue('classify');
$t->app->minion->perform_jobs;

subtest 'Classified' => sub {
  my $snippet = $t->app->pg->db->select('snippets', '*', {id => 1})->hash;
  is $snippet->{id},         1,  'right id';
  is $snippet->{classified}, 1,  'classified';
  is $snippet->{license},    1,  'license';
  is $snippet->{confidence}, 98, 'confidence';
  like $snippet->{text}, qr/Fixed copyright notice/, 'right text';
  $snippet = $t->app->pg->db->select('snippets', '*', {id => 2})->hash;
  is $snippet->{id},         2,  'right id';
  is $snippet->{classified}, 1,  'classified';
  is $snippet->{license},    0,  'not a license';
  is $snippet->{confidence}, 55, 'confidence';
  like $snippet->{text}, qr/This license establishes/, 'right text';
};

done_testing;
