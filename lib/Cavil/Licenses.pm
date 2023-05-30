# Copyright (C) 2018 SUSE Linux GmbH
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

package Cavil::Licenses;
use Mojo::Base -base, -signatures;
use overload bool => sub {1}, '""' => sub { shift->to_string }, fallback => 1;

use Exporter 'import';
use Mojo::File 'path';
use Text::Balanced 'extract_bracketed';
use Mojo::Util qw(dumper trim);

use constant DEBUG => $ENV{SUSE_LICENSES_DEBUG} || 0;

has [qw(error exception normalized tree)];

our @EXPORT_OK = ('lic');

# List from https://github.com/openSUSE/obs-service-format_spec_file
my (%ALLOWED, %CHANGES);
{
  my @lines = split "\n", path(__FILE__)->dirname->child('resources', 'license_changes.txt')->slurp;
  shift @lines;
  for my $line (@lines) {
    my ($target, $source) = split "\t", $line;
    $CHANGES{$source} = $target;
    $ALLOWED{$target}++;
  }
}

my $TOKEN_RE;
{
  my $token = join '|',
    map { '(?:(?<=[\s()])|^)' . quotemeta . '(?:(?=[\s()])|$)' } sort { length $b <=> length $a } keys %CHANGES;
  $TOKEN_RE = qr/($token)/;
}

sub canonicalize ($self) {
  $self->{tree} = _sorted_tree($self->{tree});
  return $self;
}

# return one of the licenses
sub example ($self) {
  return _example(_sorted_tree($self->{tree}));
}

sub is_part_of ($first, $second) { _walk($first->tree, $second->tree) }

sub is_similar_to ($first, $second) {
  $first->canonicalize->to_string eq $second->canonicalize->to_string;
}

sub lic (@args) { __PACKAGE__->new(@args) }

sub new ($class, @args) { @args > 0 ? $class->SUPER::new->parse(@args) : $class->SUPER::new }

# Partial implementation of SPDX 2.1 (with changes for expressions used at SUSE)
sub parse ($self, $string) {
  unless ($string) {
    return $self->tree({license => ''});
  }

  # Normalize licenses, convert ";" to "and" and remove "X with Y" exceptions
  my $before = $string;
  $string                        =~ s/$TOKEN_RE/$CHANGES{$1}/xgo;
  $string                        =~ s/\s*;\s*/ and /g;
  $self->exception(1) if $string =~ s/\s+with\s+[^\s)]+/ /ig;

  # Tokenize and parse expression
  my $tree = eval { _parse(_tokenize($string)) };
  if (my $err = $@) {
    chomp $err;
    $self->error($err);
  }

  warn dumper $tree if DEBUG;
  return $self->normalized($before ne $string)->tree($tree);
}

sub to_string ($self) { _tree_to_string($self->{tree}) }

sub _example ($tree) {
  return _example($tree->{left}) if $tree->{op};
  return $tree->{license};
}

sub _match ($main, $sub) {
  return defined $main->{license} && $main->{license} eq $sub->{license} if defined $main->{license};
  return undef                                                           if $sub->{license};
  return undef                                                           if $main->{op} ne $sub->{op};

  return _match($main->{left}, $sub->{left}) || _match($main->{left}, $sub->{right});
}

sub _parse (@tokens) {

  # Or (low precedence)
  my $left;
  for my $i (0 .. $#tokens) {
    ($left = _parse(splice(@tokens, 0, $i))) and last if $tokens[$i] eq 'or';
  }

  # Left
  unless (defined $left) {
    $left = shift @tokens;
    $left = $left =~ /^\(/ ? _parse(_tokenize($left)) : {license => _spdx($left)};
    return $left unless @tokens;
  }

  # Op
  my $op = shift @tokens;
  return $left unless @tokens;

  # Right
  my $right = _parse(@tokens);
  return {right => $right, op => $op, left => $left};
}

sub _single ($main, $sub) {
  return _single($main->{left}, $sub) || _single($main->{right}, $sub) if $main->{op} && $main->{op} eq 'and';
  return _match($main, $sub);
}

sub _sorted_tree ($tree) {
  return $tree unless $tree->{op};

  my $lt = _sorted_tree($tree->{left});
  my $rt = _sorted_tree($tree->{right});
  if ((_tree_to_string($lt) cmp _tree_to_string($rt)) > 0) {
    $tree->{left}  = $rt;
    $tree->{right} = $lt;
  }
  else {
    $tree->{right} = $rt;
    $tree->{left}  = $lt;
  }

  return $tree;
}

sub _spdx ($name) { $ALLOWED{$name} || $name =~ /^LicenseRef-/ ? $name : die "Invalid SPDX license: $name\n" }

sub _tokenize ($string) {

  # Ignore outer parentheses
  $string =~ s/^\s*\((.*)\)\s*$/$1/ if ((extract_bracketed($string, '()'))[0] // '') eq $string;

  # Macro
  die "Invalid license expression: $string\n" if index($string, '%') >= 0;

  my @tokens;
  while (length $string) {

    # Compound expression
    if ($string =~ /^\s*\(/) {
      (my $token, $string) = extract_bracketed trim($string), '()';
      die "Invalid license expression: $string\n" unless defined $token;
      push @tokens, $token if defined $token;
    }

    # Operator
    elsif ($string =~ s/^\s+(and|or)//i) { push @tokens, lc $1 }

    # Simple expression
    elsif ($string =~ s/^\s*((?:(?!\s+and|\s+or).)+)//i) {
      push @tokens, trim $1;
    }

    # This should not happen
    else { die "Invalid license expression: $string\n" }
  }

  return @tokens;
}

sub _tree_to_string ($tree) {
  if ($tree->{op}) {
    my $ls = _tree_to_string($tree->{left});
    $ls = _wrap_mixed($tree->{left}, $tree->{op}, $ls);
    my $rs = _tree_to_string($tree->{right});
    $rs = _wrap_mixed($tree->{right}, $tree->{op}, $rs);
    return sprintf("$ls %s $rs", $tree->{op});
  }

  return $tree->{license};
}

sub _walk ($main, $sub) {
  return _walk($main, $sub->{left}) && _walk($main, $sub->{right}) if $sub->{op} && $sub->{op} eq 'and';
  return _single($main, $sub);
}

sub _wrap_mixed ($tree, $op, $str) {
  return $tree->{op} && $tree->{op} ne $op ? "($str)" : $str;
}

1;
