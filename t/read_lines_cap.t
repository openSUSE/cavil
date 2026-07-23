# SPDX-FileCopyrightText: 2026 SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Mojo::Base -strict, -signatures;

use FindBin;
use lib "$FindBin::Bin/lib";

use Test::More;
use Mojo::File qw(tempfile);
use Cavil::PatternEngine;
use Cavil::Util qw(file_and_checksum);

# The original engine's fixed line buffer bounded every line to ~8 KB; Cavil::Matcher returns whole
# physical lines, so the app caps them centrally in Cavil::PatternEngine::read_lines. Only the cavil
# engine can produce an over-cap line (the original already truncates below the cap), so this is gated.
plan skip_all => 'Cavil::Matcher is not installed' unless eval { require Cavil::Matcher; 1 };

Cavil::PatternEngine::use_engine('cavil');
my $cap = Cavil::PatternEngine::MAX_LINE_SIZE;

# One physical line far larger than the cap, then a short line.
my $file = tempfile;
$file->spew(('x' x (5 * $cap)) . "\ncopyright notice\n");

subtest 'read_lines truncates a runaway line and leaves short lines alone' => sub {
  my $rows = Cavil::PatternEngine::read_lines("$file", {1 => 1, 2 => 1});
  is scalar(@$rows),        2,                  'one row per physical line';
  is length($rows->[0][2]), $cap,               'the runaway line is truncated to MAX_LINE_SIZE';
  is $rows->[1][2],         'copyright notice', 'the short line is untouched';
};

subtest 'file_and_checksum (snippet text) is bounded by the cap' => sub {
  my ($text, $hash) = file_and_checksum("$file", 1, 2);
  ok length($text) >= $cap,    'includes the (capped) first line';
  ok length($text) < 5 * $cap, 'but is bounded, not the multi-x raw line';
  ok $hash,                    'and still produces a checksum';
};

done_testing;
