# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package Cavil::PatternEngine;
use Mojo::Base -strict, -signatures;

use Carp 'croak';

# Every line Cavil reads for text extraction - snippets, report previews, the file and snippet views - is
# truncated to this many bytes in read_lines below. A longer line is minified machine content (a bundled
# .js/.css/.map with the whole file on one line), never a license declaration, and left whole it would put
# multi-hundred-KB "lines" into snippets and reports. Capping at this single chokepoint means no consumer
# has to defend against it; the matcher reads files separately, so matching is unaffected.
use constant MAX_LINE_SIZE => 8000;

# Cavil can run its pattern matching on either the original C++ engine or its drop-in successor. Both
# expose the same package functions and the same object method names, and (crucially) produce identical
# token hashes and content checksums, so the engine can be switched with the "matcher" config value
# without any database migration. Only the seven package-level functions need routing here; method
# calls on the returned Matcher/Hash/Bag objects work unchanged because each object carries its class.

my %ENGINES = (spooky => 'Spooky::Patterns::XS', cavil => 'Cavil::Matcher');

# The original engine is always present (a hard dependency); the successor is loaded on demand.
require Spooky::Patterns::XS;
my $NAME   = 'spooky';
my $ENGINE = $ENGINES{spooky};

# Select the active engine, loading it if necessary. Called once at application startup from the
# "matcher" config value. Dies with a clear message if an unknown engine is requested, or if the
# successor is selected but not installed.
sub use_engine ($name) {
  $name //= 'spooky';
  my $pkg = $ENGINES{$name} or croak qq{Unknown pattern engine "$name" (use "spooky" or "cavil")};
  unless (eval "require $pkg; 1") {
    croak qq{Pattern engine "$name" ($pkg) is not available: $@};
  }
  $NAME   = $name;
  $ENGINE = $pkg;
  return $ENGINE;
}

sub name ()   {$NAME}
sub engine () {$ENGINE}

# Thin dispatchers to the active engine's package functions.
sub init_matcher         { $ENGINE->can('init_matcher')->(@_) }
sub init_hash            { $ENGINE->can('init_hash')->(@_) }
sub init_bag_of_patterns { $ENGINE->can('init_bag_of_patterns')->(@_) }
sub parse_tokens         { $ENGINE->can('parse_tokens')->(@_) }

sub read_lines {
  my $rows = $ENGINE->can('read_lines')->(@_);

  # Bound each line to MAX_LINE_SIZE; read_lines returns one row per physical line ([lineno, pid, text]),
  # so this truncates a runaway line while keeping the engine's real line numbers intact.
  for my $row (@$rows) {
    $row->[2] = substr $row->[2], 0, MAX_LINE_SIZE if length $row->[2] > MAX_LINE_SIZE;
  }

  return $rows;
}
sub normalize { $ENGINE->can('normalize')->(@_) }
sub distance  { $ENGINE->can('distance')->(@_) }

1;
