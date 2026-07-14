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
use Cavil::Util (
  qw(buckets lines_context license_is_catch_all normalize_license_expr obs_ssh_auth parse_exclude_file),
  qw(parse_service_file normalize_license_text pattern_matches pattern_contains_redundant_skip read_lines),
  qw(external_link_data request_id_from_external_link run_cmd spdx_link ssh_sign text_shingles validate_tags),
  qw(weighted_containment)
);

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

subtest 'pattern_contains_redundant_skip' => sub {
  ok pattern_contains_redundant_skip('$SKIP foo'),        'redundant $SKIP at beginning';
  ok pattern_contains_redundant_skip('foo $SKIP'),        'redundant $SKIP at end';
  ok !pattern_contains_redundant_skip('foo $SKIP19 bar'), 'no redundant $SKIP';
};

subtest 'normalize_license_text' => sub {

  subtest 'baseline strippers' => sub {
    is normalize_license_text('Permission is hereby granted'), 'Permission is hereby granted',
      'plain text is unchanged';
    is normalize_license_text('<p>Permission is <b>hereby</b> granted</p>'), 'Permission is hereby granted',
      'strips html tags';
    is normalize_license_text('Creative Commons &amp; friends'), 'Creative Commons friends', 'strips html entities';
    is normalize_license_text(" * Permission is granted\n * to use"), 'Permission is granted to use',
      'strips comment leaders and collapses whitespace';
    is normalize_license_text("// Permission is granted\n// to use"), 'Permission is granted to use',
      'strips // comment leaders';
    is normalize_license_text("Copyright (c) 2021 John Smith\nPermission is granted"), 'Permission is granted',
      'drops copyright lines';
    is normalize_license_text("see https://example.org/LICENSE\nlicensed under MIT"), 'licensed under MIT',
      'drops url lines';
    is normalize_license_text("contact foo\@bar.com\nlicensed under MIT"), 'licensed under MIT', 'drops email lines';
  };

  subtest 'C/C++ block comment delimiters' => sub {
    is normalize_license_text('/* Permission is hereby granted */'), 'Permission is hereby granted',
      'leading and trailing delimiters';
    is normalize_license_text('/** Permission **/ is /* granted */'), 'Permission is granted',
      'doubled delimiters anywhere on the line';
    is normalize_license_text('foo /* bar */ baz'), 'foo bar baz', 'mid-line delimiters';
    is normalize_license_text('Redistribution and use in source'), 'Redistribution and use in source',
      'plain text without delimiters is untouched';
  };

  subtest 'source-listing line numbers' => sub {
    is normalize_license_text("16 * THE SOFTWARE IS PROVIDED\n17 * EXPRESS OR IMPLIED"),
      'THE SOFTWARE IS PROVIDED EXPRESS OR IMPLIED', 'leading line numbers + the now-exposed * marker';
    is normalize_license_text("12 /* Permission is hereby */\n13 /* granted to any */"),
      'Permission is hereby granted to any', 'line numbers wrapping C comments';
    is normalize_license_text("10 // Licensed under the Apache License"), 'Licensed under the Apache License',
      'line number + the now-exposed // marker';
    is normalize_license_text("00010 Permission\n00011 granted"), 'Permission granted',
      'doxygen zero-padded line numbers';
    is normalize_license_text("8 O2scl is free software"), 'O2scl is free software', 'single-digit line number';
  };

  subtest 'guards: must NOT eat meaningful numbers' => sub {
    is normalize_license_text("4. Neither the name\n5. nor the names"), '4. Neither the name 5. nor the names',
      'BSD-style "N." clause numbers survive';
    is normalize_license_text("1) first condition\n2) second condition"), '1) first condition 2) second condition',
      '"N)" enumerated clauses survive';
    is normalize_license_text('3. Redistributions in binary form'), '3. Redistributions in binary form',
      'a real numbered clause line survives';
    is normalize_license_text('you may use version 2 of the License'), 'you may use version 2 of the License',
      'numbers in the middle of a line are untouched';
  };

  subtest 'groff/man markup' => sub {
    is normalize_license_text('Permission is \fBhereby\fR granted'), 'Permission is hereby granted',
      'font escapes \fB \fR';
    is normalize_license_text('the \fIProgram\fP and'), 'the Program and', 'font escapes \fI \fP';
    is normalize_license_text('a \f(CWcode\fP block'),  'a code block',    'two-letter font escape \f(CW';
    is normalize_license_text('zero\&width'),           'zerowidth',       'zero-width \& escape';
    is normalize_license_text(".\\\" Permission to use, copy, modify\n.\\\" and distribute is hereby granted"),
      'Permission to use, copy, modify and distribute is hereby granted',
      'keeps license text written inside .\\" comments (man pages), stripping only the marker';
  };

  subtest 'real markup, end to end (raw file text)' => sub {
    is normalize_license_text(
      '<a class="jxr_linenumber" name="16" href="#16">16</a> <em class="jxr_javadoccomment"> * THE SOFTWARE IS PROVIDED</em>'
    ), 'THE SOFTWARE IS PROVIDED', 'jxr (java xref) html line';
    is normalize_license_text(
      '<div class="line"><a name="l00012"></a><span class="lineno"> 12</span>&#160;<span class="comment"> Permission is hereby granted</span></div>'
    ), 'Permission is hereby granted', 'doxygen html line';
    is normalize_license_text(
      ".\\\" Permission to use, copy, modify, and\n.\\\" distribute this \\fBsoftware\\fR freely"),
      'Permission to use, copy, modify, and distribute this software freely',
      'man page: license text in .\\" comments with font escapes is preserved';
  };
};

subtest 'text_shingles' => sub {
  my $a = text_shingles('Permission is hereby granted to all', 3);
  is scalar(keys %$a), 4, 'four 3-token shingles from six tokens';

  # Case and punctuation are folded by the tokenizer, so these are identical
  my $b = text_shingles('PERMISSION is HEREBY granted, to all!!!', 3);
  is_deeply [sort keys %$a], [sort keys %$b], 'case/punctuation normalized away';

  my $short = text_shingles('MIT license', 3);
  is scalar(keys %$short), 2, 'short text falls back to unigrams';
};

subtest 'weighted_containment' => sub {
  my $snippet = {a => 1, b => 1, c => 1, d => 1};
  is weighted_containment($snippet, {a => 1, b => 1, c => 1, d => 1}), 1,   'full containment scores 1';
  is weighted_containment($snippet, {}),                               0,   'no overlap scores 0';
  is weighted_containment($snippet, {a => 1, b => 1}),                 0.5, 'half the shingles present';
  is weighted_containment({},       {a => 1}),                         0, 'empty snippet scores 0 (no divide by zero)';

  # IDF weighting: a rare shingle counts far more than common boilerplate
  my $idf = {rare => 100, common => 1};
  my $s   = {rare => 1,   common => 1};
  ok weighted_containment($s, {rare   => 1}, $idf) > 0.9, 'matching the rare shingle dominates';
  ok weighted_containment($s, {common => 1}, $idf) < 0.1, 'matching only boilerplate scores low';
};

subtest 'normalize_license_expr' => sub {
  is normalize_license_expr('MIT'),                 'mit',             'lower-cases a simple identifier';
  is normalize_license_expr('  GPL-2.0-only '),     'gpl-2.0-only',    'trims surrounding whitespace';
  is normalize_license_expr("MIT\t AND   MPL-2.0"), 'mit and mpl-2.0', 'collapses internal whitespace';
  is normalize_license_expr(''),                    '',                'empty string stays empty';
  is normalize_license_expr('   '),                 '',                'whitespace-only string normalizes to empty';

  subtest '"+" is treated as the SPDX "-or-later"' => sub {
    is normalize_license_expr('GPL-2.0+'),        'gpl-2.0-or-later',        'trailing "+" on a lone token';
    is normalize_license_expr('MIT OR GPL-2.0+'), 'gpl-2.0-or-later or mit', 'trailing "+" inside an expression';
  };

  subtest '"LicenseRef-" prefixes are dropped' => sub {
    is normalize_license_expr('LicenseRef-MPL-2'),    'mpl-2',    'strips a LicenseRef- prefix';
    is normalize_license_expr('licenseref-Custom-1'), 'custom-1', 'strips a lower-case licenseref- prefix';
  };

  subtest 'flat "OR" lists are sorted (commutative)' => sub {
    is normalize_license_expr('MIT OR Apache-2.0'), 'apache-2.0 or mit', 'two operands are reordered';
    is normalize_license_expr('GPL-2.0-or-later OR Artistic-1.0-Perl OR MIT'),
      'artistic-1.0-perl or gpl-2.0-or-later or mit', 'three operands are sorted alphabetically';
    is normalize_license_expr('Apache-2.0 OR MIT'), normalize_license_expr('MIT OR Apache-2.0'),
      'reordered OR expressions normalize identically';
  };

  subtest '"AND"/"WITH"/parentheses are left in original order' => sub {
    is normalize_license_expr('MIT AND Apache-2.0'), 'mit and apache-2.0', 'AND is not reordered';
    is normalize_license_expr('GPL-2.0-only WITH Classpath-exception-2.0'),
      'gpl-2.0-only with classpath-exception-2.0', 'WITH is not reordered';
    is normalize_license_expr('(MIT OR Apache-2.0) AND GPL-2.0-only'), '(mit or apache-2.0) and gpl-2.0-only',
      'expressions with parentheses are not reordered';
  };
};

subtest 'request_id_from_external_link' => sub {
  is request_id_from_external_link('obs#1234'),     1234,  'right id';
  is request_id_from_external_link('ibs#4321'),     4321,  'right id';
  is request_id_from_external_link('unknown#4321'), undef, 'no id';
  is request_id_from_external_link(''),             undef, 'no id';
};

subtest 'external_link_data' => sub {
  is external_link_data(undef), undef, 'undefined link returns undef';
  is_deeply external_link_data('obs#1234'), {text => 'obs#1234'}, 'unconfigured link stays plain';

  my $sources = [
    {
      pattern => '^obs#(\d+)$',
      url     => 'https://build.opensuse.org/request/show/$1',
      label   => 'OBS',
      title   => 'Open Build Service request'
    },
    {pattern => '^soo#([^!]+)!(\d+)$', url => 'https://src.example.test/$1/pulls/$2', label => 'source'},
    {pattern => '^plain#(.+)$', label => 'plain'}
  ];
  is_deeply external_link_data('obs#1234', $sources),
    {
    text  => 'obs#1234',
    url   => 'https://build.opensuse.org/request/show/1234',
    label => 'OBS',
    title => 'Open Build Service request'
    },
    'configured link returns structured rendering data';
  is_deeply external_link_data('soo#openSUSE/cavil!7', $sources),
    {
    text  => 'soo#openSUSE/cavil!7',
    url   => 'https://src.example.test/openSUSE/cavil/pulls/7',
    label => 'source',
    title => 'External link'
    },
    'multiple captures are expanded into source URL';
  is_deeply external_link_data('plain#example', $sources), {text => 'plain#example', label => 'plain'},
    'configured source can be label-only';
  is_deeply external_link_data('openSUSE:Factory', $sources), {text => 'openSUSE:Factory'},
    'unmatched configured link stays plain';
};

subtest 'run_cmd' => sub {
  my $cwd    = path;
  my $result = run_cmd($cwd, ['echo', 'foo']);
  is $result->{status},    !!1,     'right status';
  is $result->{exit_code}, 0,       'right exit code';
  is $result->{stderr},    '',      'right stderr';
  is $result->{stdout},    "foo\n", 'right stdout';
};

subtest 'read_lines' => sub {
  my $file = tempfile;
  my $fh   = $file->open('>:raw');
  print $fh "alpha\n";
  print $fh "b\xC3\xA4r\n";
  print $fh "caf\xE9\n";
  close $fh;

  is read_lines($file, 1, 3),  "alpha\nb\x{e4}r\ncaf\x{e9}\n", 'reads all requested lines and decodes mixed encodings';
  is read_lines($file, 2, 2),  "b\x{e4}r\n",                   'reads a single line range';
  is read_lines($file, 2, 10), "b\x{e4}r\ncaf\x{e9}\n",        'ignores non-existent lines beyond file end';

  subtest 'with line numbers' => sub {
    is read_lines($file, 1, 3, 1), "     1  alpha\n     2  b\x{e4}r\n     3  caf\x{e9}\n",
      'prefixes each line with its absolute line number';
    is read_lines($file, 2, 2, 1), "     2  b\x{e4}r\n", 'single line keeps its absolute number';
    is read_lines($file, 2, 10, 1), "     2  b\x{e4}r\n     3  caf\x{e9}\n",
      'numbering reflects file position, not offset within the range';
    is read_lines($file, 1, 3, 0), "alpha\nb\x{e4}r\ncaf\x{e9}\n", 'falsy flag is identical to omitting it';
  };
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

  subtest 'Untrusted text is HTML-escaped (no XSS)' => sub {

    # License strings can come from imported component metadata and are rendered with v-html, so any
    # non-link text must be escaped
    is spdx_link('MIT <img src=x onerror=alert(1)>'),
      '<a class="spdx-link" target="_blank" href="https://spdx.org/licenses/MIT.html">MIT</a>'
      . ' &lt;img src=x onerror=alert(1)&gt;', 'markup around a known license is escaped';
    is spdx_link('<script>alert(1)</script>'), '&lt;script&gt;alert(1)&lt;/script&gt;',
      'unknown license with markup is fully escaped';
    is spdx_link('Foo & Bar'), 'Foo &amp; Bar', 'ampersands are escaped';
    unlike spdx_link('MIT" onmouseover="alert(1)'), qr/onmouseover="alert/, 'attribute-breaking text is escaped';
  };
};

subtest 'ssh_sign' => sub {
  my $signature = ssh_sign($PRIVATE_KEY, 'realm', 'message');
  like $signature, qr/^[-A-Za-z0-9+\/]+={0,3}$/, 'valid Base64 encoded signature';
  isnt ssh_sign($PRIVATE_KEY, 'realm2', 'message'),  $signature, 'different signature';
  isnt ssh_sign($PRIVATE_KEY, 'realm',  'message2'), $signature, 'different signature';
  is ssh_sign($PRIVATE_KEY, 'realm', 'message'), $signature, 'identical signature';
};

subtest 'validate_tags' => sub {
  subtest 'undef and empty inputs' => sub {
    my ($clean, $error) = validate_tags(undef);
    is_deeply $clean, [], 'undef yields empty array';
    is $error, undef, 'no error';

    ($clean, $error) = validate_tags([]);
    is_deeply $clean, [], 'empty array stays empty';
    is $error, undef, 'no error';
  };

  subtest 'happy paths' => sub {
    my ($clean, $error) = validate_tags(['review']);
    is_deeply $clean, ['review'], 'single tag passes through';
    is $error, undef, 'no error';

    ($clean, $error) = validate_tags(['review', 'demo', 'triage']);
    is_deeply $clean, ['review', 'demo', 'triage'], 'multiple tags preserve order';

    ($clean, $error) = validate_tags(['  review  ']);
    is_deeply $clean, ['review'], 'whitespace trimmed';

    ($clean, $error) = validate_tags(['review', 'review', 'demo', 'review']);
    is_deeply $clean, ['review', 'demo'], 'duplicates collapsed, first occurrence wins';

    ($clean, $error) = validate_tags(['review', '', '   ', 'demo']);
    is_deeply $clean, ['review', 'demo'], 'empty and whitespace-only tags dropped';
  };

  subtest 'length cap (32 characters)' => sub {
    my ($clean, $error) = validate_tags(['x' x 32]);
    is_deeply $clean, ['x' x 32], 'exactly 32 characters accepted';
    is $error, undef, 'no error at the boundary';

    ($clean, $error) = validate_tags(['x' x 33]);
    is $clean, undef, 'over-cap returns undef';
    like $error, qr/tag exceeds 32 characters/, 'error mentions the cap';
  };

  subtest 'count cap (16 tags)' => sub {
    my @sixteen = map {"t$_"} 1 .. 16;
    my ($clean, $error) = validate_tags([@sixteen]);
    is_deeply $clean, [@sixteen], 'exactly 16 tags accepted';
    is $error, undef, 'no error at the boundary';

    ($clean, $error) = validate_tags([@sixteen, 't17']);
    is $clean, undef, 'over-cap returns undef';
    like $error, qr/too many tags, maximum is 16/, 'error mentions the cap';

    # Whitespace-only entries don't count toward the cap.
    ($clean, $error) = validate_tags([@sixteen, '', '   ']);
    is_deeply $clean, [@sixteen], 'blank fillers do not consume the budget';
    is $error, undef, 'no error';
  };

  subtest 'rejects non-string elements' => sub {
    my ($clean, $error) = validate_tags('review');
    is $clean, undef, 'scalar input rejected';
    like $error, qr/tags must be an array of strings/, 'error explains';

    ($clean, $error) = validate_tags({review => 1});
    is $clean, undef, 'hashref input rejected';
    like $error, qr/tags must be an array of strings/, 'error explains';

    ($clean, $error) = validate_tags(['review', [], 'demo']);
    is $clean, undef, 'arrayref element rejected';
    like $error, qr/tags must be an array of strings/, 'error explains';

    ($clean, $error) = validate_tags(['review', undef]);
    is $clean, undef, 'undef element rejected';
    like $error, qr/tags must be an array of strings/, 'error explains';
  };
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

subtest 'license_is_catch_all' => sub {
  ok license_is_catch_all('Any Permissive'),      'an "Any ..." grab-bag is catch_all';
  ok license_is_catch_all('Any reference local'), 'another "Any ..." grab-bag is catch_all';
  ok license_is_catch_all('GPL-Unspecified'),     'a version-less family marker is catch_all';
  ok license_is_catch_all('LGPL Unspecified'),    'the space-separated variant is catch_all';
  ok license_is_catch_all('All Rights Reserved'), 'the proprietary default marker is catch_all';
  ok license_is_catch_all('Public-Domain'),       'the public-domain marker is catch_all';

  ok !license_is_catch_all('MIT'),                            'a concrete SPDX license is not catch_all';
  ok !license_is_catch_all('GPL-2.0 WITH Linking-exception'), 'a concrete WITH-exception license is not catch_all';
  ok !license_is_catch_all('LPPL-1.3'),                       'a concrete non-SPDX-id license is not catch_all';
  ok !license_is_catch_all(''),                               'the empty (keyword) license is not catch_all';
  ok !license_is_catch_all(undef),                            'undef is not catch_all';

  # Composite expressions ending in "Unspecified" are swept in (the safe direction for coverage)
  ok license_is_catch_all('MIT OR BSD-Unspecified'), 'a composite ending in Unspecified is treated as catch_all';
};

done_testing;
