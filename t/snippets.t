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

plan skip_all => 'set TEST_ONLINE to enable this test' unless $ENV{TEST_ONLINE};

my $cavil_test = Cavil::Test->new(online => $ENV{TEST_ONLINE}, schema => 'snippets_test');
my $t          = Test::Mojo->new(Cavil => $cavil_test->default_config);
$cavil_test->package_with_snippets_fixtures($t->app);

subtest 'Unpack and index with the job queue' => sub {
  my $unpack_id = $t->app->minion->enqueue(unpack => [1]);
  $t->app->minion->perform_jobs;

  like $t->app->packages->find(1)->{checksum}, qr/^Error-9:\w+/, 'right shortname';

  my $res = $t->app->pg->db->select('snippets', 'text', {}, {order_by => 'text'})->hashes;
  is_deeply(
    $res,
    [
      {
            text => "\nNow complex: The license might\nbe something cool\nbut we would not\nsay what we can do"
          . "\nand what we can not do\nwith the GPL. The problem\nis that if we continue\nthis line and afterwards"
          . "\ntalk again about the GPL,\nit should really be part\nof the same snippet. We don't\nwant GPL to abort it."
      },
      {
        text => "The GPL might be\nsomething cool\nbut we would not\nsay what we can do\nand what we can not do"
          . "\nwith the license.\n"
      },
      {
        text => "The license might be\nsomething cool\nbut we would not\nsay what we can do\nand what we can not do"
          . "\nwith the GPL."
      }
    ]
  );
};

done_testing();
