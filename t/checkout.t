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

use Mojo::Base -strict, -signatures;

use FindBin;
use lib "$FindBin::Bin/lib";

use Test::More;
use Test::Mojo;
use Cavil::Test;
use Mojo::File qw(path curfile tempdir);
use Mojo::JSON qw(decode_json);
use Cavil::Checkout;

plan skip_all => 'set TEST_ONLINE to enable this test' unless $ENV{TEST_ONLINE};

my $dir = path(__FILE__)->dirname->child('legal-bot');

sub report {
  my $report = eval path(__FILE__)->dirname->child('reports', shift)->slurp;
  return $@ ? die $@ : $report;
}

my $TMP = tempdir;

sub temp_copy (@path) {
  my $from   = $dir->child(@path);
  my $target = $TMP->child(@path)->make_path;
  $_->copy_to($target->child($_->basename)) for $from->list({hidden => 1})->each;

  my $deb_test = $from->child('debian');
  if (-d $deb_test) {
    my $deb_dir = $target->child('debian')->make_path;
    $_->copy_to($deb_dir->child($_->basename)) for $deb_test->list->each;
  }

  return $target;
}

subtest 'ceph-image (kiwi)' => sub {
  my $ceph     = temp_copy('ceph-image', '5fcfdab0e71b0bebfdf8b5cc3badfecf');
  my $checkout = Cavil::Checkout->new($ceph);
  $checkout->unpack;
  is_deeply $checkout->specfile_report, report('ceph-image.kiwi'), 'right kiwi report';
};

subtest 'go1.16-devel-container (Dockerfile)' => sub {
  my $go       = temp_copy('go1.16-devel-container', 'ffcfdab0e71b1bebfdf8b5cc3badfeca');
  my $checkout = Cavil::Checkout->new($go);
  $checkout->unpack;
  is_deeply $checkout->specfile_report, report('go1.16-devel-container.dockerfile'), 'right dockerfile report';
};

subtest 'harbor-helm (Helm)' => sub {
  my $harbor   = temp_copy('harbor-helm', '4fcfdab0e71b0bebfdf8b5cc3badfec4');
  my $checkout = Cavil::Checkout->new($harbor);
  $checkout->unpack;
  is_deeply $checkout->specfile_report, report('harbor-helm.helm'), 'right helm chart report';
};

subtest 'libfsverity0 (DEB)' => sub {
  my $libfs    = temp_copy('libfsverity0', '9932c13432c3c5bdbe260ab8bc3b13ef');
  my $checkout = Cavil::Checkout->new($libfs);
  $checkout->unpack;
  is_deeply $checkout->specfile_report, report('libfsverity0.deb'), 'right deb report';
};

subtest 'gnome-icon-theme' => sub {
  my $theme    = temp_copy('gnome-icon-theme', '6101f5eb933704aaad5dea63667110ac');
  my $checkout = Cavil::Checkout->new($theme);
  $checkout->unpack;
  is_deeply $checkout->specfile_report, report('gnome-icon-theme.specfile'), 'right specfile report';
};

subtest 'gnome-menus' => sub {
  my $menus    = temp_copy('gnome-menus', 'aaacabb87b4356ac167f1a19458bc412');
  my $checkout = Cavil::Checkout->new($menus);
  $checkout->unpack;
  is_deeply $checkout->specfile_report, report('gnome-menus.specfile'), 'right specfile report';
};

subtest 'gtk-vnc' => sub {
  my $vnc      = temp_copy('gtk-vnc', 'dbc35628c22fb9537a187e338c5e7007');
  my $checkout = Cavil::Checkout->new($vnc);
  $checkout->unpack;
  is_deeply $checkout->specfile_report, report('gtk-vnc.specfile'), 'right specfile report';
};

subtest 'kmod' => sub {
  my $kmod     = temp_copy('kmod', 'a91003b451a34fe24defecdde1f2902e');
  my $checkout = Cavil::Checkout->new($kmod);
  $checkout->unpack;
  is_deeply $checkout->specfile_report, report('kmod.specfile'), 'right specfile report';
};

subtest 'libqt4' => sub {
  my $qt       = temp_copy('libqt4', '9ec277c8a213f76119aa737e98f01959');
  my $checkout = Cavil::Checkout->new($qt);
  $checkout->unpack;
  is_deeply $checkout->specfile_report, report('libqt4.specfile'), 'right specfile report';
};

subtest 'mono-core' => sub {
  my $mono     = temp_copy('mono-core', '610dad1a6b8dd8e36b021ab0291cd1d9');
  my $checkout = Cavil::Checkout->new($mono);
  $checkout->unpack;
  is_deeply $checkout->specfile_report, report('mono-core.specfile'), 'right specfile report';
};

subtest 'perl-Mojolicious' => sub {
  my $mojo     = temp_copy('perl-Mojolicious', 'c7cfdab0e71b0bebfdf8b2dc3badfecd');
  my $checkout = Cavil::Checkout->new($mojo);
  $checkout->unpack;
  is_deeply $checkout->specfile_report, report('perl-Mojolicious.specfile'), 'right specfile report';
  my $mojo_temp_dir = temp_copy('perl-Mojolicious', 'c7cfdab0e71b0bebfdf8b2dc3badfecd');
  $checkout = Cavil::Checkout->new($mojo_temp_dir);
  $checkout->unpack;
  my $json = $mojo_temp_dir->child('.unpacked.json');
  ok -f $json, 'log file exists';
  my $hash = decode_json($json->slurp);
  is $hash->{destdir}, $mojo_temp_dir->child('.unpacked'), 'right destination';
  is $hash->{pid},     $$,                                 'right process id';
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
  my $nm5      = temp_copy('plasma-nm5', '4df243e211552e65b7146523c2f7051c');
  my $checkout = Cavil::Checkout->new($nm5);
  $checkout->unpack;
  is_deeply $checkout->specfile_report, report('plasma-nm5.specfile'), 'right specfile report';
};

subtest 'timezone' => sub {
  my $tz       = temp_copy('timezone', '2724cdf3fada2aba427132fee8327b0f');
  my $checkout = Cavil::Checkout->new($tz);
  $checkout->unpack;
  is_deeply $checkout->specfile_report, report('timezone.specfile'), 'right specfile report';
};

subtest 'wxWidgets-3_2' => sub {
  my $wx       = temp_copy('wxWidgets-3_2', '25014ee9d3640ebd9bc2370a2bbb5a63');
  my $checkout = Cavil::Checkout->new($wx);
  $checkout->unpack;
  is_deeply $checkout->specfile_report, report('wxWidgets-3_2.specfile'), 'right specfile report';
};

subtest 'error-invalid-license' => sub {
  my $eil      = temp_copy('error-invalid-license', 'cb5e100e5a9a3e7f6d1fd97512215282');
  my $checkout = Cavil::Checkout->new($eil);
  $checkout->unpack;
  is_deeply $checkout->specfile_report, report('error-invalid-license.specfile'), 'right specfile report';
};

subtest 'error-no-spdx' => sub {
  my $ens      = temp_copy('error-no-spdx', 'cb5e100e5a9a3e7f6d1fd97512215282');
  my $checkout = Cavil::Checkout->new($ens);
  $checkout->unpack;
  is_deeply $checkout->specfile_report, report('error-no-spdx.specfile'), 'right specfile report';
};

subtest 'error-missing-main' => sub {
  my $emm      = temp_copy('error-missing-main', 'cb5e100e5a9a3e7f6d1fd97512215282');
  my $checkout = Cavil::Checkout->new($emm);
  $checkout->unpack;
  is_deeply $checkout->specfile_report, report('error-missing-main.specfile'), 'right specfile report';
};

subtest 'error-missing-specfile' => sub {
  my $ems      = temp_copy('error-missing-specfile', 'cb5e100e5a9a3e7f6d1fd97512215282');
  my $checkout = Cavil::Checkout->new($ems);
  $checkout->unpack;
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
  is $hash->{pid},     $$,                       'right process id';
  is_deeply $hash->{unpacked}{'error-broken-archive/test.txt'}, {mime => 'text/plain'}, 'right structure';
};

subtest 'error-missing-main-kiwi' => sub {
  my $emmk     = temp_copy('error-missing-main-kiwi', 'aacfdab0e71b0bebfdf8b5cc3badfecf');
  my $checkout = Cavil::Checkout->new($emmk);
  $checkout->unpack;
  is_deeply $checkout->specfile_report, report('error-missing-main-kiwi.kiwi'), 'right kiwi report';
};

subtest 'error-missing-kiwifile' => sub {
  my $emmk     = temp_copy('error-missing-kiwifile', 'bbcfdab0e71b0bebfdf8b5cc3badfecf');
  my $checkout = Cavil::Checkout->new($emmk);
  $checkout->unpack;
  is_deeply $checkout->specfile_report, report('error-missing-kiwifile.kiwi'), 'right kiwi report';
};

subtest 'error-missing-main-dockerfile' => sub {
  my $docker   = temp_copy('error-missing-main-dockerfile', '56cfdab0e71b0bebfdf8b5cc3badfe23');
  my $checkout = Cavil::Checkout->new($docker);
  $checkout->unpack;
  is_deeply $checkout->specfile_report, report('error-missing-main-dockerfile.dockerfile'), 'right kiwi report';
};

subtest 'error-missing-main-helm' => sub {
  my $helm     = temp_copy('error-missing-main-helm', '86cfdab0e71b0bebfdf8b5cc3badfe2f');
  my $checkout = Cavil::Checkout->new($helm);
  $checkout->unpack;
  is_deeply $checkout->specfile_report, report('error-missing-main-helm.helm'), 'right kiwi report';
};

subtest 'mixed (a little bit of everything)' => sub {
  my $mixed    = temp_copy('mixed', 'fffe100e5a9a3e7f6d1fd97512215282');
  my $checkout = Cavil::Checkout->new($mixed);
  $checkout->unpack;
  is_deeply $checkout->specfile_report, report('mixed.mixed'), 'right mixed report';
};

subtest 'error-invalid-license-mixed' => sub {
  my $mixed    = temp_copy('error-invalid-license-mixed', 'fffe100e5a9a3e7f6d1fd97512215283');
  my $checkout = Cavil::Checkout->new($mixed);
  $checkout->unpack;
  is_deeply $checkout->specfile_report, report('error-invalid-license-mixed.mixed'), 'right mixed report';
};

subtest 'error-missing-main-mixed' => sub {
  my $mixed    = temp_copy('error-missing-main-mixed', 'fffe100e5a9a3e7f6d1fd97512215284');
  my $checkout = Cavil::Checkout->new($mixed);
  $checkout->unpack;
  is_deeply $checkout->specfile_report, report('error-missing-main-mixed.mixed'), 'right mixed report';
};

subtest 'error-invalid-yaml-helm' => sub {
  my $helm     = temp_copy('error-invalid-yaml-helm', 'fffe100e5a9a3e7f6d1fd97512215286');
  my $checkout = Cavil::Checkout->new($helm);
  $checkout->unpack;
  is_deeply $checkout->specfile_report, report('error-invalid-yaml-helm.helm'), 'right helm chart report';
};

subtest 'error-invalid-xml-kiwi' => sub {
  my $kiwi     = temp_copy('error-invalid-xml-kiwi', 'fffe100e5a9a3e7f6d1fd97512215287');
  my $checkout = Cavil::Checkout->new($kiwi);
  $checkout->unpack;
  is_deeply $checkout->specfile_report, report('error-invalid-xml-kiwi.kiwi'), 'right kiwi report';
};

subtest 'error-incomplete-checkout' => sub {
  my $remote   = temp_copy('error-incomplete-checkout', 'cb5e100e5a9a3e7f6d1fd97512215282');
  my $checkout = Cavil::Checkout->new($remote);
  $checkout->unpack;
  is_deeply $checkout->specfile_report, report('error-incomplete-checkout.specfile'), 'right specfile report';
};

subtest 'Tarball upload' => sub {
  my $ceph     = temp_copy('tarball-upload', '5fcfdab0e71b0bebfdf8b5cc6bcdfecf');
  my $checkout = Cavil::Checkout->new($ceph);
  $checkout->unpack;
  is_deeply $checkout->specfile_report, report('tarball-upload.cavil'), 'right tarball report';
};

subtest 'Unpack background job' => sub {
  my $cavil_test = Cavil::Test->new(online => $ENV{TEST_ONLINE}, schema => 'unpack_test_mojo');
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
  ok -f $module,                                       'module exists';
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

subtest 'Unpack background job (with exclude file)' => sub {
  my $cavil_test = Cavil::Test->new(online => $ENV{TEST_ONLINE}, schema => 'unpack_test_buildah');
  my $config     = $cavil_test->default_config;
  $config->{exclude_file} = curfile->sibling('exclude-files', 'checkout.exclude')->to_string;
  my $t = Test::Mojo->new(Cavil => $config);
  $cavil_test->unpack_fixtures($t->app);

  my $minion = $t->app->minion;

  ok !$t->app->packages->is_unpacked(1), 'not unpacked yet';
  $minion->enqueue(unpack => [1]);
  $minion->perform_jobs;
  ok $t->app->packages->is_unpacked(1), 'unpacked';
  my $good = path($t->app->packages->pkg_checkout_dir(1));
  ok -e $good->child('.unpacked', 'foo', 'bar.txt');
  ok -e $good->child('.unpacked', 'foo', 'bar', 'bar.tar');
  ok -e $good->child('.unpacked', 'foo', 'bar', 'bar');
  ok -e $good->child('.unpacked', 'foo', 'bar', 'bar', 'test.js');

  ok !$t->app->packages->is_unpacked(2), 'not unpacked yet';
  $minion->enqueue(unpack => [2]);
  $minion->perform_jobs;
  ok $t->app->packages->is_unpacked(2), 'unpacked';
  my $good_too = path($t->app->packages->pkg_checkout_dir(2));
  ok -e $good_too->child('.unpacked',  'foo', 'bar.txt');
  ok -e $good_too->child('.unpacked',  'foo', 'bar', 'bar.tar');
  ok !-e $good_too->child('.unpacked', 'foo', 'bar', 'bar');
  ok !-e $good_too->child('.unpacked', 'foo', 'bar', 'bar', 'test.js');

  ok !$t->app->packages->is_unpacked(3), 'not unpacked yet';
  $minion->enqueue(unpack => [3]);
  $minion->perform_jobs;
  ok $t->app->packages->is_unpacked(3), 'unpacked';
  my $broken = path($t->app->packages->pkg_checkout_dir(3));
  ok -e $broken->child('.unpacked',  'foo', 'bar.txt');
  ok -e $broken->child('.unpacked',  'foo', 'bar', 'test-case.tar');
  ok !-e $broken->child('.unpacked', 'foo', 'bar', 'test-case');
};

done_testing;
