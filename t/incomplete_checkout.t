# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Mojo::Base -strict;

use FindBin;
use lib "$FindBin::Bin/lib";

use Test::More;
use Test::Mojo;
use Cavil::Test;
use Cavil::ReportUtil qw(report_checksum);
use Mojo::File        qw(path);

plan skip_all => 'set TEST_ONLINE to enable this test' unless $ENV{TEST_ONLINE};

my $cavil_test = Cavil::Test->new(online => $ENV{TEST_ONLINE}, schema => 'incomplete_checkout_test');
my $config     = $cavil_test->default_config;
my $t          = Test::Mojo->new(Cavil => $config);
$cavil_test->mojo_fixtures($t->app);

$t->app->minion->enqueue(unpack => [1]);
$t->app->minion->enqueue(unpack => [2]);
$t->app->minion->perform_jobs;
is $t->app->packages->find(1)->{state}, 'new', 'still new';
is $t->app->packages->find(2)->{state}, 'new', 'still new';

subtest 'Do not auto-accept incomplete checkouts' => sub {
  my $dir = $cavil_test->checkout_dir;
  $dir->child('perl-Mojolicious', 'c7cfdab0e71b0bebfdf8b2dc3badfecd', 'perl-Mojolicious.spec')
    ->copy_to(
    $dir->child('perl-Mojolicious', 'da3e32a3cce8bada03c6a9d63c08cd58', '.unpacked', 'perl-Mojolicious.spec'));
  my $file = $dir->child('perl-Mojolicious', 'da3e32a3cce8bada03c6a9d63c08cd58', '.unpacked', '_service');
  $file->spew(<<EOF);
<services>
  <service name="download_files" mode="trylocal" />
</services>
EOF

  my $pkg = $t->app->packages->find(1);
  $pkg->{state}          = 'acceptable';
  $pkg->{reviewing_user} = 1;
  $t->app->packages->update($pkg);

  $t->app->minion->enqueue('reindex_all');
  $t->app->minion->perform_jobs;

  $pkg = $t->app->packages->find(1);
  is $pkg->{state}, 'acceptable', 'has been accepted';
  my $pkg2 = $t->app->packages->find(2);
  is $pkg2->{state}, 'new', 'still new';
  like $pkg2->{notice}, qr/Not found.+ manual review is required because the checkout might be incomplete/,
    'notice about incomplete checkout';
};

done_testing();
