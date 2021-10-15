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
use Mojo::File qw(path tempdir);
use Mojo::JSON qw(decode_json);
use Cavil::Checkout;

plan skip_all => 'set TEST_ONLINE to enable this test' unless $ENV{TEST_ONLINE};

my $dir = path(__FILE__)->dirname->child('legal-bot');

sub report {
  my $report = eval path(__FILE__)->dirname->child('reports', shift)->slurp;
  return $@ ? die $@ : $report;
}

sub temp_copy {
  my $from   = $dir->child(@_);
  my $target = tempdir;
  $_->copy_to($target->child($_->basename)) for $from->list->each;
  return $target;
}

subtest 'ceph-image (kiwi)' => sub {
  my $ceph     = $dir->child('ceph-image', '5fcfdab0e71b0bebfdf8b5cc3badfecf');
  my $checkout = Cavil::Checkout->new($ceph);
  is_deeply $checkout->specfile_report, report('ceph-image.kiwi'), 'right kiwi report';
};

subtest 'go1.16-devel-container (Dockerfile)' => sub {
  my $go       = $dir->child('go1.16-devel-container', 'ffcfdab0e71b1bebfdf8b5cc3badfeca');
  my $checkout = Cavil::Checkout->new($go);
  is_deeply $checkout->specfile_report, report('go1.16-devel-container.dockerfile'), 'right dockerfile report';
};

subtest 'harbor-helm (Helm)' => sub {
  my $harbor   = $dir->child('harbor-helm', '4fcfdab0e71b0bebfdf8b5cc3badfec4');
  my $checkout = Cavil::Checkout->new($harbor);
  is_deeply $checkout->specfile_report, report('harbor-helm.helm'), 'right helm chart report';
};

subtest 'gnome-icon-theme' => sub {
  my $theme    = $dir->child('gnome-icon-theme', '6101f5eb933704aaad5dea63667110ac');
  my $checkout = Cavil::Checkout->new($theme);
  is_deeply $checkout->specfile_report, report('gnome-icon-theme.specfile'), 'right specfile report';
};

subtest 'gnome-menus' => sub {
  my $menus    = $dir->child('gnome-menus', 'aaacabb87b4356ac167f1a19458bc412');
  my $checkout = Cavil::Checkout->new($menus);
  is_deeply $checkout->specfile_report, report('gnome-menus.specfile'), 'right specfile report';
};

subtest 'gtk-vnc' => sub {
  my $vnc      = $dir->child('gtk-vnc', 'dbc35628c22fb9537a187e338c5e7007');
  my $checkout = Cavil::Checkout->new($vnc);
  is_deeply $checkout->specfile_report, report('gtk-vnc.specfile'), 'right specfile report';
};

subtest 'kmod' => sub {
  my $kmod     = $dir->child('kmod', 'a91003b451a34fe24defecdde1f2902e');
  my $checkout = Cavil::Checkout->new($kmod);
  is_deeply $checkout->specfile_report, report('kmod.specfile'), 'right specfile report';
};

subtest 'libqt4' => sub {
  my $qt       = $dir->child('libqt4', '9ec277c8a213f76119aa737e98f01959');
  my $checkout = Cavil::Checkout->new($qt);
  is_deeply $checkout->specfile_report, report('libqt4.specfile'), 'right specfile report';
};

subtest 'mono-core' => sub {
  my $mono     = $dir->child('mono-core', '610dad1a6b8dd8e36b021ab0291cd1d9');
  my $checkout = Cavil::Checkout->new($mono);
  is_deeply $checkout->specfile_report, report('mono-core.specfile'), 'right specfile report';
};

subtest 'perl-Mojolicious' => sub {
  my $mojo     = $dir->child('perl-Mojolicious', 'c7cfdab0e71b0bebfdf8b2dc3badfecd');
  my $checkout = Cavil::Checkout->new($mojo);
  is_deeply $checkout->specfile_report, report('perl-Mojolicious.specfile'), 'right specfile report';
  my $mojo_temp_dir = temp_copy('perl-Mojolicious', 'c7cfdab0e71b0bebfdf8b2dc3badfecd');
  $checkout = Cavil::Checkout->new($mojo_temp_dir);
  $checkout->unpack;
  my $json = $mojo_temp_dir->child('.unpacked.json');
  ok -f $json, 'log file exists';
  my $hash = decode_json($json->slurp);
  is $hash->{destdir}, $mojo_temp_dir->child('.unpacked'), 'right destination';
  is $hash->{pid}, $$, 'right process id';
  is_deeply $hash->{unpacked}{'Mojolicious-7.25/LICENSE'}, {mime => 'text/plain'}, 'right structure';
  ok -f $mojo_temp_dir->child('.unpacked', 'Mojolicious-7.25', 'LICENSE'), 'license file exists';
  my $module = $mojo_temp_dir->child('.unpacked', 'Mojolicious-7.25', 'lib', 'Mojolicious.pm');
  ok -f $module, 'module exists';

  # Check post processed
  $json = $mojo_temp_dir->child('.postprocessed.json');
  ok -f $json, '2nd log file exists';
  $hash = decode_json($json->slurp);

  my $maxed_file = 'Mojolicious-7.25/README.processed.md';
  is_deeply $hash->{unpacked}->{$maxed_file}, {mime => 'text/plain'}, 'file was maxed';
};

subtest 'plasma-nm5' => sub {
  my $nm5      = $dir->child('plasma-nm5', '4df243e211552e65b7146523c2f7051c');
  my $checkout = Cavil::Checkout->new($nm5);
  is_deeply $checkout->specfile_report, report('plasma-nm5.specfile'), 'right specfile report';
};

subtest 'timezone' => sub {
  my $tz       = $dir->child('timezone', '2724cdf3fada2aba427132fee8327b0f');
  my $checkout = Cavil::Checkout->new($tz);
  is_deeply $checkout->specfile_report, report('timezone.specfile'), 'right specfile report';
};

subtest 'wxWidgets-3_2' => sub {
  my $wx       = $dir->child('wxWidgets-3_2', '25014ee9d3640ebd9bc2370a2bbb5a63');
  my $checkout = Cavil::Checkout->new($wx);
  is_deeply $checkout->specfile_report, report('wxWidgets-3_2.specfile'), 'right specfile report';
};

subtest 'error-invalid-license' => sub {
  my $eil      = $dir->child('error-invalid-license', 'cb5e100e5a9a3e7f6d1fd97512215282');
  my $checkout = Cavil::Checkout->new($eil);
  is_deeply $checkout->specfile_report, report('error-invalid-license.specfile'), 'right specfile report';
};

subtest 'error-no-spdx' => sub {
  my $ens      = $dir->child('error-no-spdx', 'cb5e100e5a9a3e7f6d1fd97512215282');
  my $checkout = Cavil::Checkout->new($ens);
  is_deeply $checkout->specfile_report, report('error-no-spdx.specfile'), 'right specfile report';
};

subtest 'error-missing-main' => sub {
  my $emm      = $dir->child('error-missing-main', 'cb5e100e5a9a3e7f6d1fd97512215282');
  my $checkout = Cavil::Checkout->new($emm);
  is_deeply $checkout->specfile_report, report('error-missing-main.specfile'), 'right specfile report';
};

subtest 'error-missing-specfile' => sub {
  my $ems      = $dir->child('error-missing-specfile', 'cb5e100e5a9a3e7f6d1fd97512215282');
  my $checkout = Cavil::Checkout->new($ems);
  is_deeply $checkout->specfile_report, report('error-missing-specfile.specfile'), 'right specfile report';
};

subtest 'error-broken-archive' => sub {
  my $eba      = temp_copy('error-broken-archive', 'cb5e100e5a9a3e7f6d1fd97512215282');
  my $checkout = Cavil::Checkout->new($eba);
  $checkout->unpack;
  my $json = $eba->child('.unpacked.json');
  ok -f $json, 'log file exists';
  my $hash = decode_json($json->slurp);
  is $hash->{destdir}, $eba->child('.unpacked'), 'right destination';
  is $hash->{pid}, $$, 'right process id';
  is_deeply $hash->{unpacked}{'error-broken-archive/test.txt'}, {mime => 'text/plain'}, 'right structure';
};

subtest 'error-missing-main-kiwi' => sub {
  my $emmk     = $dir->child('error-missing-main-kiwi', 'aacfdab0e71b0bebfdf8b5cc3badfecf');
  my $checkout = Cavil::Checkout->new($emmk);
  is_deeply $checkout->specfile_report, report('error-missing-main-kiwi.kiwi'), 'right kiwi report';
};

subtest 'error-missing-kiwifile' => sub {
  my $emmk     = $dir->child('error-missing-kiwifile', 'bbcfdab0e71b0bebfdf8b5cc3badfecf');
  my $checkout = Cavil::Checkout->new($emmk);
  is_deeply $checkout->specfile_report, report('error-missing-kiwifile.kiwi'), 'right kiwi report';
};

subtest 'error-missing-main-dockerfile' => sub {
  my $docker   = $dir->child('error-missing-main-dockerfile', '56cfdab0e71b0bebfdf8b5cc3badfe23');
  my $checkout = Cavil::Checkout->new($docker);
  is_deeply $checkout->specfile_report, report('error-missing-main-dockerfile.dockerfile'), 'right kiwi report';
};

subtest 'error-missing-main-helm' => sub {
  my $helm     = $dir->child('error-missing-main-helm', '86cfdab0e71b0bebfdf8b5cc3badfe2f');
  my $checkout = Cavil::Checkout->new($helm);
  is_deeply $checkout->specfile_report, report('error-missing-main-helm.helm'), 'right kiwi report';
};

subtest 'Unpack background job' => sub {
  my $cavil_test = Cavil::Test->new(online => $ENV{TEST_ONLINE}, schema => 'unpack_test');
  my $t          = Test::Mojo->new(Cavil => $cavil_test->default_config);
  $cavil_test->mojo_fixtures($t->app);

  ok !$t->app->packages->is_unpacked(1), 'not unpacked yet';
  my $minion = $t->app->minion;
  my $job_id = $minion->enqueue(unpack => [1]);
  $minion->perform_jobs;
  ok $t->app->packages->is_unpacked(1), 'unpacked';
  unlike $minion->job($job_id)->info->{result}, qr/Package \d+ is already being processed/, 'no race condition';

  my $dir  = $cavil_test->checkout_dir->child('perl-Mojolicious', 'c7cfdab0e71b0bebfdf8b2dc3badfecd');
  my $json = $dir->child('.unpacked.json');
  ok -f $json, 'log file exists';
  my $hash = decode_json($json->slurp);
  is $hash->{destdir}, $dir->child('.unpacked'), 'right destination';
  ok -f $dir->child('.unpacked', 'Mojolicious-7.25', 'LICENSE'), 'license file exists';
  my $module = $dir->child('.unpacked', 'Mojolicious-7.25', 'lib', 'Mojolicious.pm');
  ok -f $module, 'module exists';
  ok -f $cavil_test->cache_dir->child('cavil.tokens'), 'cache initialized';

  # Prevent import race condition
  ok $minion->job($job_id)->retry, 'unpack job retried';
  my $guard = $minion->guard('processing_pkg_1', 172800);
  ok !$minion->lock('processing_pkg_1', 0), 'lock exists';
  my $worker = $minion->worker->register;
  ok my $job = $worker->dequeue(0, {id => $job_id}), 'job dequeued';
  is $job->execute, undef, 'no error';
  like $minion->job($job_id)->info->{result}, qr/Package \d+ is already being processed/, 'race condition prevented';
  $worker->unregister;
  undef $guard;
  ok $minion->lock('processing_pkg_1', 0), 'lock no longer exists';
};

done_testing;
