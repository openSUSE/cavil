# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Mojo::Base -strict;

use FindBin;
use lib "$FindBin::Bin/lib";

use Test::More;
use Test::Mojo;
use Cavil::Test;
use Cavil::Util qw(incoming_priority PRIORITY_INCOMING PRIORITY_UPKEEP);
use Mojo::File  qw(path tempdir);

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
  $t->get_ok('/upload')->status_is(200)->element_exists('#archive-upload');
};

subtest 'Validation' => sub {
  $t->post_ok('/upload', {Accept => 'application/json'})->status_is(400)->json_like('/error', qr/Invalid upload/);
  $t->post_ok('/upload', {Accept => 'application/json'}, form => {name => 'perl-Mojolicious', priority => 5})
    ->status_is(400)
    ->json_like('/error', qr/tarball/);

  # Without a JSON Accept header validation errors redirect back to the form
  $t->post_ok('/upload')->status_is(302)->header_is(Location => '/upload');
};

subtest 'Upload' => sub {
  $t->get_ok('/reviews/details/1')->status_is(200);
  $t->get_ok('/reviews/details/2')->status_is(200);
  $t->get_ok('/reviews/details/3')->status_is(404);

  # No package metadata is required, only the archive (name is prefilled from the filename in the UI)
  $t->post_ok(
    '/upload',
    {Accept => 'application/json'},
    form => {
      name     => 'perl-Mojolicious',
      priority => '6',
      tarball  => {
        file => path(__FILE__)->dirname->child('legal-bot', 'perl-Mojolicious', 'c7cfdab0e71b0bebfdf8b2dc3badfecd',
          'Mojolicious-7.25.tar.gz')->to_string
      }
    }
    )
    ->status_is(200)
    ->json_is('/id'   => 3)
    ->json_is('/name' => 'perl-Mojolicious')
    ->json_like('/url', qr!/reviews/details/3!);

  # Re-uploading the same archive under the same name is rejected as a duplicate
  $t->post_ok(
    '/upload',
    {Accept => 'application/json'},
    form => {
      name     => 'perl-Mojolicious',
      priority => '6',
      tarball  => {
        file => path(__FILE__)->dirname->child('legal-bot', 'perl-Mojolicious', 'c7cfdab0e71b0bebfdf8b2dc3badfecd',
          'Mojolicious-7.25.tar.gz')->to_string
      }
    }
  )->status_is(409)->json_like('/error', qr/already exists/);

  $t->get_ok('/reviews/details/3')->status_is(200);
  $t->get_ok('/reviews/report/3.json')->status_is(408);

  my $pkg = $t->app->packages->find(3);
  is $pkg->{priority}, 6, 'priority taken from the form';

  # An uploaded archive is an arriving package, and the priority on the form moves it around inside the
  # incoming band the same way the one a Bot API request carries does
  my $unpack = $t->app->minion->jobs({tasks => ['unpack'], states => ['inactive']})->next;
  is $unpack->{priority}, incoming_priority(6), 'queued in the incoming band, one step up for the form priority';

  # The checkout directory must be the real content hash of the archive (not the md5 of an
  # empty stream), otherwise different archives uploaded under the same name would collide
  is $pkg->{checkout_dir}, 'c1ffb4256878c64eb0e40c48f36d24d2', 'checkout_dir is the archive content hash';

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

  $t->get_ok('/reviews/report/3.json')->header_like(Vary => qr/Accept-Encoding/)->status_is(200);
  ok my $json = $t->tx->res->json, 'JSON response';

  ok my $pkg = $json->{package}, 'package';
  is $pkg->{id},   3,                  'id';
  is $pkg->{name}, 'perl-Mojolicious', 'name';

  # No declared license (the archive has no package file), so it canonicalizes to "Unknown"
  like $pkg->{checksum}, qr!Unknown-9!, 'checksum';
  is $pkg->{login},  undef,                                                                 'no login';
  is $pkg->{state},  'new',                                                                 'state';
  is $pkg->{notice}, 'Manual review is required because no previous reports are available', 'requires manual review';

  ok my $report = $json->{report}, 'report';
  is $report->{urls}[0][0], 'http://mojolicious.org', 'right URL';
  ok $report->{urls}[0][1], 'multiple matches';

  ok my $missed_files = $report->{missed_files}, 'missed files';
  is $missed_files->[0]{id},       1,         'id';
  is $missed_files->[0]{license},  'Keyword', 'license';
  is $missed_files->[0]{match},    0,         'no match';
  is $missed_files->[0]{max_risk}, 9,         'max risk';

  ok $report->{files}, 'files';
  ok my $licenses = $report->{licenses},       'licenses';
  ok my $apache   = $licenses->{'Apache-2.0'}, 'Apache';
  is $apache->{name}, 'Apache-2.0', 'name';
  is $apache->{risk}, 5,            'risk';
};

subtest 'Auto-detected metadata from an embedded package file' => sub {
  my $tmp = tempdir;
  my $src = $tmp->child('cavil-demo-1.2.3')->make_path;
  $src->child('cavil-demo.spec')->spew("Name: cavil-demo\nVersion: 1.2.3\nLicense: MIT\nSummary: Demo package\n");
  $src->child('README')->spew("Just a demo\n");
  my $archive = $tmp->child('cavil-demo-1.2.3.tar.gz');
  is system('tar', '-czf', $archive->to_string, '-C', $tmp->to_string, 'cavil-demo-1.2.3'), 0, 'archive created';

  $t->post_ok(
    '/upload',
    {Accept => 'application/json'},
    form => {name => 'cavil-demo', priority => '5', tarball => {file => $archive->to_string}}
  )->status_is(200)->json_is('/id' => 4)->json_is('/name' => 'cavil-demo');

  $t->app->minion->perform_jobs;
  $t->get_ok('/reviews/report/4.json')->status_is(200);
  ok my $pkg = $t->tx->res->json->{package}, 'package';

  # The spec inside the archive (one wrapper directory deep) is auto-detected as the main file
  like $pkg->{checksum}, qr!MIT-!, 'license auto-detected from embedded spec';
};

subtest 'Same name with different content is not a false duplicate' => sub {
  my $tmp = tempdir;
  my @ids;
  for my $variant (qw(alpha beta)) {
    my $src = $tmp->child("src-$variant")->make_path;
    $src->child('file.txt')->spew("content $variant\n");
    my $archive = $tmp->child("$variant.tar.gz");
    is system('tar', '-czf', $archive->to_string, '-C', $src->to_string, '.'), 0, "$variant archive created";
    $t->post_ok(
      '/upload',
      {Accept => 'application/json'},
      form => {name => 'dup-name', priority => '5', tarball => {file => $archive->to_string}}
    )->status_is(200);
    push @ids, $t->tx->res->json->{id};
  }
  isnt $ids[0], $ids[1], 'two different archives under the same name create distinct packages';
};

subtest 'Non-JSON upload redirects to the dashboard' => sub {
  $t->post_ok(
    '/upload',
    form => {
      name     => 'perl-Mojo-Redirect',
      priority => '5',
      tarball  => {
        file => path(__FILE__)->dirname->child('legal-bot', 'perl-Mojolicious', 'c7cfdab0e71b0bebfdf8b2dc3badfecd',
          'Mojolicious-7.25.tar.gz')->to_string
      }
    }
  )->status_is(302)->header_is(Location => '/');
  $t->get_ok('/')->status_is(200)->content_like(qr/perl-Mojo-Redirect has been uploaded/);
  ok $t->app->packages->find_by_name_and_md5('perl-Mojo-Redirect', 'c1ffb4256878c64eb0e40c48f36d24d2'),
    'package created via the redirect path';
};

subtest 'Ephemeral upload is flagged and runs a band below normal incoming' => sub {
  my $tmp = tempdir;
  my $src = $tmp->child('eph')->make_path;
  $src->child('file.txt')->spew("ephemeral content\n");
  my $archive = $tmp->child('eph.tar.gz');
  is system('tar', '-czf', $archive->to_string, '-C', $src->to_string, '.'), 0, 'ephemeral archive created';

  $t->post_ok(
    '/upload',
    {Accept => 'application/json'},
    form => {name => 'eph-web', priority => '6', ephemeral => 1, tarball => {file => $archive->to_string}}
  )->status_is(200);
  my $id = $t->tx->res->json->{id};

  ok $t->app->packages->find($id)->{ephemeral}, 'package is flagged ephemeral';

  my $unpack = $t->app->minion->jobs({tasks => ['unpack'], notes => ["pkg_$id"]})->next;
  is $unpack->{priority}, incoming_priority(6) - (PRIORITY_INCOMING - PRIORITY_UPKEEP),
    'queued a whole band below normal incoming';

  # The report metadata hints that the review is ephemeral and when it will be deleted
  $t->app->minion->perform_jobs;
  $t->get_ok("/reviews/meta/$id")->status_is(200);
  ok $t->tx->res->json('/ephemeral'), 'metadata marks the report ephemeral';
  my $meta = $t->tx->res->json;
  is $meta->{ephemeral_delete}, $meta->{created} + 24 * 3600, 'deletion time is created plus the configured window';
};

subtest 'Ephemeral reviews are listed together in every state' => sub {
  my $tmp = tempdir;
  my $src = $tmp->child('eph2')->make_path;
  $src->child('file.txt')->spew("second ephemeral content\n");
  my $archive = $tmp->child('eph2.tar.gz');
  is system('tar', '-czf', $archive->to_string, '-C', $src->to_string, '.'), 0, 'second ephemeral archive created';

  $t->post_ok(
    '/upload',
    {Accept => 'application/json'},
    form => {name => 'eph-accepted', priority => '5', ephemeral => 1, tarball => {file => $archive->to_string}}
  )->status_is(200);
  my $id2 = $t->tx->res->json->{id};
  $t->app->minion->perform_jobs;

  # Force two different states so the listing is proven not to filter by state
  my $id1 = $t->app->pg->db->select('bot_packages', 'id', {name => 'eph-web'})->hash->{id};
  $t->app->packages->update({id => $id1, state => 'new'});
  $t->app->packages->update({id => $id2, state => 'acceptable'});

  $t->get_ok('/pagination/reviews/ephemeral')->status_is(200);
  my $page  = $t->tx->res->json;
  my %by_id = map { $_->{id} => $_ } @{$page->{page}};
  ok $by_id{$id1},        'new-state ephemeral review is listed';
  ok $by_id{$id2},        'acceptable-state ephemeral review is listed';
  ok !$by_id{3},          'a normal (non-ephemeral) package is not listed';
  ok $by_id{$id1}{login}, 'uploader login is present';
  is $by_id{$id1}{ephemeral_delete}, $by_id{$id1}{created_epoch} + 24 * 3600, 'row carries the scheduled deletion time';
};

done_testing();
