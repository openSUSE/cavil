# Copyright (C) 2024 SUSE LLC
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
use Cavil::ReportUtil qw(report_checksum);

subtest 'report_checksum' => sub {
  is report_checksum({},                           {}), '1709a28fde41022c01762131a1711875', 'empty report';
  is report_checksum({main => {license => 'MIT'}}, {}), '2d5198bd51f0617d05bf585eb3dc4758', 'specfile license only';

  subtest 'Dig licenses' => sub {
    is report_checksum({main => {license => 'MIT'}}, {licenses => {'Apache-2.0' => {risk => 2}}}),
      'e91c43850ffd197cee057b93e1f00e0a', 'specfile and dig licenses';
    is report_checksum({main => {license => 'MIT'}}, {licenses => {'Apache-2.0' => {risk => 2}, 'Foo' => {risk => 0}}}),
      'e91c43850ffd197cee057b93e1f00e0a', 'ignore risk 0 licenses';
    is report_checksum({main => {license => 'MIT'}},
      {licenses => {'Apache-2.0' => {risk => 2}, 'BSD-3-Clause' => {risk => 1}}}),
      '9c6028aac6ea076c135afa22bb1af168', 'two dig licenses';
  };

  subtest 'Flags' => sub {
    is report_checksum({main => {license => 'MIT'}}, {licenses => {'Apache-2.0' => {risk => 2, flags => ['patent']}}}),
      '44145ca2199684606c72e444d16c10b5', 'one license flag';
    is report_checksum({main => {license => 'MIT'}},
      {licenses => {'Apache-2.0' => {risk => 2, flags => ['patent', 'trademark']}}}),
      '4bbcf593950c619f3beb693643925559', 'two license flags';
  };

  subtest 'Snippets' => sub {
    is report_checksum(
      {main => {license => 'MIT'}},
      {
        licenses => {'Apache-2.0' => {risk => 2}, 'BSD-3-Clause' => {risk => 1}},
        snippets => {2            => {4    => '6d5198bd51f0617d05bf585rb3dc475f'}}
      }
      ),
      'e53a9998d69ce6a27f198c415abaf363', 'one snippets present';
    is report_checksum(
      {main => {license => 'MIT'}},
      {
        licenses => {'Apache-2.0' => {risk => 2}, 'BSD-3-Clause' => {risk => 1}},
        snippets => {
          2 => {4 => '6d5198bd51f0617d05bf585rb3dc475f', 2 => '9d5198bd51f0a17d05af585rb3dc475e'},
          3 => {1 => '1f5198bd51fb617d05bf585rb3dc47ae'}
        }
      }
      ),
      '7351d8ac9fd4bbdb1cdda1293984c58d', 'one snippets present';
  };
};

done_testing;
