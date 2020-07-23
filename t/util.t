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

use Test::More;
use Mojo::File;
use Mojo::JSON 'decode_json';
use Cavil::Util qw(buckets lines_context);

is_deeply buckets([1 .. 10], 3), [[1, 2, 3, 4], [5, 6, 7, 8], [9, 10]], 'right buckets';
is_deeply buckets([1 .. 10], 4), [[1, 2, 3, 4, 5], [6, 7, 8, 9, 10]], 'right buckets';

my $casedir = Mojo::File->new('t/lines');

sub compare_lines {
  my $case = shift;
  my $json = decode_json($casedir->child("$case.json")->slurp);
  is_deeply(lines_context($json->{original}), $json->{expected}, "right context in case $case");
}

compare_lines("01");
compare_lines("02");

done_testing;
