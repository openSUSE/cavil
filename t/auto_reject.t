# Copyright (C) 2025 SUSE LLC
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
use Cavil::ReportUtil qw(report_checksum);
use Mojo::File        qw(path);

plan skip_all => 'set TEST_ONLINE to enable this test' unless $ENV{TEST_ONLINE};

my $cavil_test = Cavil::Test->new(online => $ENV{TEST_ONLINE}, schema => 'auto_reject_test');
my $config     = $cavil_test->default_config;
my $t          = Test::Mojo->new(Cavil => $config);
$cavil_test->mojo_fixtures($t->app);

$t->app->minion->enqueue(unpack => [1]);
$t->app->minion->perform_jobs;
is $t->app->packages->find(1)->{state}, 'new', 'still new';

subtest 'Accept package because of its name' => sub {
  my $file
    = $cavil_test->checkout_dir->child('perl-Mojolicious', 'c7cfdab0e71b0bebfdf8b2dc3badfecd', 'perl-Mojolicious.spec');
  my $content = $file->slurp;
  $content .= "\n#!RemoteAsset\n";
  $file->spew($content);

  $t->app->minion->enqueue('reindex_all');
  $t->app->minion->perform_jobs;

  my $pkg = $t->app->packages->find(1);
  is $pkg->{state},  'unacceptable',                                  'automatically rejected';
  is $pkg->{result}, 'Rejected because package contains RemoteAsset', 'reason';
};

done_testing();
