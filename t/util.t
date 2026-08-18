# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Mojo::Base -strict;

use Test::More;
use Mojo::File qw(path curfile tempfile);
use Mojo::JSON qw(decode_json);
use Cavil::Util (
  qw(buckets expand_spec_macros extract_copyrights legal_review_notices lines_context license_is_catch_all),
  qw(license_text),
  qw(normalize_license_expr obs_ssh_auth),
  qw(parse_exclude_file parse_service_file normalize_license_text pattern_matches pattern_contains_redundant_skip read_lines),
  qw(external_link_data incoming_priority request_id_from_external_link run_cmd spdx_link ssh_sign text_shingles),
  qw(validate_tags PRIORITY_INCOMING PRIORITY_UPKEEP PRIORITY_WAITING),
  qw(decode_json_fast encode_json_fast to_json_fast)
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

subtest 'expand_spec_macros' => sub {

  # Pull the value of a spec tag out of the expanded text, exactly like Checkout parses it later
  my $tag = sub {
    my ($spec, $name) = @_;
    for my $line (split "\n", expand_spec_macros($spec)) {
      return $1 if $line =~ /^\Q$name\E:\s*(.+?)\s*$/;
    }
    return undef;
  };

  subtest 'simple substitution' => sub {
    is $tag->("%define foo bar\nVersion: %{foo}\n", 'Version'), 'bar', 'braced reference';
    is $tag->("%define foo bar\nVersion: %foo\n",   'Version'), 'bar', 'bare reference';
    is $tag->("%global foo bar\nVersion: %{foo}\n", 'Version'), 'bar', '%global behaves like %define';
    is $tag->("%define   foo   bar baz \nVersion: %{foo}\n", 'Version'), 'bar baz',
      'extra whitespace and multi-word values';
  };

  subtest 'definition order does not matter' => sub {
    is $tag->("Version: %{foo}\n%define foo bar\n", 'Version'), 'bar', 'macro defined after use still resolves';
    is $tag->("%define foo one\n%define foo two\nVersion: %{foo}\n", 'Version'), 'one',
      'first definition wins, like rpm';
  };

  subtest 'chained macros (the Firefox case)' => sub {
    my $spec = "%define major 140\n%define mainver %major.13.0\nVersion: %{mainver}\n";
    is $tag->($spec, 'Version'), '140.13.0', 'mainver -> major resolves through several passes';
  };

  subtest 'tags are seeded like rpm auto-macros' => sub {
    my $spec = "Name: firefox\nVersion: 140.0\n" . "Source: http://ftp.example.org/%{name}/%{name}-%{version}.tar.xz\n";
    is $tag->($spec, 'Source'), 'http://ftp.example.org/firefox/firefox-140.0.tar.xz',
      '%{name} and %{version} come from the Name/Version tags';

    my $chained = "%define mainver 91.2\nName: tool\nVersion: %{mainver}\n" . "Source: %{name}-%{version}.tar.gz\n";
    is $tag->($chained, 'Source'), 'tool-91.2.tar.gz', 'seeded %{version} is itself macro-resolved';
  };

  subtest 'unknown macros are left untouched' => sub {
    is $tag->("Version: %{_prefix}/x\n", 'Version'), '%{_prefix}/x', 'undefined braced macro passes through';
    is $tag->("Version: %undefined\n",   'Version'), '%undefined',   'undefined bare macro passes through';
  };

  subtest 'active/unsafe macros are never evaluated' => sub {
    my $shell = "Version: %(echo pwned)\n";
    is $tag->($shell, 'Version'), '%(echo pwned)', 'shell expansion is left verbatim';

    my $expand = expand_spec_macros("%{expand:%%global x %(echo hi)}\nVersion: %{x}\n");
    like $expand, qr/\Q%{expand:\E/,   '%{expand:...} block is left verbatim';
    like $expand, qr/Version: %\{x\}/, 'macro from an expand block is not defined';

    # Conditional define: the "%define" is inside a %{!?...} guard, so it must not be captured
    my $cond = "%{!?_x: %global _x %{_y}/macros}\nVersion: %{_x}\n";
    is $tag->($cond, 'Version'), '%{_x}', 'conditional guard define is not captured';

    # Conditional references keep their sigil characters and are left alone
    is $tag->("Version: 0%{?dist}\n", 'Version'), '0%{?dist}', '%{?foo} conditional reference untouched';
  };

  subtest 'escaped %% is not a macro' => sub {
    is $tag->("%define major 140\nVersion: %%major.99\n", 'Version'), '%%major.99',
      'a literal %% is left alone even when the name is defined';
  };

  subtest '%if branches are not evaluated (best-effort, first wins)' => sub {
    my $spec = "%if 0%{?suse_version} > 1500\n%define ch release\n%else\n%define ch esr\n%endif\n" . "Version: %{ch}\n";
    is $tag->($spec, 'Version'), 'release', 'first branch definition is used without evaluating the condition';
  };

  subtest 'recursion and cycles terminate safely' => sub {
    my $self = "%define a %{a}\nVersion: %{a}\n";
    is $tag->($self, 'Version'), '%{a}', 'self-reference does not loop and is left unresolved';

    my $cycle = "%define a %{b}\n%define b %{a}\nVersion: %{a}\n";
    my $out   = $tag->($cycle, 'Version');
    like $out, qr/^%\{[ab]\}$/, 'mutual cycle terminates with an unresolved reference';
  };

  subtest 'hostile macro values cannot inject regex or replacement syntax' => sub {
    is $tag->("%define x \$1\\{oops\\}\nVersion: %{x}\n", 'Version'), '$1\\{oops\\}',
      'special characters in the value are substituted literally';
    is $tag->("%define x ^(lib.*)\$\nVersion: %{x}\n", 'Version'), '^(lib.*)$',
      'regex metacharacters in the value are not interpreted';
  };

  subtest 'defensive inputs' => sub {
    is expand_spec_macros(undef),                           undef,    'undef in, undef out';
    is expand_spec_macros(''),                              '',       'empty string is unchanged';
    is $tag->("%define foo\nVersion: %{foo}\n", 'Version'), '%{foo}', 'valueless define is skipped';

    # A pathological pile of references must not blow up; the pass cap bounds the work
    my $big = ("Version: " . ("%{u}" x 5000) . "\n");
    ok defined expand_spec_macros($big), 'large unresolved input returns without hanging';
  };
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
  is spdx_link('MIT'), '<button type="button" class="spdx-link" data-spdx="MIT">MIT</button>', 'known license';
  is spdx_link('Apache-2.0'), '<button type="button" class="spdx-link" data-spdx="Apache-2.0">Apache-2.0</button>',
    'known license';
  is spdx_link('Unknown-License'), 'Unknown-License', 'unknown license';

  subtest 'Expression with AND' => sub {
    is spdx_link('Apache-2.0 AND MIT'),
      '<button type="button" class="spdx-link" data-spdx="Apache-2.0">Apache-2.0</button>' . ' AND '
      . '<button type="button" class="spdx-link" data-spdx="MIT">MIT</button>';
  };

  subtest 'Expression with OR' => sub {
    is spdx_link('MIT OR GPL-2.0-only'), '<button type="button" class="spdx-link" data-spdx="MIT">MIT</button>' . ' OR '
      . '<button type="button" class="spdx-link" data-spdx="GPL-2.0-only">GPL-2.0-only</button>';
  };

  subtest 'Expression with parentheses and AND/OR' => sub {
    is spdx_link('(MIT OR Apache-2.0) AND GPL-2.0-only'),
        '('
      . '<button type="button" class="spdx-link" data-spdx="MIT">MIT</button>' . ' OR '
      . '<button type="button" class="spdx-link" data-spdx="Apache-2.0">Apache-2.0</button>'
      . ') AND '
      . '<button type="button" class="spdx-link" data-spdx="GPL-2.0-only">GPL-2.0-only</button>';
  };

  subtest 'Expression with exception' => sub {
    is spdx_link('Classpath-exception-2.0'),
      '<button type="button" class="spdx-link" data-spdx="Classpath-exception-2.0">Classpath-exception-2.0</button>',
      'SPDX exception only';

    is spdx_link('GPL-2.0-only WITH Classpath-exception-2.0'),
        '<button type="button" class="spdx-link" data-spdx="GPL-2.0-only">GPL-2.0-only</button>'
      . ' WITH '
      . '<button type="button" class="spdx-link" data-spdx="Classpath-exception-2.0">'
      . 'Classpath-exception-2.0</button>', 'SPDX license WITH exception';

    is spdx_link('MIT WITH Autoconf-exception-3.0'),
        '<button type="button" class="spdx-link" data-spdx="MIT">MIT</button>'
      . ' WITH '
      . '<button type="button" class="spdx-link" data-spdx="Autoconf-exception-3.0">'
      . 'Autoconf-exception-3.0</button>', 'MIT WITH Autoconf-exception-3.0';
  };

  subtest 'Untrusted text is HTML-escaped (no XSS)' => sub {

    # License strings can come from imported component metadata and are rendered with v-html, so any
    # non-link text must be escaped
    is spdx_link('MIT <img src=x onerror=alert(1)>'),
      '<button type="button" class="spdx-link" data-spdx="MIT">MIT</button>' . ' &lt;img src=x onerror=alert(1)&gt;',
      'markup around a known license is escaped';
    is spdx_link('<script>alert(1)</script>'), '&lt;script&gt;alert(1)&lt;/script&gt;',
      'unknown license with markup is fully escaped';
    is spdx_link('Foo & Bar'), 'Foo &amp; Bar', 'ampersands are escaped';
    unlike spdx_link('MIT" onmouseover="alert(1)'), qr/onmouseover="alert/, 'attribute-breaking text is escaped';
  };
};

subtest 'license_text' => sub {
  like license_text('MIT'),                     qr/Permission is hereby granted, free of charge/, 'a listed license';
  like license_text('Classpath-exception-2.0'), qr/link this library/i, 'an exception, which spdx_link also links';
  is license_text('Nope-1.0'), undef, 'an identifier that is not on the list';
  is license_text(''),         undef, 'no identifier at all';
  unlike license_text('MIT'), qr/\r/, 'no line endings introduced';
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
  ok license_is_catch_all('Any Permissive'),          'an "Any ..." grab-bag is catch_all';
  ok license_is_catch_all('Any reference local'),     'another "Any ..." grab-bag is catch_all';
  ok license_is_catch_all('Any Public Domain'),       'the public-domain marker is catch_all';
  ok license_is_catch_all('Any All Rights Reserved'), 'the proprietary default marker is catch_all';
  ok license_is_catch_all('GPL-Unspecified'),         'a version-less family marker is catch_all';
  ok license_is_catch_all('LGPL-Unspecified'),        'another version-less family marker is catch_all';

  ok !license_is_catch_all('MIT'),                            'a concrete SPDX license is not catch_all';
  ok !license_is_catch_all('GPL-2.0 WITH Linking-exception'), 'a concrete WITH-exception license is not catch_all';
  ok !license_is_catch_all('LPPL-1.3'),                       'a concrete non-SPDX-id license is not catch_all';
  ok !license_is_catch_all(''),                               'the empty (keyword) license is not catch_all';
  ok !license_is_catch_all(undef),                            'undef is not catch_all';

  # One placeholder anywhere in an expression makes the whole expression one, on either side of the operator
  ok license_is_catch_all('MIT OR BSD-Unspecified'),  'a composite naming an unspecified family is catch_all';
  ok license_is_catch_all('BSD-Unspecified OR MIT'),  'and so is the same statement written the other way round';
  ok license_is_catch_all('MIT AND BSD-Unspecified'), 'an unspecified half of an AND leaves it unknown too';
  ok license_is_catch_all('BSD-3-Clause AND Any Permissive'),     'a grab-bag component counts the same';
  ok license_is_catch_all('GPL-Unspecified WITH Font-Exception'), 'a version-less family carrying an exception';
  ok license_is_catch_all('(LGPL-Unspecified AND GPL-Unspecified) OR MIT'), 'components inside parentheses count';

  # Both conventions have to be spelled exactly, or the name no longer announces the flag
  ok !license_is_catch_all('LGPL Unspecified'), 'the space-separated variant is not catch_all';
  ok !license_is_catch_all('Anything'),         'a license merely starting with "Any" is not catch_all';
  ok !license_is_catch_all('GPL-2.0 WITH Unspecified-Exception'),
    'the suffix has to end a component, so an unknown exception has to be named "Exception-Unspecified"';
  ok !license_is_catch_all('LicenseRef-SUSE-Public-Domain'), 'a LicenseRef is an identified license';
};

subtest 'incoming_priority' => sub {
  is incoming_priority(5),     PRIORITY_INCOMING,     'an ordinary request is the incoming band itself';
  is incoming_priority(10),    PRIORITY_INCOMING + 5, 'the most urgent request is at the top of the band';
  is incoming_priority(1),     PRIORITY_INCOMING - 4, 'a product import is at the bottom of it';
  is incoming_priority(undef), PRIORITY_INCOMING,     'a request without one is treated as ordinary';

  # The review priority is not a queue priority, and a request cannot use it to leave the band
  is incoming_priority( 0),   PRIORITY_INCOMING - 4, 'below the scale is the bottom of the band';
  is incoming_priority(-100), PRIORITY_INCOMING - 4, 'and so is far below it';
  is incoming_priority( 11),  PRIORITY_INCOMING + 5, 'above the scale is the top of the band';
  is incoming_priority(1000), PRIORITY_INCOMING + 5, 'and so is far above it';

  ok incoming_priority(1) > PRIORITY_UPKEEP + 7, 'the least urgent import outranks every rebuild the queue makes';
  ok incoming_priority(10) < PRIORITY_WAITING,   'the most urgent one still yields to a reviewer waiting on a report';
};

subtest 'JSON helpers' => sub {
  subtest 'round-trip' => sub {
    my $data = {b => 2, a => [1, 'two', {c => 'three'}], "\x{fc}" => "\x{e4}", empty => {}, list => []};
    is_deeply decode_json_fast(encode_json_fast($data)),        $data, 'binary round-trip';
    is_deeply Mojo::JSON::from_json(to_json_fast($data)),       $data, 'text round-trip readable by Mojo::JSON';
    is_deeply decode_json_fast(Mojo::JSON::encode_json($data)), $data, 'Mojo::JSON output readable by us';

    is encode_json_fast("\x{e4}"), qq{"\xc3\xa4"}, 'binary encoder emits UTF-8 bytes';
    is to_json_fast("\x{e4}"),     qq{"\x{e4}"},   'text encoder emits characters';
    is encode_json_fast(undef),    'null',         'nonref allowed, as with Mojo::JSON';
    is to_json_fast(\1),           'true',         'booleans survive';
  };

  # Cavil keys hashes on filenames and contributor names straight out of the archive. Sorting those
  # keys, which is what Mojo::JSON's encoders do, never returns with Cpanel::JSON::XS 4.43 - so if this
  # subtest ever stops finishing rather than starts failing, "canonical" is back.
  subtest 'non-ASCII keys' => sub {
    my @names = ("Bj\x{f8}rn", "Rafa\x{142}", "Andr\x{e9}", "J\x{e9}r\x{f4}me", "M\x{e5}rten", "Wei\x{df}");
    my %hash  = map { ("$names[$_ % @names] Person$_" => $_) } 1 .. 500;
    is_deeply decode_json_fast(encode_json_fast(\%hash)),  \%hash, 'they survive the binary round-trip';
    is_deeply Mojo::JSON::from_json(to_json_fast(\%hash)), \%hash, 'and the text one';
  };

  # Everything Mojo::JSON sets except "canonical" is kept, so input that used to parse still parses
  is_deeply decode_json_fast('{"a":1,"a":2}'), {a => 2}, 'duplicate keys are still allowed, not fatal';
};

subtest 'legal_review_notices' => sub {
  is_deeply legal_review_notices("Name: foo\nLicense: MIT\n"), [], 'no notices';

  is_deeply legal_review_notices("# Legal-Review-Notice: single line\nLicense: MIT\n"), ['single line'], 'one-liner';

  is_deeply legal_review_notices("###  Legal-Review-Notice:  many hashes and spaces  \n"), ['many hashes and spaces'],
    'marker and whitespace stripped';

  is_deeply legal_review_notices("# Legal-Review-Notice: line one\n# line two\n# line three\nLicense: MIT\n"),
    ["line one\nline two\nline three"], 'continuation lines joined and stopped by a directive';

  is_deeply legal_review_notices("# Legal-Review-Notice: trailing space   \n# more   \n"), ["trailing space\nmore"],
    'trailing whitespace trimmed on every line';

  is_deeply legal_review_notices("# Legal-Review-Notice: first\n\n# an unrelated comment\n"), ['first'],
    'a blank line ends the notice';

  is_deeply legal_review_notices("# Legal-Review-Notice: first\n#\n# an unrelated comment\n"), ['first'],
    'an empty comment line ends the notice';

  is_deeply legal_review_notices("# Legal-Review-Notice: first\n###\n# an unrelated comment\n"), ['first'],
    'a hashes-only comment line ends the notice';

  is_deeply legal_review_notices("# Legal-Review-Notice: first\nName: foo\n# Legal-Review-Notice: second\n"),
    ['first', 'second'], 'two separate one-liners';

  is_deeply legal_review_notices("# Legal-Review-Notice: first\n# more\n# Legal-Review-Notice: second\n# also\n"),
    ["first\nmore", "second\nalso"], 'a new notice ends the previous block';

  is_deeply legal_review_notices("# Legal-Review-Notice: at the very end\n# with a continuation"),
    ["at the very end\nwith a continuation"], 'notice runs to the end of file';
};

subtest 'extract_copyrights' => sub {
  my $notices = sub { [sort keys %{extract_copyrights(shift)}] };

  subtest 'shapes that are notices' => sub {
    my @cases = (
      ['Copyright (c) 2018 Foo Bar',      'Copyright (c) 2018 Foo Bar'],
      ['Copyright 2013 Thorsten Lorenz.', 'Copyright 2013 Thorsten Lorenz.'], ['(c) 2018 Foo', '(c) 2018 Foo'],
      ['(C) Copyright 2002 Zwane Mwaikambo',          '(C) Copyright 2002 Zwane Mwaikambo'],
      ['Copyright © 2019 John Doe',                   'Copyright © 2019 John Doe'],
      ['SPDX-FileCopyrightText: 2019 Jane <j@e.org>', 'SPDX-FileCopyrightText: 2019 Jane <j@e.org>'],
      [' * Copyright (c) 2018 Foo',                   'Copyright (c) 2018 Foo'],
      ['// Copyright 2015 The Chromium Authors',      'Copyright 2015 The Chromium Authors'],
      ['# Copyright (C) 2024 SUSE LLC',               'Copyright (C) 2024 SUSE LLC'],

      # A notice on one line closes its comment on that line; the terminator is not part of the notice
      ['/* Copyright (c) 2019 Foo Bar */',    'Copyright (c) 2019 Foo Bar'],
      ['<!-- Copyright (c) 2019 Foo Bar -->', 'Copyright (c) 2019 Foo Bar'],

      # A notice with no year at all. The commonest single notice in the wild, and requiring a year
      # (as the SBOM writer used to) drops every one of them.
      [
        'Copyright (c) Microsoft Corporation. All rights reserved.',
        'Copyright (c) Microsoft Corporation. All rights reserved.'
      ],
      ['Copyright (c) Sindre Sorhus <s@s.com>', 'Copyright (c) Sindre Sorhus <s@s.com>'],

      # Patch files are most of an openSUSE package and carry notices behind a diff marker
      ['+Copyright (c) 2009 The Go Authors.', 'Copyright (c) 2009 The Go Authors.'],
      ['+ * Copyright (c) 2006 Intel Corp.',  'Copyright (c) 2006 Intel Corp.']
    );
    for my $case (@cases) {
      my ($input, $expected) = @$case;
      is_deeply $notices->($input), [$expected], "notice: $input";
    }
  };

  subtest 'shapes that are not notices' => sub {
    my @cases = (
      'Copyright',                                                   # nothing follows the anchor
      'The Copyright Office should be sent a form',                  # anchor not at the line start
      'copyright notice, this list of conditions and the follow',    # wrapped license text
      'COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR',       # wrapped warranty disclaimer
      'Copyright and related rights are waived via the Creative',    # CC0 prose, no holder
      'Copyright (C) YEAR NAME OF AUTHOR',                           # GPL boilerplate placeholder
      'Copyright [yyyy] [name of copyright owner]',                  # Apache boilerplate placeholder
      'Copyright (c) <year> <copyright holders>',                    # MIT boilerplate placeholder
      'Copyright (c) <YEAR>, <OWNER>',                               # BSD boilerplate placeholder
      'Copyright Holder, and derivatives of that collection',        # Artistic License defined term
      'Copyright Holder may include your modifications in the',      # Artistic License defined term
      'Copyright Holder. This restriction only applies to the',      # SIL OFL defined term

      # "(c)" also enumerates clauses. Apache-2.0 section 4(c) alone put this in 80 files of one package,
      # and prose, maths and protocol comments all open the same way.
      '(c) You must retain, in the Source form of any Derivative Works that You distribute, all',
      '(c) The stream ID is for a locally-created stream which does not exist yet. This is a',
      '(C) The PN is below the watermark.', '(c) 1 < qInv < p'
    );
    is_deeply $notices->($_), [], "not a notice: $_" for @cases;
  };

  subtest 'multi-line notices are collected whole' => sub {
    is_deeply $notices->("Copyright (c) 2011 The Chromium Authors\nAll rights reserved.\n"),
      ['Copyright (c) 2011 The Chromium Authors All rights reserved.'], 'the paired trailer comes along';

    is_deeply $notices->(" * Copyright (c) 2019\n *     Alice <a\@e.org>\n *     Bob <b\@e.org>\n"),
      ['Copyright (c) 2019 Alice <a@e.org> Bob <b@e.org>'], 'holders indented under a bare year';

    is_deeply $notices->("Copyright 2019 Foo Inc.,\nBar Ltd.\n"), ['Copyright 2019 Foo Inc., Bar Ltd.'],
      'a notice broken off mid sentence';

    # Without this the fold runs straight from the notice into the license and stores the two as one
    is_deeply $notices->("Copyright (c) Microsoft Corporation.\nLicensed under the Apache License\n"),
      ['Copyright (c) Microsoft Corporation.'], 'the license body ends the notice';

    is_deeply $notices->("Copyright (c) 2018 Foo\nCopyright (c) 2019 Bar\n"),
      ['Copyright (c) 2018 Foo', 'Copyright (c) 2019 Bar'], 'the next notice ends the previous one';

    is_deeply $notices->(" * Copyright (c) 2019\n\n *     Not A Holder\n"), ['Copyright (c) 2019'],
      'a blank line ends the notice';
  };

  subtest 'occurrences are counted' => sub {
    is_deeply extract_copyrights("Copyright 2019 Foo\nsome code\nCopyright 2019 Foo\n"), {'Copyright 2019 Foo' => 2},
      'one entry, counted twice';
  };

  subtest 'hostile input stays bounded' => sub {
    ok !%{extract_copyrights('')},             'empty string';
    ok !%{extract_copyrights("\x00\xff\xfe")}, 'binary noise';
    is_deeply $notices->('Copyright (c) 2019 Foo'), ['Copyright (c) 2019 Foo'], 'no trailing newline';

    # A line of nothing but comment leaders must not make the anchor backtrack; a nested quantifier
    # here is the classic way to hang a scanner that reads every file of every package
    my $punctuation = ('#*/;!|>+-' x 20_000) . "X\n";
    ok !%{extract_copyrights($punctuation)}, 'a long run of comment leaders is cheap';

    # Caps: notices per file, lines scanned, continuation lines folded, stored notice length
    my $many = join '', map {"Copyright (c) 2019 Holder $_\n"} 1 .. 500;
    is scalar keys %{extract_copyrights($many)}, 100, 'notices per file are capped';

    my $deep = "Copyright (c) 2019\n" . join '', map { (' ' x 40) . "Holder $_\n" } 1 .. 100;
    is_deeply $notices->($deep), ['Copyright (c) 2019 Holder 1 Holder 2 Holder 3 Holder 4'],
      'folding stops after a bounded run of continuation lines';

    # A single line long enough to matter is a minified blob and never reaches the length cap; folding
    # several wide continuation lines together is the way a stored notice can actually grow
    my $wide = 'Copyright (c) 2019 ' . ('A' x 250) . "\n";
    $wide .= join '', map { '    ' . ('B' x 250) . "\n" } 1 .. 4;
    is length $notices->($wide)->[0], 1024, 'a folded notice is truncated to its cap';

    my $blob = 'Copyright (c) 2019 ' . ('a' x 5000);
    is_deeply $notices->($blob), [], 'an over-long source line is a minified blob, not a notice';

    my $late = ("\n" x 25_000) . "Copyright (c) 2019 Too Far Down\n";
    is_deeply $notices->($late), [], 'lines past the scan cap are not examined';
  };
};

done_testing;
