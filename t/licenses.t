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
use Cavil::Licenses 'lic';

sub is_part_of {
  my ($first, $second) = @_;
  ok(lic($first)->is_part_of(lic($second)), qq{"$second" is part of "$first"});
}

sub isnt_part_of {
  my ($first, $second) = @_;
  ok !lic($first)->is_part_of(lic($second)), qq{"$second" is not part of "$first"};
}

sub is_similar_to {
  my ($first, $second) = @_;
  ok(lic($first)->is_similar_to(lic($second)), qq{"$second" is similar to "$first"});
}

sub isnt_similar_to {
  my ($first, $second) = @_;
  ok !lic($first)->is_similar_to(lic($second)), qq{"$second" is not similar to "$first"};
}

sub is_example {
  my ($first, $second) = @_;
  is(lic($first)->example, $second, qq{example out of "$first" is "$second"});
}

# Just a license
my $l = lic('AGPL-3.0-only');
ok !$l->normalized, 'not normalized';
ok !$l->exception,  'no exception';
is $l->error, undef, 'no error';
is_deeply $l->tree, {license => 'AGPL-3.0-only'}, 'right structure';
is $l->to_string, 'AGPL-3.0-only', 'right string';
is "$l",          'AGPL-3.0-only', 'right string';
is_deeply $l->canonicalize->tree, {license => 'AGPL-3.0-only'}, 'right canonicalized structure';

subtest 'LicenseRef-* (SPDX license identifier not yet part of the spec)' => sub {
  my $l = lic('LicenseRef-NPSL-0.95');
  ok !$l->normalized, 'not normalized';
  is $l->error, undef, 'no error';
  is_deeply $l->tree, {license => 'LicenseRef-NPSL-0.95'}, 'right structure';
};

# License with whitespace
$l = lic('Academic Free License 2.1');
ok $l->normalized, 'normalized';
is $l->error, undef, 'no error';
is_deeply $l->tree, {license => 'AFL-2.1'}, 'right structure';

# Normalized license
$l = lic('SUSE-AGPL-3.0+');
ok $l->normalized, 'normalized';
is $l->error, undef, 'no error';
is_deeply $l->tree, {license => 'AGPL-3.0-or-later'}, 'right structure';

subtest 'Valid license expression with "+"' => sub {
  my $l = lic('CDDL-1.0+');
  ok !$l->normalized, 'not normalized';
  is $l->error, undef, 'no error';
  is_deeply $l->tree, {license => 'CDDL-1.0+'}, 'right structure';

  $l = lic('MIT or CDDL-1.0+');
  ok !$l->normalized, 'not normalized';
  is $l->error, undef, 'no error';
  is_deeply $l->tree, {left => {license => 'MIT'}, op => 'or', right => {license => 'CDDL-1.0+'}}, 'right structure';
};

# Useless operator
$l = lic('AGPL-3.0-only and');
ok !$l->normalized, 'not normalized';
is $l->error, undef, 'no error';
is_deeply $l->tree, {license => 'AGPL-3.0-only'}, 'right structure';

# License exception
$l = lic('LGPL-2.1-or-later WITH WxWindows-exception-3.1');
ok !$l->normalized, 'not normalized';
ok $l->exception,   'exception';
is $l->error, undef, 'no error';
is_deeply $l->tree, {license => 'LGPL-2.1-or-later WITH WxWindows-exception-3.1'}, 'right structure';

# Invalid license exception
$l = lic('MIT OR LGPL-2.1-or-later WITH some-unknown-exception OR Artistic-2.0+');
ok !$l->normalized, 'not normalized';
ok $l->exception,   'exception';
is $l->error, 'Invalid SPDX license exception: some-unknown-exception', 'error';

# SUSE license with exception in name
$l = lic('GPL-3.0-with-Qt-Company-Qt-exception-1.1');
ok !$l->normalized, 'not normalized';
ok !$l->exception,  'no exception';
is $l->error, 'Invalid SPDX license: GPL-3.0-with-Qt-Company-Qt-exception-1.1', 'error';

# Multiple licenses
$l = lic('AGPL-3.0-only AND Ruby AND Artistic-1.0');
ok !$l->normalized, 'not normalized';
is $l->error, undef, 'no error';
my $ast = {
  left  => {license => 'AGPL-3.0-only'},
  op    => 'and',
  right => {left => {license => 'Ruby'}, op => 'and', right => {license => 'Artistic-1.0'}}
};
is_deeply $l->tree, $ast, 'right structure';
is "$l", 'AGPL-3.0-only AND Ruby AND Artistic-1.0', 'right string';
is_deeply $l->canonicalize->to_string, 'AGPL-3.0-only AND Artistic-1.0 AND Ruby', 'right canonicalized string';

$l = lic('AGPL-3.0-only; Ruby;Artistic-1.0');
ok $l->normalized, 'normalized';
is $l->error, undef, 'no error';
is_deeply $l->tree, $ast, 'right structure';
is $l->to_string, 'AGPL-3.0-only AND Ruby AND Artistic-1.0', 'right string';

# Parentheses
$l = lic('(LGPL-2.1-only OR LGPL-3.0-only) AND (GPL-3.0-or-later OR GPL-2.0-only)');
ok !$l->normalized, 'not normalized';
ok !$l->exception,  'no exception';
is $l->error, undef, 'no error';
$ast = {
  left  => {left => {license => 'LGPL-2.1-only'}, op => 'or', right => {license => 'LGPL-3.0-only'}},
  op    => 'and',
  right => {left => {license => 'GPL-3.0-or-later'}, op => 'or', right => {license => 'GPL-2.0-only'}}
};
is_deeply $l->tree, $ast, 'right structure';
is $l->to_string, '(LGPL-2.1-only OR LGPL-3.0-only) AND (GPL-3.0-or-later OR GPL-2.0-only)', 'right string';
is $l->canonicalize->to_string, '(GPL-2.0-only OR GPL-3.0-or-later) AND (LGPL-2.1-only OR LGPL-3.0-only)',
  'right canonicalized string';

# Parentheses and license exceptions
$l
  = lic('(LGPL-2.1 WITH i2p-gpl-java-exception '
    . 'or LGPL-3.0-only WITH Autoconf-exception-2.0) '
    . 'and (GPL-3.0-or-later with freertos-exception-2.0 '
    . 'or GPL-2.0-only With Linux-syscall-note )');
ok $l->normalized, 'normalized';
ok $l->exception,  'exception';
is $l->error, undef, 'no error';
$ast = {
  left => {
    left  => {license => 'LGPL-2.1-only WITH i2p-gpl-java-exception'},
    op    => 'or',
    right => {license => 'LGPL-3.0-only WITH Autoconf-exception-2.0'}
  },
  op    => 'and',
  right => {
    left  => {license => 'GPL-3.0-or-later WITH freertos-exception-2.0'},
    op    => 'or',
    right => {license => 'GPL-2.0-only WITH Linux-syscall-note'}
  }
};
is_deeply $l->tree, $ast, 'right structure';
is $l->to_string, '(LGPL-2.1-only WITH i2p-gpl-java-exception OR LGPL-3.0-only WITH Autoconf-exception-2.0)'
  . ' AND (GPL-3.0-or-later WITH freertos-exception-2.0 OR GPL-2.0-only WITH Linux-syscall-note)', 'right string';
is $l->canonicalize->to_string,
  '(GPL-2.0-only WITH Linux-syscall-note OR GPL-3.0-or-later WITH freertos-exception-2.0)'
  . ' AND (LGPL-2.1-only WITH i2p-gpl-java-exception OR LGPL-3.0-only WITH Autoconf-exception-2.0)',
  'right canonicalized string';

# Nested parentheses, operators and normalized licenses
$l = lic('(Ruby AND (GPL-1.0+ OR (Artistic-1.0 AND ASL 1.1)) AND AGPL-3.0)');
ok $l->normalized, 'normalized';
is $l->error, undef, 'no error';
$ast = {
  left  => {license => 'Ruby'},
  op    => 'and',
  right => {
    left => {
      left  => {license => 'GPL-1.0-or-later'},
      op    => 'or',
      right => {left => {license => 'Artistic-1.0'}, op => 'and', right => {license => 'Apache-1.1'}}
    },
    op    => 'and',
    right => {license => 'AGPL-3.0-only'}
  }
};
is_deeply $l->tree, $ast, 'right structure';
is $l->to_string, 'Ruby AND (GPL-1.0-or-later OR (Artistic-1.0 AND Apache-1.1))' . ' AND AGPL-3.0-only', 'right string';
is $l->canonicalize->to_string, '((Apache-1.1 AND Artistic-1.0) OR GPL-1.0-or-later)' . ' AND AGPL-3.0-only AND Ruby',
  'right canonicalized string';

# Operator precedence
$l->parse('Ruby AND GPL-1.0-or-later OR Artistic-1.0 AND AGPL-3.0-only');
ok !$l->normalized, 'not normalized';
is $l->error, undef, 'no error';
$ast = {
  left  => {left => {license => 'Ruby'}, op => 'and', right => {license => 'GPL-1.0-or-later'}},
  op    => 'or',
  right => {left => {license => 'Artistic-1.0'}, op => 'and', right => {license => 'AGPL-3.0-only'}}
};
is_deeply $l->tree, $ast, 'right structure';
is $l->to_string, '(Ruby AND GPL-1.0-or-later) OR (Artistic-1.0 AND AGPL-3.0-only)', 'right string';
is $l->canonicalize->to_string, '(AGPL-3.0-only AND Artistic-1.0) OR (GPL-1.0-or-later AND Ruby)',
  'right canonicalized string';

subtest 'SUSE license' => sub {
  $l = lic('SUSE-Freeware');
  ok $l->normalized, 'normalized';
  is $l->error, undef, 'no error';
  is_deeply $l->tree, {license => 'LicenseRef-SUSE-Freeware'}, 'right structure';
  is $l->to_string, 'LicenseRef-SUSE-Freeware', 'right string';
};

# Partial match
$l = lic('SUSE-Apache-2.0+');
ok $l->normalized, 'normalized';
is $l->error, undef, 'no error';
$ast = {license => 'Apache-2.0+'};
is_deeply $l->tree, $ast, 'right structure';
is "$l", 'Apache-2.0+', 'right string';
is_deeply $l->canonicalize->to_string, 'Apache-2.0+', 'right canonicalized string';

# Bad parentheses
$l = lic('(LGPL-2.1-only OR LGPL-3.0-only AND (GPL-2.0-only OR GPL-3.0-only');
ok !$l->normalized, 'not normalized';
is $l->error, 'Invalid license expression: (LGPL-2.1-only OR LGPL-3.0-only' . ' AND (GPL-2.0-only OR GPL-3.0-only',
  'right error';
is_deeply $l->tree, undef, 'no structure';
$l = lic('(LGPL-2.1-only OR LGPL-3.0-only AND (GPL-2.0-only OR GPL-3.0-only)');
ok !$l->normalized, 'not normalized';
is $l->error, 'Invalid license expression: (LGPL-2.1-only OR LGPL-3.0-only' . ' AND (GPL-2.0-only OR GPL-3.0-only)',
  'right error';
is_deeply $l->tree, undef, 'no structure';

# Invalid SPDX license
$l = lic('SomeLicense-1.0');
ok !$l->normalized, 'not normalized';
is $l->error, 'Invalid SPDX license: SomeLicense-1.0', 'right error';
is_deeply $l->tree, undef, 'no structure';
$l = lic('Apache-2.0 AND MPLv2.0');
ok !$l->normalized, 'not normalized';
is $l->error, 'Invalid SPDX license: MPLv2.0', 'right error';
is_deeply $l->tree, undef, 'no structure';

# Macro
$l = lic('%{license_apache2} AND %{license_mit}');
ok !$l->normalized, 'not normalized';
is $l->error, 'Invalid license expression: %{license_apache2} AND %{license_mit}', 'right error';
is_deeply $l->tree, undef, 'no structure';

# Part of
is_part_of 'Apache-1.0 AND Apache-2.0',            'Apache-1.0';
is_part_of 'Apache-1.0 AND Apache-2.0',            'Apache-2.0';
is_part_of 'Apache-1.0 AND Apache-2.0',            'Apache-2.0 AND Apache-1.0';
is_part_of 'Apache-1.0 OR Apache-2.0',             'Apache-1.0 OR Apache-2.0';
is_part_of 'Apache-1.0 OR Apache-2.0 AND GPL-1.0', 'Apache-1.0 OR Apache-2.0';
is_part_of 'Apache-1.0 OR Apache-2.0 AND Ruby',    'Apache-1.0 OR Apache-2.0 AND Ruby';

# Not part of
isnt_part_of 'Apache-1.0', 'Apache-2.0';
isnt_part_of 'Apache-1.0', 'Ruby';
isnt_part_of 'Apache-1.0', 'Apache-1.0 AND Apache-2.0';

# Similar licenses
is_similar_to 'Apache-1.0', 'Apache-1.0';
isnt_similar_to 'Apache-1.0', 'Apache-2.0';
isnt_similar_to 'Apache-1.0', 'Apache-1.0 AND Apache-2.0';
is_similar_to 'Apache-1.0 AND Apache-2.0',                      'Apache-1.0 AND Apache-2.0';
is_similar_to 'Apache-2.0 AND Apache-1.0',                      'Apache-1.0 AND Apache-2.0';
is_similar_to 'Ruby AND GPL-1.0+ OR Artistic-1.0 and AGPL-3.0', ' (AGPL-3.0 and Artistic-1.0) OR (Ruby AND GPL-1.0+)';

is_example 'MIT',                            'MIT';
is_example 'GPL-1.0+ OR Artistic-1.0',       'Artistic-1.0';
is_example 'Artistic-1.0 AND GPL-1.0+',      'Artistic-1.0';
is_example '(LGPL-2.1+ OR MPL-1.1) AND MIT', 'LGPL-2.1-or-later';

# The building block must be total: never die and never warn on any input, so callers can rely on
# lic(...)->canonicalize->to_string || 'Unknown' style chains without guarding.
subtest 'invalid input is handled without dying or warning' => sub {
  my @cases = (
    'GPL-2.0 WITH Linking-exception',    # unknown exception
    'XFree86',                           # unknown license
    'LPPL-1.3',                          # ambiguous (only 1.3a/1.3c exist)
    'Python >= 2.0.1',                   # version expression
    'GPL-2.0 OR ANY',                    # bogus operand
    'MIT OR OR Apache-2.0',              # duplicate operator
    'OR MIT',                            # leading operator
    '() OR MIT',                         # empty group
    '(MIT',                              # unbalanced parenthesis
    '%{license_mit}',                    # rpm macro
    'MIT WITH Bogus-exception',          # unknown exception
  );
  for my $c (@cases) {
    my @warnings;
    local $SIG{__WARN__} = sub { push @warnings, $_[0] };
    my $l     = lic($c);
    my $canon = eval { $l->to_string };
    ok !$@, qq{to_string does not die on "$c"};
    is $canon, '', qq{to_string is empty for invalid "$c"};
    ok defined $l->error, qq{error is set for "$c"};
    ok !$l->is_valid,     qq{is_valid is false for "$c"};

    # canonicalize / example / is_part_of / is_similar_to must also be total on an error object
    is eval { $l->canonicalize->to_string } // '<die>', '', qq{canonicalize->to_string safe for "$c"};
    is eval { $l->example }                 // '<die>', '', qq{example safe for "$c"};
    ok !$@, qq{no death from canonicalize/example on "$c"};
    is scalar(@warnings), 0, qq{no warnings emitted for "$c"} or diag join '', @warnings;
  }
};

subtest 'is_part_of / is_similar_to are warning-free on compound vs leaf' => sub {
  my @warnings;
  local $SIG{__WARN__} = sub { push @warnings, $_[0] };
  ok lic('GPL-2.0-only AND (GPL-2.0-only OR GPL-3.0-only)')->is_part_of(lic('GPL-2.0-only')),
    'leaf is part of a compound expression';
  ok !lic('MIT')->is_part_of(lic('GPL-2.0-only OR GPL-3.0-only')),      'compound is not part of a leaf';
  ok lic('MIT OR Apache-2.0')->is_similar_to(lic('Apache-2.0 OR MIT')), 'order-independent similarity';
  ok !lic('MIT')->is_similar_to(lic('MIT AND Apache-2.0')),             'leaf not similar to compound';
  is scalar(@warnings), 0, 'comparing leaves against operator nodes never warns' or diag join '', @warnings;
};

subtest 'is_valid vs is_canonical' => sub {

  # Already-canonical valid SPDX: both true
  for my $good ('MIT', 'GPL-2.0-or-later', 'Apache-2.0 OR MIT', 'GPL-2.0-only WITH Classpath-exception-2.0') {
    ok lic($good)->is_valid,     qq{"$good" is_valid};
    ok lic($good)->is_canonical, qq{"$good" is_canonical};
  }

  # Valid but not canonical (normalized on parse): is_valid true, is_canonical false
  for my $norm (['GPL-2.0+', 'GPL-2.0-or-later'], ['GPL-2.0', 'GPL-2.0-only'], ['Expat', 'MIT']) {
    my ($in, $out) = @$norm;
    ok lic($in)->is_valid,      qq{"$in" is_valid (normalizes)};
    ok !lic($in)->is_canonical, qq{"$in" is not is_canonical};
    is lic($in)->to_string, $out, qq{"$in" canonicalizes to "$out"};
  }

  # Invalid: neither
  for my $bad ('XFree86', 'GPL-2.0 WITH Linking-exception') {
    ok !lic($bad)->is_valid,     qq{"$bad" is not is_valid};
    ok !lic($bad)->is_canonical, qq{"$bad" is not is_canonical};
  }

  # The empty expression is valid and canonical (used to clear a mapping)
  ok lic('')->is_valid,     'empty is_valid';
  ok lic('')->is_canonical, 'empty is_canonical';
  is lic('')->to_string, '', 'empty stringifies to empty';
};

subtest 'SPDX operators are canonical and idempotent' => sub {

  # Operators are case-insensitive on input, uppercase on output (license ids keep their canonical case)
  is lic('MIT and Apache-2.0')->to_string, 'MIT AND Apache-2.0', 'lowercase "and" normalized to uppercase';
  is lic('MIT or Apache-2.0')->to_string,  'MIT OR Apache-2.0',  'lowercase "or" normalized to uppercase';

  # A dangling trailing operator is tolerated (non-lossy): the real license is kept, not an error
  is lic('MIT OR')->to_string,  'MIT', 'trailing OR tolerated';
  is lic('MIT AND')->to_string, 'MIT', 'trailing AND tolerated';

  # "+" operator preserved on ids without a dedicated -or-later form
  ok lic('CDDL-1.0+')->is_canonical, 'CDDL-1.0+ is canonical (real "+" operator)';

  # AND binds tighter than OR (WITH > AND > OR) and round-trips with parentheses
  my $expr = 'Ruby AND GPL-1.0-or-later OR Artistic-1.0 AND AGPL-3.0-only';
  is lic($expr)->to_string, '(Ruby AND GPL-1.0-or-later) OR (Artistic-1.0 AND AGPL-3.0-only)',
    'AND binds tighter than OR, rendered with parentheses';

  # Full SPDX grammar corners: precedence, parentheses/nesting, refs
  is lic('MIT OR GPL-2.0-only AND Apache-2.0')->to_string, 'MIT OR (GPL-2.0-only AND Apache-2.0)',
    'OR is lowest precedence';
  is lic('MIT AND GPL-2.0-only WITH Classpath-exception-2.0')->to_string,
    'MIT AND GPL-2.0-only WITH Classpath-exception-2.0', 'WITH binds tighter than AND';
  is lic('((MIT OR Apache-2.0))')->to_string, 'MIT OR Apache-2.0',  'redundant nested parentheses collapse';
  is lic('MIT AND (Apache-2.0)')->to_string,  'MIT AND Apache-2.0', 'redundant parentheses around a leaf collapse';
  ok lic('LicenseRef-Foo-1.0')->is_valid,                       'LicenseRef- is a valid license';
  ok lic('DocumentRef-spdx-tool-1.2:LicenseRef-Xyz')->is_valid, 'DocumentRef-...:LicenseRef- external ref is valid';
  is lic('MIT OR DocumentRef-x:LicenseRef-y')->to_string, 'MIT OR DocumentRef-x:LicenseRef-y',
    'external ref round-trips inside an expression';

  # Idempotence: a canonical string re-parses to itself, and canonicalize is a fixed point
  for my $s (
    'MIT', 'GPL-2.0-or-later',
    'MIT OR Apache-2.0',
    'GPL-2.0-only WITH Classpath-exception-2.0',
    '(GPL-2.0-only OR GPL-3.0-or-later) AND (LGPL-2.1-only OR LGPL-3.0-only)'
    )
  {
    is lic($s)->to_string, $s, qq{"$s" round-trips};
    my $canon = lic($s)->canonicalize->to_string;
    is lic($canon)->canonicalize->to_string, $canon, qq{"$s" canonicalize is a fixed point};
  }
};

done_testing;
