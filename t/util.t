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
use Mojo::File qw(path curfile tempfile);
use Mojo::JSON qw(decode_json);
use Cavil::Util (qw(buckets lines_context obs_ssh_auth parse_exclude_file parse_service_file pattern_matches),
  qw(request_id_from_external_link run_cmd spdx_link ssh_sign));

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

subtest 'parse_service_file' => sub {
  is_deeply parse_service_file(''),                      [], 'empty service file';
  is_deeply parse_service_file(" \n \n "),               [], 'empty service file';
  is_deeply parse_service_file('<services></services>'), [], 'empty service file';
  is_deeply parse_service_file('<services>'),            [], 'empty service file';
  is_deeply parse_service_file('services'),              [], 'empty service file';

  my $services1 = [
    {name => 'download_files',    mode => 'trylocal', safe => 0},
    {name => 'verify_file',       mode => 'Default',  safe => 0},
    {name => 'product_converter', mode => 'Default',  safe => 1}
  ];
  is_deeply parse_service_file(<<EOF), $services1, 'unsafe services';
<services>
  <service name="download_files" mode="trylocal" />
  <service name="verify_file">
    <param name="file">krabber-1.0.tar.gz</param>
    <param name="verifier">sha256</param>
    <param name="checksum">7f535a96a834b31ba2201a90c4d365990785dead92be02d4cf846713be938b78</param>
  </service>
  <service name="product_converter">
</services>
EOF

  my $services2 = [
    {name => 'one',   mode => 'Default',    safe => 0},
    {name => 'two',   mode => 'trylocal',   safe => 0},
    {name => 'three', mode => 'localonly',  safe => 1},
    {name => 'four',  mode => 'serveronly', safe => 0},
    {name => 'five',  mode => 'buildtime',  safe => 1},
    {name => 'six',   mode => 'manual',     safe => 1},
    {name => 'seven', mode => 'disabled',   safe => 1}
  ];
  is_deeply parse_service_file(<<EOF), $services2, 'all modes';
<services>
  <service name="one" />
  <service name="two" mode="trylocal" />
  <service name="three" mode="localonly" />
  <service name="four" mode="serveronly" />
  <service name="five" mode="buildtime" />
  <service name="six" mode="manual" />
  <service name="seven" mode="disabled" />
</services>
EOF
};

subtest 'pattern_matches' => sub {
  ok pattern_matches('bar',             'bar'),                     'match';
  ok pattern_matches('bär',             'bär'),                     'match';
  ok pattern_matches('bar',             'foo bar baz'),             'match';
  ok pattern_matches('bar',             'bar baz'),                 'match';
  ok pattern_matches('bar',             "foo bar"),                 'match';
  ok pattern_matches('foo bar',         "foo\nbar"),                'match';
  ok !pattern_matches('foo',            'bar baz'),                 'no match';
  ok !pattern_matches('foo',            'bar'),                     'no match';
  ok !pattern_matches('foo',            'fooo'),                    'no match';
  ok pattern_matches('# foo',           '## foo bar baz'),          'match';
  ok pattern_matches('# foo',           'foo'),                     'match';
  ok pattern_matches('234',             '1 234 56'),                'match';
  ok pattern_matches('123',             '123'),                     'match';
  ok pattern_matches('foo $SKIP19 bar', 'foo yada bar baz'),        'match';
  ok pattern_matches('foo $SKIP1 bar',  'foo yada bar baz'),        'match';
  ok !pattern_matches('foo $SKIP1 bar', 'foo ya da bar'),           'no match';
  ok pattern_matches('foo $SKIP2 bar',  'foo ya da bar'),           'match';
  ok pattern_matches('foo $SKIP3 bar',  'foo ya da bar'),           'match';
  ok !pattern_matches('foo $SKIP3 bar', 'foo ya da ya da bar'),     'no match';
  ok !pattern_matches('foo $SKIP3 bar', 'foo ya da ya da bar foo'), 'no match';
};

subtest 'request_id_from_external_link' => sub {
  is request_id_from_external_link('obs#1234'),     1234,  'right id';
  is request_id_from_external_link('ibs#4321'),     4321,  'right id';
  is request_id_from_external_link('unknown#4321'), undef, 'no id';
  is request_id_from_external_link(''),             undef, 'no id';
};

subtest 'run_cmd' => sub {
  my $cwd    = path;
  my $result = run_cmd($cwd, ['echo', 'foo']);
  is $result->{status},    !!1,     'right status';
  is $result->{exit_code}, 0,       'right exit code';
  is $result->{stderr},    '',      'right stderr';
  is $result->{stdout},    "foo\n", 'right stdout';
};

subtest 'spdx_link' => sub {
  is spdx_link('MIT'), '<a class="spdx-link" target="_blank" href="https://spdx.org/licenses/MIT.html">MIT</a>',
    'known license';
  is spdx_link('Apache-2.0'),
    '<a class="spdx-link" target="_blank" href="https://spdx.org/licenses/Apache-2.0.html">Apache-2.0</a>',
    'known license';
  is spdx_link('Unknown-License'), 'Unknown-License', 'unknown license';

  subtest 'Expression with AND' => sub {
    is spdx_link('Apache-2.0 AND MIT'),
      '<a class="spdx-link" target="_blank" href="https://spdx.org/licenses/Apache-2.0.html">Apache-2.0</a>' . ' AND '
      . '<a class="spdx-link" target="_blank" href="https://spdx.org/licenses/MIT.html">MIT</a>';
  };

  subtest 'Expression with OR' => sub {
    is spdx_link('MIT OR GPL-2.0-only'),
      '<a class="spdx-link" target="_blank" href="https://spdx.org/licenses/MIT.html">MIT</a>' . ' OR '
      . '<a class="spdx-link" target="_blank" href="https://spdx.org/licenses/GPL-2.0-only.html">GPL-2.0-only</a>';
  };

  subtest 'Expression with parentheses and AND/OR' => sub {
    is spdx_link('(MIT OR Apache-2.0) AND GPL-2.0-only'),
        '('
      . '<a class="spdx-link" target="_blank" href="https://spdx.org/licenses/MIT.html">MIT</a>' . ' OR '
      . '<a class="spdx-link" target="_blank" href="https://spdx.org/licenses/Apache-2.0.html">Apache-2.0</a>'
      . ') AND '
      . '<a class="spdx-link" target="_blank" href="https://spdx.org/licenses/GPL-2.0-only.html">GPL-2.0-only</a>';
  };

  subtest 'Expression with exception' => sub {
    is spdx_link('Classpath-exception-2.0'),
      '<a class="spdx-link" target="_blank" href="https://spdx.org/licenses/Classpath-exception-2.0.html">Classpath-exception-2.0</a>',
      'SPDX exception only';

    is spdx_link('GPL-2.0-only WITH Classpath-exception-2.0'),
        '<a class="spdx-link" target="_blank" href="https://spdx.org/licenses/GPL-2.0-only.html">GPL-2.0-only</a>'
      . ' WITH '
      . '<a class="spdx-link" target="_blank" href="https://spdx.org/licenses/Classpath-exception-2.0.html">'
      . 'Classpath-exception-2.0</a>', 'SPDX license WITH exception';

    is spdx_link('MIT WITH Autoconf-exception-3.0'),
        '<a class="spdx-link" target="_blank" href="https://spdx.org/licenses/MIT.html">MIT</a>'
      . ' WITH '
      . '<a class="spdx-link" target="_blank" href="https://spdx.org/licenses/Autoconf-exception-3.0.html">'
      . 'Autoconf-exception-3.0</a>', 'MIT WITH Autoconf-exception-3.0';
  };
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
