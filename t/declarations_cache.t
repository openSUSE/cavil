# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Mojo::Base -strict;

use FindBin;
use lib "$FindBin::Bin/lib";

use Test::More;
use Test::Mojo;
use Cavil::Test;
use Cavil::Checkout;
use Mojo::JSON qw(from_json);

plan skip_all => 'set TEST_ONLINE to enable this test' unless $ENV{TEST_ONLINE};

my $cavil_test = Cavil::Test->new(online => $ENV{TEST_ONLINE}, schema => 'declarations_cache_test');
my $t          = Test::Mojo->new(Cavil => $cavil_test->default_config);
$cavil_test->mojo_fixtures($t->app);

my $db      = $t->app->pg->db;
my $reports = $t->app->reports;
my $stored  = sub { $db->select('bot_reports', 'declarations', {package => shift})->hash };

subtest 'Stored with the report' => sub {
  $t->app->minion->enqueue(unpack => [1]);
  $t->app->minion->perform_jobs;
  my $declarations = $reports->declarations(1);
  is $declarations->{declarations}[0]{file}, 'perl-Mojolicious.spec', 'right primary';
  is_deeply from_json($stored->(1)->{declarations}), $declarations, 'analyze stored them';

  # Reports analyzed before the declarations column existed have none stored
  $db->update('bot_reports', {declarations => undef}, {package => 1});
  is_deeply $reports->declarations(1),               $declarations, 'rebuilt from the checkout';
  is_deeply from_json($stored->(1)->{declarations}), $declarations, 'and stored again';
};

subtest 'Read before the first analysis' => sub {
  is_deeply $reports->declarations(2), {declarations => [], incomplete_checkout => []}, 'nothing before unpacking';
  ok !$stored->(2), 'nothing stored';

  Cavil::Checkout->new($t->app->packages->pkg_checkout_dir(2))->unpack;
  is $reports->declarations(2)->{declarations}[0]{file}, 'perl-Mojolicious.spec', 'built from the checkout';
  is from_json($stored->(2)->{declarations})->{declarations}[0]{file}, 'perl-Mojolicious.spec', 'and stored';
  is_deeply $reports->declarations(999), {declarations => [], incomplete_checkout => []}, 'unknown package';
};

subtest 'Package without declarations' => sub {
  my $dir = $t->app->packages->pkg_checkout_dir(2);
  $dir->list->grep(qr/\.spec$/)->each('remove');
  $t->app->minion->enqueue(unpack => [2]);
  $t->app->minion->perform_jobs;
  my $empty = {declarations => [], incomplete_checkout => []};
  is_deeply from_json($stored->(2)->{declarations}), $empty, 'analyze stored none';
  $t->get_ok('/login')->status_is(302);
  $t->get_ok('/reviews/meta/2')->status_is(200)->json_is('/declarations', [])->json_is('/package_type', undef);
};

subtest 'Declaration without a license' => sub {
  $t->app->packages->pkg_checkout_dir(2)->child('Dockerfile')->spew("FROM scratch\n");
  $t->app->minion->enqueue(unpack => [2]);
  $t->app->minion->perform_jobs;
  $t->get_ok('/reviews/meta/2')
    ->status_is(200)
    ->json_is('/declarations/0/license', undef)
    ->json_is('/package_type',           'dockerfile');
  my $report = $t->app->build_controller->mcp_report(2);
  like $report,   qr/^\* `Dockerfile` \(dockerfile\), no license declared$/m, 'listed as undeclared';
  unlike $report, qr/Declared-License/,                                       'nothing declared';
};

done_testing;
