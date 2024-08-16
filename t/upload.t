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
use Mojo::File qw(path);
use Mojo::JSON qw(decode_json);

plan skip_all => 'set TEST_ONLINE to enable this test' unless $ENV{TEST_ONLINE};

my $cavil_test = Cavil::Test->new(online => $ENV{TEST_ONLINE}, schema => 'upload_test');
my $config     = $cavil_test->default_config;
my $t          = Test::Mojo->new(Cavil => $config);
$cavil_test->mojo_fixtures($t->app);
$t->app->minion->perform_jobs;

subtest 'Permissions' => sub {
  $t->get_ok('/upload')->status_is(403);
  $t->post_ok('/upload')->status_is(403);
  $t->get_ok('/login')->status_is(302)->header_is(Location => '/');
  $t->get_ok('/upload')->status_is(200)->element_exists('input[name=name]');
};

subtest 'Validation' => sub {
  $t->get_ok('/upload')->status_is(200)->element_exists_not('input[class~=field-with-error]');
  $t->post_ok('/upload')->status_is(200)->element_exists('input[name=name][class~=field-with-error]');
  $t->post_ok('/upload', form => {name => 'perl-Mojolicious'})->status_is(200)
    ->element_exists_not('input[name=name][class~=field-with-error]')
    ->element_exists('input[name=licenses][class~=field-with-error]');
  $t->post_ok('/upload', form => {name => 'perl-Mojolicious', licenses => 'Artistic-2.0'})->status_is(200)
    ->element_exists_not('input[name=name][class~=field-with-error]')
    ->element_exists_not('input[name=licenses][class~=field-with-error]')
    ->element_exists('input[name=tarball][class~=field-with-error]');
};

subtest 'Upload' => sub {
  $t->get_ok('/reviews/details/1')->status_is(200);
  $t->get_ok('/reviews/details/2')->status_is(200);
  $t->get_ok('/reviews/details/3')->status_is(404);
  $t->post_ok(
    '/upload',
    form => {
      name     => 'perl-Mojolicious',
      version  => '7.25',
      licenses => 'Artistic-2.0',
      priority => '6',
      tarball  => {
        file => path(__FILE__)->dirname->child('legal-bot', 'perl-Mojolicious', 'c7cfdab0e71b0bebfdf8b2dc3badfecd',
          'Mojolicious-7.25.tar.gz')->to_string
      }
    }
  )->status_is(302)->header_is(Location => '/');
  $t->get_ok('/')->status_is(200)
    ->content_like(qr/Package perl-Mojolicious has been uploaded and is now being processed/);
  $t->get_ok('/reviews/details/3')->status_is(200);
  $t->get_ok('/reviews/calc_report/3.json')->status_is(408);

  my $pkg  = $t->app->packages->find(3);
  my $json = path($cavil_test->checkout_dir)->child('perl-Mojolicious', $pkg->{checkout_dir}, '.cavil.json');
  ok -f $json, 'JSON file has been generated';
  is_deeply decode_json($json->slurp), {licenses => 'Artistic-2.0', version => '7.25'}, 'right structure';

  my $tarball
    = path($cavil_test->checkout_dir)->child('perl-Mojolicious', $pkg->{checkout_dir}, 'Mojolicious-7.25.tar.gz');
  ok -f $tarball, 'tarball exists';

  my $unpacked = path($cavil_test->checkout_dir)->child('perl-Mojolicious', $pkg->{checkout_dir}, '.unpacked');
  ok !-d $unpacked, 'not yet unpacked';
};

subtest 'Indexing' => sub {
  $t->app->minion->perform_jobs;
  my $unpacked = path($cavil_test->checkout_dir)
    ->child('perl-Mojolicious', $t->app->packages->find(3)->{checkout_dir}, '.unpacked');
  ok -d $unpacked, 'unpacked';

  $t->get_ok('/reviews/calc_report/3.json')->header_like(Vary => qr/Accept-Encoding/)->status_is(200);
  ok my $json = $t->tx->res->json, 'JSON response';

  ok my $pkg = $json->{package}, 'package';
  is $pkg->{id},   3,                  'id';
  is $pkg->{name}, 'perl-Mojolicious', 'name';
  like $pkg->{checksum}, qr!Artistic-2.0-9!, 'checksum';
  is $pkg->{login},  undef,                                                                 'no login';
  is $pkg->{state},  'new',                                                                 'state';
  is $pkg->{result}, 'Manual review is required because no previous reports are available', 'requires manual review';

  ok my $report = $json->{report}, 'report';
  is $report->{urls}[0][0], 'http://mojolicious.org', 'right URL';
  ok $report->{urls}[0][1], 'multiple matches';

  ok my $missed_files = $report->{missed_files}, 'missed files';
  is $missed_files->[0]{id},       1,         'id';
  is $missed_files->[0]{license},  'Snippet', 'license';
  is $missed_files->[0]{match},    0,         'no match';
  is $missed_files->[0]{max_risk}, 9,         'max risk';

  ok $report->{files}, 'files';
  ok my $licenses = $report->{licenses},       'licenses';
  ok my $apache   = $licenses->{'Apache-2.0'}, 'Apache';
  is $apache->{name}, 'Apache-2.0', 'name';
  is $apache->{risk}, 5,            'risk';
};

done_testing();
