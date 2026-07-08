# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Mojo::Base -strict, -signatures;

use FindBin;
use lib "$FindBin::Bin/lib";

use Test::More;
use Test::Mojo;
use Cavil::Test;
use Mojo::JSON qw(decode_json);

plan skip_all => 'set TEST_ONLINE to enable this test' unless $ENV{TEST_ONLINE};

my $cavil_test = Cavil::Test->new(online => $ENV{TEST_ONLINE}, schema => 'command_component_test');
my $t          = Test::Mojo->new(Cavil => $cavil_test->default_config);
my $app        = $t->app;
$cavil_test->no_fixtures($app);

my $db   = $app->pg->db;
my $usr  = $db->insert('bot_users', {login => 'tester'}, {returning => 'id'})->hash->{id};
my $pkgs = $app->packages;

sub add_pkg ($name, $dir) {
  return $pkgs->add(
    name            => $name,
    package         => $name,
    checkout_dir    => $dir,
    srcmd5          => $dir,
    api_url         => 'https://api.opensuse.org',
    requesting_user => $usr,
    project         => 'devel:test',
    priority        => 5
  );
}

sub add_comp ($pid, $type, $name, $version) {
  $db->insert('package_components',
    {package => $pid, type => $type, name => $name, version => $version, purl => "pkg:$type/$name\@$version"});
}

# A package shipped in two products, with two components
my $in_products = add_pkg('in-products', 'a' x 32);
add_comp($in_products, 'npm',   'react', '18.2.0');
add_comp($in_products, 'cargo', 'serde', '1.0.197');
my $p1 = $db->insert('bot_products', {name => 'SUSE:Prod:One'}, {returning => 'id'})->hash->{id};
my $p2 = $db->insert('bot_products', {name => 'SUSE:Prod:Two'}, {returning => 'id'})->hash->{id};
$db->insert('bot_package_products', {package => $in_products, product => $_}) for $p1, $p2;

# A package in no product (fresh devel request), identified by its external_link
my $devel = add_pkg('devel-only', 'b' x 32);
$db->update('bot_packages', {external_link => 'obs#123'}, {id => $devel});
add_comp($devel, 'npm', 'lodash', '4.17.19');

# Embargoed and obsolete packages must never appear, even when mapped to a product
my $emb = add_pkg('embargoed-pkg', 'c' x 32);
$db->update('bot_packages', {embargoed => 1}, {id => $emb});
add_comp($emb, 'npm', 'secret-dep', '1.0.0');
$db->insert('bot_package_products', {package => $emb, product => $p1});

my $obs = add_pkg('obsolete-pkg', 'd' x 32);
$db->update('bot_packages', {obsolete => 1}, {id => $obs});
add_comp($obs, 'npm', 'old-dep', '0.1.0');
$db->insert('bot_package_products', {package => $obs, product => $p1});

subtest 'component --export' => sub {
  my $buffer = '';
  {
    open my $handle, '>', \$buffer;
    local *STDOUT = $handle;
    $app->start('component', '--export');
  }

  my @records = map { decode_json($_) } grep {length} split /\n/, $buffer;
  my %seen    = map { join('|', @$_{qw(product external_link package source component version)}) => 1 } @records;
  my %by_pkg;
  $by_pkg{$_->{package}}++ for @records;

  # Product packages: one record per (component, product); product set, external_link empty
  ok $seen{'SUSE:Prod:One||in-products|npm|react|18.2.0'},    'react under the first product';
  ok $seen{'SUSE:Prod:Two||in-products|npm|react|18.2.0'},    'react under the second product (fan-out)';
  ok $seen{'SUSE:Prod:One||in-products|cargo|serde|1.0.197'}, 'serde under the first product';
  ok $seen{'SUSE:Prod:Two||in-products|cargo|serde|1.0.197'}, 'serde under the second product';
  is $by_pkg{'in-products'}, 4, 'two components across two products yields four records';

  # Non-product package: external_link carried, product empty
  ok $seen{'|obs#123|devel-only|npm|lodash|4.17.19'}, 'devel-only package uses external_link, product empty';
  is $by_pkg{'devel-only'}, 1, 'exactly one record for the non-product package';

  # Excluded packages
  ok !$by_pkg{'embargoed-pkg'}, 'embargoed package is excluded';
  ok !$by_pkg{'obsolete-pkg'},  'obsolete package is excluded';

  # Each record carries the checksum (the source-hosting checksum that, with the name, uniquely
  # identifies the package)
  my %checksum;
  $checksum{$_->{package}} = $_->{checksum} for @records;
  is $checksum{'in-products'}, 'a' x 32, 'record carries the package checksum';
  is $checksum{'devel-only'},  'b' x 32, 'checksum present for the non-product package too';
};

done_testing;
