# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package Cavil::PatternEngine;
use Mojo::Base -strict, -signatures;

use Carp 'croak';

# Bound generated one-line content here; the matcher reads files separately.
use constant MAX_LINE_SIZE => 8000;

# Engines share token hashes and checksums, so switching requires no migration.

my %ENGINES = (cavil => 'Cavil::Matcher', spooky => 'Spooky::Patterns::XS');

# The default engine is always present (a hard dependency); the alternative is loaded on demand.
require Cavil::Matcher;
my $NAME   = 'cavil';
my $ENGINE = $ENGINES{cavil};

sub use_engine ($name) {
  $name //= 'cavil';
  my $pkg = $ENGINES{$name} or croak qq{Unknown pattern engine "$name" (use "cavil" or "spooky")};
  unless (eval "require $pkg; 1") {
    croak qq{Pattern engine "$name" ($pkg) is not available: $@};
  }
  $NAME   = $name;
  $ENGINE = $pkg;
  return $ENGINE;
}

sub name ()   {$NAME}
sub engine () {$ENGINE}

sub init_matcher         { $ENGINE->can('init_matcher')->(@_) }
sub init_hash            { $ENGINE->can('init_hash')->(@_) }
sub init_bag_of_patterns { $ENGINE->can('init_bag_of_patterns')->(@_) }
sub parse_tokens         { $ENGINE->can('parse_tokens')->(@_) }

sub read_lines {
  my $rows = $ENGINE->can('read_lines')->(@_);

  # Preserve physical line numbers while truncating content.
  for my $row (@$rows) {
    $row->[2] = substr $row->[2], 0, MAX_LINE_SIZE if length $row->[2] > MAX_LINE_SIZE;
  }

  return $rows;
}
sub normalize { $ENGINE->can('normalize')->(@_) }
sub distance  { $ENGINE->can('distance')->(@_) }

1;
