# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package Cavil::PatternEngine;
use Mojo::Base -strict, -signatures;

# Bound generated one-line content here; the matcher reads files separately.
use constant MAX_LINE_SIZE => 8000;

require Cavil::Matcher;

sub init_matcher         { Cavil::Matcher::init_matcher(@_) }
sub init_hash            { Cavil::Matcher::init_hash(@_) }
sub init_bag_of_patterns { Cavil::Matcher::init_bag_of_patterns(@_) }
sub parse_tokens         { Cavil::Matcher::parse_tokens(@_) }
sub normalize            { Cavil::Matcher::normalize(@_) }
sub distance             { Cavil::Matcher::distance(@_) }

sub read_lines {
  my $rows = Cavil::Matcher::read_lines(@_);

  # Preserve physical line numbers while truncating content.
  for my $row (@$rows) {
    $row->[2] = substr $row->[2], 0, MAX_LINE_SIZE if length $row->[2] > MAX_LINE_SIZE;
  }

  return $rows;
}

1;
