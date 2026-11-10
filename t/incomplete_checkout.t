# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Mojo::Base -strict, -signatures;

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
  like $t->app->build_controller->mcp_report(2),
    qr/## Checkout May Be Incomplete\n\n\* Remote service in _service file: download_files \(mode: trylocal\)/,
    'incomplete checkout section';
};

my $app       = $t->app;
my $pkgs      = $app->packages;
my $checkouts = 0;
my $checkout  = sub ($name, %files) {
  my $sum = sprintf '%032x', ++$checkouts;
  my $dir = $cavil_test->checkout_dir->child($name, $sum)->make_path;
  $dir->child($_)->spew($files{$_}) for keys %files;
  my $id = $pkgs->add(
    name            => $name,
    checkout_dir    => $sum,
    api_url         => 'https://api.opensuse.org',
    requesting_user => 1,
    project         => 'devel:test',
    package         => $name,
    srcmd5          => $sum,
    priority        => 5
  );
  $pkgs->imported($id);
  $app->minion->enqueue(unpack => [$id]);
  $app->minion->perform_jobs;
  return $pkgs->find($id);
};
my $accept = sub ($id, $state) {
  $pkgs->update({id => $id, state => $state, reviewing_user => 1, review_timestamp => 1});
};
my %aggregate = (
  _aggregate =>
    qq{<aggregatelist>\n  <aggregate project="devel:other">\n    <package>foo</package>\n  </aggregate>\n</aggregatelist>\n},
  '_scmsync.obsinfo' => "mtime: 1764088004\nrevision: 1.3\n"
);
my $empty      = 'Manual review is required because the checkout is empty';
my $no_license = 'Manual review is required because no license was found';

subtest 'Never auto-accept empty checkouts' => sub {
  my $pkg = $checkout->('empty-pkg');
  is $pkg->{unpacked_files}, 0,      'no files';
  is $pkg->{state},          'new',  'not accepted';
  is $pkg->{notice},         $empty, 'empty notice';

  $accept->($pkg->{id}, 'acceptable_by_lawyer');
  $app->settings->update('test_bot', {acceptable_packages => ['empty-pkg']});
  my $again = $checkout->('empty-pkg');
  is $again->{checksum}, $pkg->{checksum}, 'same report as the accepted one';
  is $again->{state},    'new',            'not accepted by name or previous result';
  is $again->{notice},   $empty,           'empty notice';
  $app->settings->update('test_bot', {}, ['acceptable_packages']);
};

subtest 'Never auto-accept reports without a license by comparison' => sub {
  my %spec = ('nolic.spec' => "Name: nolic\nVersion: 1.0\nLicense: Custom\n");
  my $pkg  = $checkout->('nolic', %spec);
  like $pkg->{checksum}, qr/-0:/, 'risk 0';
  is $pkg->{state},       'new',       'not accepted';
  is $pkg->{notice},      $no_license, 'no license notice';
  is $pkg->{diff_report}, undef,       'no diff';

  $accept->($pkg->{id}, 'acceptable_by_lawyer');
  my $again = $checkout->('nolic', %spec);
  is $again->{checksum}, $pkg->{checksum}, 'same report';
  is $again->{state},    'new',            'previous result not inherited';
  is $again->{notice},   $no_license,      'no license notice';

  my $changed = $checkout->('nolic', 'nolic.spec' => "Name: nolic\nVersion: 2.0\nLicense: MIT\n");
  is $changed->{state}, 'new', 'not accepted';
  like $changed->{notice}, qr/^\Q$no_license\E\n\nDiff to closest match \d+\n\n  Declared license  Unknown -> MIT$/,
    'real differences are still shown';

  $accept->($again->{id}, 'acceptable');
  $app->minion->enqueue(analyzed => [$again->{id}]);
  $app->minion->perform_jobs;
  is $pkgs->find($again->{id})->{state}, 'acceptable', 'not upgraded to a lawyer decision';
};

subtest 'Auto-accept packages made only of listed files' => sub {
  my $pkg = $checkout->('aggregate-pkg', %aggregate);
  is $pkg->{state},  'acceptable',                                                       'accepted';
  is $pkg->{result}, 'Accepted because of package files (_aggregate, _scmsync.obsinfo)', 'result';

  $app->settings->update('test_bot', {auto_accept => 0});
  $pkg = $checkout->('aggregate-pkg2', %aggregate);
  is $pkg->{state}, 'new', 'not accepted while paused';
  like $pkg->{notice}, qr/Automatic acceptance is paused\n\nOtherwise accepted package files/, 'paused notice';
  $app->settings->update('test_bot', {}, ['auto_accept']);

  $app->notes->add($pkg->{id}, 'aggregate-pkg3', 1, 'Only with approval', 0, 0, undef, 1);
  $pkg = $checkout->('aggregate-pkg3', %aggregate);
  is $pkg->{state}, 'new', 'not accepted with a limitation';
  like $pkg->{notice}, qr/Only with approval\n\nOtherwise accepted package files$/, 'limitation notice';

  $pkg = $checkout->('aggregate-pkg4', %aggregate, 'foo.tar.gz' => 'not really');
  is $pkg->{state},  'new',       'unlisted file';
  is $pkg->{notice}, $no_license, 'no license notice';

  my $result = $app->settings->update('test_bot', {acceptable_files => ['_aggregate']});
  $pkg = $checkout->('aggregate-pkg5', %aggregate);
  is $pkg->{state},  'new',       'file missing from the list';
  is $pkg->{notice}, $no_license, 'no license notice';

  $result = $app->settings->update('test_bot', {}, ['acceptable_files']);
  is $pkgs->analyze_held($result->{old}, $result->{new}), 6, 'every review without a license is checked again';
  $app->minion->perform_jobs;
  is $pkgs->find($pkg->{id})->{state}, 'acceptable', 'accepted once the list covers it';
};

done_testing();
