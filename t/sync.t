# Copyright (C) 2020 SUSE LLC
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
use Mojolicious::Lite;
use Mojo::File qw(tempdir);
use Mojo::JSON qw(decode_json);

plan skip_all => 'set TEST_ONLINE to enable this test' unless $ENV{TEST_ONLINE};

my $cavil_test = Cavil::Test->new(online => $ENV{TEST_ONLINE}, schema => 'sync_test');
my $config     = $cavil_test->default_config;
$config->{classifier} = 'http://127.0.0.1:5000';
my $t = Test::Mojo->new(Cavil => $config);
$cavil_test->mojo_fixtures($t->app);

my $sync     = $t->app->sync->silent(1);
my $patterns = $t->app->patterns;
my $tempdir  = tempdir;
my $dir      = $tempdir->child('license_patterns')->make_path;

subtest 'Export license patterns' => sub {
  ok $sync->store($dir) > 0, 'multuple license patterns stored';
  my $apache = $patterns->find(1);
  is $apache->{license},  'Apache-2.0', 'right license';
  is $apache->{packname}, '',           'no packname';
  ok $apache->{pattern},  'has pattern';
  ok my $uuid = $apache->{unique_id}, 'has UUID';
  my $target = $dir->child(substr($uuid, 0, 1), substr($uuid, 1, 1), $uuid);
  my $hash   = decode_json $target->slurp;
  is $hash->{license},   'Apache-2.0', 'right license';
  is $hash->{packname},  '',           'no packname';
  is $hash->{unique_id}, $uuid, 'same UUID';

  $apache = $patterns->find(2);
  is $apache->{license},  'Apache-2.0',       'right license';
  is $apache->{packname}, 'perl-Mojolicious', 'right packname';
  ok $uuid = $apache->{unique_id}, 'has UUID';
  $target = $dir->child(substr($uuid, 0, 1), substr($uuid, 1, 1), $uuid);
  $hash   = decode_json $target->slurp;
  is $hash->{license},   'Apache-2.0',       'right license';
  is $hash->{packname},  'perl-Mojolicious', 'right packname';
  is $hash->{unique_id}, $uuid, 'same UUID';

  my $artistic = $patterns->find(3);
  is $artistic->{license}, 'Artistic-2.0', 'right license';
  ok $artistic->{pattern}, 'has pattern';
  ok $uuid = $artistic->{unique_id}, 'has UUID';
  $target = $dir->child(substr($uuid, 0, 1), substr($uuid, 1, 1), $uuid);
  $hash   = decode_json $target->slurp;
  is $hash->{license}, 'Artistic-2.0', 'right license';
  is $hash->{unique_id}, $uuid, 'same UUID';
};

subtest 'Import license patterns' => sub {
  is $sync->load($dir), 0, 'no new patterns to import yet';
  my $apache = $patterns->find(1);
  ok my $apache_uuid = $apache->{unique_id}, 'has UUID';
  my $artistic = $patterns->find(3);
  ok my $artistic_uuid = $apache->{unique_id}, 'has UUID';

  my $db = $t->app->pg->db;
  $db->delete('license_patterns', {id => $apache->{id}});
  is $db->select('license_patterns', '*', {unique_id => $apache_uuid})->rows, 0, 'pattern with UUID deleted';
  $db->delete('license_patterns', {id => $artistic->{id}});
  is $db->select('license_patterns', '*', {unique_id => $artistic_uuid})->rows, 0, 'pattern with UUID deleted';

  is $sync->load($dir), 2, 'two new patterns imported';
  is $db->select('license_patterns', '*', {unique_id => $apache_uuid})->rows,   1, 'pattern with UUID exists again';
  is $db->select('license_patterns', '*', {unique_id => $artistic_uuid})->rows, 1, 'pattern with UUID exists again';
};

done_testing;
