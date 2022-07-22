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

# Useless operator
$l = lic('AGPL-3.0-only and');
ok !$l->normalized, 'not normalized';
is $l->error, undef, 'no error';
is_deeply $l->tree, {license => 'AGPL-3.0-only'}, 'right structure';

# License exception
$l = lic('LGPL-2.1-or-later WITH WxWindows-exception-3.1');
ok $l->normalized, 'normalized';
ok $l->exception,  'exception';
is $l->error, undef, 'no error';
is_deeply $l->tree, {license => 'LGPL-2.1-or-later'}, 'right structure';

# SUSE license with exception in name
$l = lic('GPL-3.0-with-Qt-Company-Qt-exception-1.1');
ok !$l->normalized, 'not normalized';
ok !$l->exception,  'no exception';
is $l->error, undef, 'no error';
is_deeply $l->tree, {license => 'GPL-3.0-with-Qt-Company-Qt-exception-1.1'}, 'right structure';

# Multiple licenses
$l = lic('AGPL-3.0-only and Ruby and Artistic-1.0');
ok !$l->normalized, 'not normalized';
is $l->error, undef, 'no error';
my $ast = {
  left  => {license => 'AGPL-3.0-only'},
  op    => 'and',
  right => {left => {license => 'Ruby'}, op => 'and', right => {license => 'Artistic-1.0'}}
};
is_deeply $l->tree, $ast, 'right structure';
is "$l", 'AGPL-3.0-only and Ruby and Artistic-1.0', 'right string';
is_deeply $l->canonicalize->to_string, 'AGPL-3.0-only and Artistic-1.0 and Ruby', 'right canonicalized string';

$l = lic('AGPL-3.0-only; Ruby;Artistic-1.0');
ok $l->normalized, 'normalized';
is $l->error, undef, 'no error';
is_deeply $l->tree, $ast, 'right structure';
is $l->to_string, 'AGPL-3.0-only and Ruby and Artistic-1.0', 'right string';

# Parentheses
$l = lic('(LGPL-2.1-only or LGPL-3.0-only) and (GPL-3.0-or-later or GPL-2.0-only)');
ok !$l->normalized, 'not normalized';
ok !$l->exception,  'no exception';
is $l->error, undef, 'no error';
$ast = {
  left  => {left => {license => 'LGPL-2.1-only'}, op => 'or', right => {license => 'LGPL-3.0-only'}},
  op    => 'and',
  right => {left => {license => 'GPL-3.0-or-later'}, op => 'or', right => {license => 'GPL-2.0-only'}}
};
is_deeply $l->tree, $ast, 'right structure';
is $l->to_string, '(LGPL-2.1-only or LGPL-3.0-only) and (GPL-3.0-or-later or GPL-2.0-only)', 'right string';
is $l->canonicalize->to_string, '(GPL-2.0-only or GPL-3.0-or-later) and (LGPL-2.1-only or LGPL-3.0-only)',
  'right canonicalized string';

# Parentheses and license exceptions
$l
  = lic('(LGPL-2.1 WITH i2p-gpl-java-exception '
    . 'or LGPL-3.0-only With Autoconf-exception-2.0) '
    . 'and (GPL-3.0-or-later with freertos-exception-2.0 '
    . 'or GPL-2.0-only with Linux-syscall-note )');
ok $l->normalized, 'normalized';
ok $l->exception,  'exception';
is $l->error, undef, 'no error';
$ast = {
  left  => {left => {license => 'LGPL-2.1-only'}, op => 'or', right => {license => 'LGPL-3.0-only'}},
  op    => 'and',
  right => {left => {license => 'GPL-3.0-or-later'}, op => 'or', right => {license => 'GPL-2.0-only'}}
};
is_deeply $l->tree, $ast, 'right structure';
is $l->to_string, '(LGPL-2.1-only or LGPL-3.0-only) and (GPL-3.0-or-later or GPL-2.0-only)', 'right string';
is $l->canonicalize->to_string, '(GPL-2.0-only or GPL-3.0-or-later) and (LGPL-2.1-only or LGPL-3.0-only)',
  'right canonicalized string';

# Nested parentheses, operators and normalized licenses
$l = lic('(Ruby and (GPL-1.0+ or (Artistic-1.0 and ASL 1.1)) and AGPL-3.0)');
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
is $l->to_string, 'Ruby and (GPL-1.0-or-later or (Artistic-1.0 and Apache-1.1))' . ' and AGPL-3.0-only', 'right string';
is $l->canonicalize->to_string, '((Apache-1.1 and Artistic-1.0) or GPL-1.0-or-later)' . ' and AGPL-3.0-only and Ruby',
  'right canonicalized string';

# Operator precedence
$l->parse('Ruby and GPL-1.0-or-later or Artistic-1.0 and AGPL-3.0-only');
ok !$l->normalized, 'not normalized';
is $l->error, undef, 'no error';
$ast = {
  left  => {left => {license => 'Ruby'}, op => 'and', right => {license => 'GPL-1.0-or-later'}},
  op    => 'or',
  right => {left => {license => 'Artistic-1.0'}, op => 'and', right => {license => 'AGPL-3.0-only'}}
};
is_deeply $l->tree, $ast, 'right structure';
is $l->to_string, '(Ruby and GPL-1.0-or-later) or (Artistic-1.0 and AGPL-3.0-only)', 'right string';
is $l->canonicalize->to_string, '(AGPL-3.0-only and Artistic-1.0) or (GPL-1.0-or-later and Ruby)',
  'right canonicalized string';

# Partial match
$l = lic('SUSE-Freeware');
ok !$l->normalized, 'not normalized';
is $l->error, undef, 'no error';
$ast = {license => 'SUSE-Freeware'};
is_deeply $l->tree, $ast, 'right structure';
is "$l", 'SUSE-Freeware', 'right string';
is_deeply $l->canonicalize->to_string, 'SUSE-Freeware', 'right canonicalized string';
$l = lic('SUSE-Apache-2.0+');
ok $l->normalized, 'normalized';
is $l->error, undef, 'no error';
$ast = {license => 'Apache-2.0+'};
is_deeply $l->tree, $ast, 'right structure';
is "$l", 'Apache-2.0+', 'right string';
is_deeply $l->canonicalize->to_string, 'Apache-2.0+', 'right canonicalized string';

# Bad parentheses
$l = lic('(LGPL-2.1-only or LGPL-3.0-only and (GPL-2.0-only or GPL-3.0-only');
ok !$l->normalized, 'not normalized';
is $l->error, 'Invalid license expression: (LGPL-2.1-only or LGPL-3.0-only' . ' and (GPL-2.0-only or GPL-3.0-only',
  'right error';
is_deeply $l->tree, undef, 'no structure';
$l = lic('(LGPL-2.1-only or LGPL-3.0-only and (GPL-2.0-only or GPL-3.0-only)');
ok !$l->normalized, 'not normalized';
is $l->error, 'Invalid license expression: (LGPL-2.1-only or LGPL-3.0-only' . ' and (GPL-2.0-only or GPL-3.0-only)',
  'right error';
is_deeply $l->tree, undef, 'no structure';

# Invalid SPDX license
$l = lic('SomeLicense-1.0');
ok !$l->normalized, 'not normalized';
is $l->error, 'Invalid SPDX license: SomeLicense-1.0', 'right error';
is_deeply $l->tree, undef, 'no structure';
$l = lic('Apache-2.0 and MPLv2.0');
ok !$l->normalized, 'not normalized';
is $l->error, 'Invalid SPDX license: MPLv2.0', 'right error';
is_deeply $l->tree, undef, 'no structure';

# Macro
$l = lic('%{license_apache2} and %{license_mit}');
ok !$l->normalized, 'not normalized';
is $l->error, 'Invalid license expression: %{license_apache2} and %{license_mit}', 'right error';
is_deeply $l->tree, undef, 'no structure';

# Part of
is_part_of 'Apache-1.0 and Apache-2.0',            'Apache-1.0';
is_part_of 'Apache-1.0 and Apache-2.0',            'Apache-2.0';
is_part_of 'Apache-1.0 and Apache-2.0',            'Apache-2.0 and Apache-1.0';
is_part_of 'Apache-1.0 or Apache-2.0',             'Apache-1.0 or Apache-2.0';
is_part_of 'Apache-1.0 or Apache-2.0 and GPL-1.0', 'Apache-1.0 or Apache-2.0';
is_part_of 'Apache-1.0 or Apache-2.0 and Ruby',    'Apache-1.0 or Apache-2.0 and Ruby';

# Not part of
isnt_part_of 'Apache-1.0', 'Apache-2.0';
isnt_part_of 'Apache-1.0', 'Ruby';
isnt_part_of 'Apache-1.0', 'Apache-1.0 and Apache-2.0';

# Similar licenses
is_similar_to 'Apache-1.0', 'Apache-1.0';
isnt_similar_to 'Apache-1.0', 'Apache-2.0';
isnt_similar_to 'Apache-1.0', 'Apache-1.0 and Apache-2.0';
is_similar_to 'Apache-1.0 and Apache-2.0',                      'Apache-1.0 and Apache-2.0';
is_similar_to 'Apache-2.0 and Apache-1.0',                      'Apache-1.0 and Apache-2.0';
is_similar_to 'Ruby and GPL-1.0+ or Artistic-1.0 and AGPL-3.0', ' (AGPL-3.0 and Artistic-1.0) or (Ruby and GPL-1.0+)';

is_example 'MIT',                            'MIT';
is_example 'GPL-1.0+ or Artistic-1.0',       'Artistic-1.0';
is_example 'Artistic-1.0 and GPL-1.0+',      'Artistic-1.0';
is_example '(LGPL-2.1+ or MPL-1.1) and MIT', 'LGPL-2.1-or-later';

done_testing;
