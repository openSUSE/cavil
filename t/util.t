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
use Mojo::File  qw(curfile tempfile);
use Mojo::JSON  qw(decode_json);
use Cavil::Util qw(buckets lines_context obs_ssh_auth parse_exclude_file pattern_matches ssh_sign);

my $PRIVATE_KEY = tempfile->spew(<<'EOF');
-----BEGIN OPENSSH PRIVATE KEY-----
b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW
QyNTUxOQAAACAQ1ktyOCFDMUIV9GfaZio8NNPT09mHcG0Wpx3bo7xwzAAAAJBnE+yjZxPs
owAAAAtzc2gtZWQyNTUxOQAAACAQ1ktyOCFDMUIV9GfaZio8NNPT09mHcG0Wpx3bo7xwzA
AAAEAnJpCOHj1O0O8oCygQJ6pjDT+827VkQXq98zApns/VYRDWS3I4IUMxQhX0Z9pmKjw0
09PT2YdwbRanHdujvHDMAAAACmNhdmlsQHRlc3QBAgM=
-----END OPENSSH PRIVATE KEY-----
EOF

subtest 'buckets' => sub {
  is_deeply buckets([1 .. 10], 3), [[1, 2, 3, 4], [5, 6, 7, 8], [9, 10]], 'right buckets';
  is_deeply buckets([1 .. 10], 4), [[1, 2, 3, 4, 5], [6, 7, 8, 9, 10]], 'right buckets';
};

my $casedir = Mojo::File->new('t/lines');

sub compare_lines {
  my $case = shift;
  my $json = decode_json($casedir->child("$case.json")->slurp);
  is_deeply(lines_context($json->{original}), $json->{expected}, "right context in case $case");
}

subtest 'lines_context' => sub {
  compare_lines("01");
  compare_lines("02");
};

subtest 'parse_exclude_file' => sub {
  is_deeply parse_exclude_file('t/exclude-files/cavil.exclude', 'buildah'), ['test.tar',        'foo.tar'];
  is_deeply parse_exclude_file('t/exclude-files/cavil.exclude', 'gcc12'),   ['some-broken.tar', 'another.tar.gz'];
  is_deeply parse_exclude_file('t/exclude-files/cavil.exclude', 'gcc13'),   ['another.tar.gz',  'foo*bar.zip'];
  is_deeply parse_exclude_file('t/exclude-files/cavil.exclude', 'gcc1'),    ['another.tar.gz',  'specific.zip'];
  is_deeply parse_exclude_file('t/exclude-files/cavil.exclude', 'gcc9'),    ['another.tar.gz',  'specific.zip'];
  is_deeply parse_exclude_file('t/exclude-files/empty.exclude', 'whatever'), [];
};

subtest 'pattern_matches' => sub {
  ok pattern_matches('bar',             'bar'),                 'match';
  ok pattern_matches('bär',             'bär'),                 'match';
  ok pattern_matches('bar',             'foo bar baz'),         'match';
  ok pattern_matches('bar',             'bar baz'),             'match';
  ok pattern_matches('bar',             "foo bar"),             'match';
  ok !pattern_matches('foo',            'bar baz'),             'no match';
  ok !pattern_matches('foo',            'bar'),                 'no match';
  ok !pattern_matches('foo',            'fooo'),                'no match';
  ok pattern_matches('# foo',           '## foo bar baz'),      'match';
  ok pattern_matches('# foo',           'foo'),                 'match';
  ok pattern_matches('234',             '1 234 56'),            'match';
  ok pattern_matches('123',             '123'),                 'match';
  ok pattern_matches('foo $SKIP19 bar', 'foo yada bar baz'),    'match';
  ok pattern_matches('foo $SKIP1 bar',  'foo yada bar baz'),    'match';
  ok !pattern_matches('foo $SKIP1 bar', 'foo ya da bar'),       'match';
  ok pattern_matches('foo $SKIP2 bar',  'foo ya da bar'),       'match';
  ok pattern_matches('foo $SKIP3 bar',  'foo ya da bar'),       'match';
  ok !pattern_matches('foo $SKIP3 bar', 'foo ya da ya da bar'), 'no match';
};

subtest 'ssh_sign' => sub {
  my $signature = ssh_sign($PRIVATE_KEY, 'realm', 'message');
  like $signature, qr/^[-A-Za-z0-9+\/]+={0,3}$/, 'valid Base64 encoded signature';
  isnt ssh_sign($PRIVATE_KEY, 'realm2', 'message'),  $signature, 'different signature';
  isnt ssh_sign($PRIVATE_KEY, 'realm',  'message2'), $signature, 'different signature';
  is ssh_sign($PRIVATE_KEY, 'realm', 'message'), $signature, 'identical signature';
};

subtest 'obs_ssh_auth' => sub {
  my $auth_header
    = obs_ssh_auth('Signature realm="Use your developer account",headers="(created)"', 'user', $PRIVATE_KEY);
  isnt obs_ssh_auth('Signature realm="Use your developer account",headers="(created)"', 'user2', $PRIVATE_KEY),
    $auth_header, 'different header';
  is obs_ssh_auth('Signature realm="Use your developer account",headers="(created)"', 'user', $PRIVATE_KEY),
    $auth_header, 'identical header';
  like $auth_header,
    qr/^Signature keyId="user",algorithm="ssh",signature="[-A-Za-z0-9+\/]+={0,3}",headers="\(created\)",created="\d+"$/;
};

done_testing;
