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
use Mojo::Pg;
use Mojolicious::Lite;

plan skip_all => 'set TEST_ONLINE to enable this test' unless $ENV{TEST_ONLINE};

my $cavil_test = Cavil::Test->new(online => $ENV{TEST_ONLINE}, schema => 'analyze_test');
my $t          = Test::Mojo->new(Cavil => $cavil_test->default_config);
$cavil_test->mojo_fixtures($t->app);

app->log->level('error');

subtest 'Analyze background job' => sub {
  $t->app->minion->enqueue(unpack => [1]);
  $t->app->minion->perform_jobs;

  # Set the first version to acceptable
  my $pkg = $t->app->packages->find(1);
  $pkg->{reviewing_user}   = 1;
  $pkg->{result}           = 'Sure';
  $pkg->{state}            = 'acceptable';
  $pkg->{review_timestamp} = 1;
  $t->app->packages->update($pkg);

  $t->app->minion->enqueue(unpack => [2]);
  $t->app->minion->perform_jobs;

  my $res = $t->app->pg->db->select('bot_packages', '*', {id => 2})->hashes->[0];
  is $res->{result}, "Diff to closest match 1:\n\n  Different spec file license: Artistic-2.0\n\n", 'different spec';
  is $res->{state},  'new',                                                                         'not approved';
};

done_testing;
