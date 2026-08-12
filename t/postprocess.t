# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Mojo::Base -strict, -signatures;

use Test::More;
use Mojo::File qw(path tempdir);
use Mojo::Util qw(encode);
use Cavil::Checkout;
use Cavil::PostProcess;

# Diagnostics may contain decoded UTF-8; keep the TAP handles from warning.
binmode Test::More->builder->$_, ':encoding(UTF-8)' for qw(output failure_output todo_output);

my $dir = path(__FILE__)->dirname->child('legal-bot');

sub temp_copy {
  my $from   = $dir->child(@_);
  my $target = tempdir;
  $_->copy_to($target->child($_->basename)) for $from->list->each;
  return $target;
}

# Run the real post-processor over a directory holding one file, and return the processor, the
# name of the variant it produced, and the lines of that variant. Every original_lines case below
# is checked against a file post-processing actually wrote, so a map that agrees with the code but
# not with the output on disk cannot pass.
sub post_process ($content, $name = 'file.js', $mime = 'text/plain') {
  my $tmp = tempdir;
  $tmp->child($name)->spew($content);
  my $processor = Cavil::PostProcess->new({destdir => $tmp, unpacked => {$name => {mime => $mime}}});
  $processor->postprocess;
  my ($produced) = keys %{$processor->hash->{unpacked}};
  return ($processor, $tmp->child($name)->to_string, [split /\n/, $tmp->child($produced)->slurp]);
}

# The full map for a file, as {processed line => original line}
sub line_map ($processor, $original, $processed) {
  return $processor->original_lines($original, [1 .. scalar @$processed]);
}

subtest 'gnome-icon-theme' => sub {
  my $pwll      = temp_copy('package-with-long-lines', '677dca225770d164778fd08123af89e960b8bd0d');
  my $processor = Cavil::PostProcess->new({destdir => $pwll, unpacked => {'README.md' => {mime => 'text/plain'}}});
  $processor->postprocess;
  is_deeply $processor->hash, {destdir => $pwll, unpacked => {'README.processed.md' => {mime => 'text/plain'}}},
    'maxed';

  is $pwll->child('README.processed.md')->slurp, $pwll->child('README.shortened')->slurp, 'Correctly split';

  my $pwt = temp_copy('package-with-translations', '96d268b759eb1e18a63a95a2c622ab47d5c34f23');
  $processor = Cavil::PostProcess->new(
    {destdir => $pwt, unpacked => {'test.po' => {mime => 'text/x-po'}, 'package.spec' => {mime => 'text/plain'}}});
  $processor->postprocess;
  is_deeply $processor->hash,
    {
    destdir  => $pwt,
    unpacked => {'test.processed.po' => {mime => 'text/x-po'}, 'package.processed.spec' => {mime => 'text/plain'},}
    },
    'striped';

  is $pwt->child('test.processed.po')->slurp, $pwt->child('test.stripped')->slurp, 'Correctly stripped msgid';
  is $pwt->child('package.processed.spec')->slurp, $pwt->child('package.stripped')->slurp,
    'Correctly stripped spec file';
};

subtest 'Markup files are stripped to text and wrapped' => sub {
  my $tmp = tempdir;

  # A long paragraph forces the stripped output to be line-wrapped like any other file.
  my $long = join ' ', ('protected by copyright and distributed under licenses restricting its use') x 4;
  $tmp->child('content.xml')
    ->spew(qq{<text:p text:style-name="P8">U.S.A. All rights reserved.</text:p><text:p>$long</text:p>});

  my $processor = Cavil::PostProcess->new({destdir => $tmp, unpacked => {'content.xml' => {mime => 'text/xml'}}});
  $processor->postprocess;

  is_deeply $processor->hash, {destdir => $tmp, unpacked => {'content.processed.xml' => {mime => 'text/xml'}}},
    'original entry replaced by the stripped .processed variant';

  my $out = $tmp->child('content.processed.xml')->slurp;
  like $out,   qr/U\.S\.A\. All rights reserved\./, 'license text preserved';
  unlike $out, qr/text:p|style-name|P8|[<>]/,       'no markup tokens leak into the output';

  my @lines = split /\n/, $out;
  ok @lines >= 3, 'long paragraph was wrapped across multiple lines';
};

subtest 'Filenames without alphanumeric extensions do not gain .processed._' => sub {
  my $tmp = tempdir;
  $tmp->child('config.guess._')->spew(join(' ', ('xxxxx') x 30) . "\n");

  my $processor = Cavil::PostProcess->new({destdir => $tmp, unpacked => {'config.guess._' => {mime => 'text/plain'}}});
  $processor->postprocess;

  my @produced = sort keys %{$processor->hash->{unpacked}};
  ok !(grep {/\.processed\._$/} @produced), 'no phantom .processed._ entry'
    or diag 'unpacked entries: ' . join(', ', @produced);
};

subtest 'original_lines: plain line wrapping' => sub {
  subtest 'a file nothing happens to maps to itself' => sub {
    my ($pp, $orig, $out) = post_process("one\ntwo\nthree\n");
    is_deeply line_map($pp, $orig, $out), {1 => 1, 2 => 2, 3 => 3}, 'identity';
  };

  subtest 'a wrapped line shifts everything after it' => sub {
    my ($pp, $orig, $out) = post_process("line1\n" . ('a' x 200) . ' ' . ('b' x 50) . "\nafter\n");
    is scalar @$out, 4, 'the long line became two';
    is_deeply line_map($pp, $orig, $out), {1 => 1, 2 => 2, 3 => 2, 4 => 3},
      'both halves point back at the line they came from, and "after" is un-shifted';
  };

  subtest 'a long line with no split point is left intact' => sub {
    my ($pp, $orig, $out) = post_process("line1\n" . ('a' x 200) . "\nafter\n");
    is_deeply line_map($pp, $orig, $out), {1 => 1, 2 => 2, 3 => 3}, 'no [ ;{}"] after column 115, so no shift';
  };

  subtest 'boundary at max_line_length' => sub {
    my ($pp, $orig, $out) = post_process("line1\n" . ('a' x 115) . "\nafter\n");
    is_deeply line_map($pp, $orig, $out), {1 => 1, 2 => 2, 3 => 3}, 'a line of exactly 115 is never split';

    # The split character sits at the boundary and nothing follows it, so the "keep the character
    # on this chunk" rule consumes the whole line - one chunk, even though the file was rewritten
    ($pp, $orig, $out) = post_process("line1\n" . ('a' x 115) . " \nafter\n");
    is scalar @$out, 3, 'rewritten but not actually split';
    is_deeply line_map($pp, $orig, $out), {1 => 1, 2 => 2, 3 => 3}, 'trailing space at the boundary, no shift';

    # A quote breaks *before* itself, so the same position does split here
    ($pp, $orig, $out) = post_process("line1\n" . ('a' x 115) . '"' . ('b' x 10) . "\nafter\n");
    is_deeply line_map($pp, $orig, $out), {1 => 1, 2 => 2, 3 => 2, 4 => 3},
      'a quote at the boundary splits where a space did not';
  };

  subtest 'shifts accumulate over several long lines' => sub {
    my ($pp, $orig, $out) = post_process(('a' x 200) . " x\n" . ('b' x 200) . " y\nafter\n");
    is_deeply line_map($pp, $orig, $out), {1 => 1, 2 => 1, 3 => 2, 4 => 2, 5 => 3}, 'two lines became four';
  };

  subtest 'empty lines still count as one line each' => sub {
    my ($pp, $orig, $out) = post_process("\n\n" . ('a' x 200) . " x\nafter\n");
    is_deeply line_map($pp, $orig, $out), {1 => 1, 2 => 2, 3 => 3, 4 => 3, 5 => 4}, 'blank lines are not swallowed';
  };

  subtest 'a last line without a trailing newline' => sub {
    my ($pp, $orig, $out) = post_process("line1\n" . ('a' x 200) . ' ' . ('b' x 50));
    is_deeply line_map($pp, $orig, $out), {1 => 1, 2 => 2, 3 => 2}, 'still mapped';
  };

  # The plain wrapper reads the source without an encoding layer, so it decides on bytes: 80 x "e
  # acute" is 160 bytes but only 80 characters. A character-based translator would report no split
  # here and mis-map every following line
  subtest 'wrapping is decided on bytes, not characters' => sub {
    my ($pp, $orig, $out) = post_process("line1\n" . encode('UTF-8', "\x{e9}" x 80) . " tail\nafter\n");
    is scalar @$out, 4, 'split even though the line is only 85 characters wide';
    is_deeply line_map($pp, $orig, $out), {1 => 1, 2 => 2, 3 => 2, 4 => 3}, 'byte semantics';
  };
};

subtest 'original_lines: markup stripping' => sub {
  subtest 'text collapsed from several source lines maps to where the text starts' => sub {
    my ($pp, $orig, $out)
      = post_process("<html>\n<body>\n<p>\n  Licensed under\n  the MIT license\n</p>\n<p>tail</p>\n</body>\n</html>\n",
      'page.html', 'text/html');
    is_deeply $out, ['Licensed under the MIT license ', 'tail'], 'markup gone, prose kept';

    # Line 3 is "<p>" - the run reported by the parser opens with the newline after it, but the
    # text itself is on line 4
    is_deeply line_map($pp, $orig, $out), {1 => 4, 2 => 7}, 'the paragraph maps to its first line of prose';
  };

  subtest 'a license in a comment maps to the comment' => sub {
    my ($pp, $orig, $out) = post_process(
      "<html>\n<head>\n<title>t</title>\n</head>\n<body>\n<!-- SPDX-License-Identifier: MIT -->\n"
        . "<p>tail</p>\n</body>\n</html>\n",
      'page.html', 'text/html'
    );
    like $out->[1], qr/SPDX-License-Identifier: MIT/, 'the declaration survived stripping';
    is_deeply line_map($pp, $orig, $out), {1 => 3, 2 => 6, 3 => 7}, 'and points at line 6, where the comment is';
  };

  subtest 'script and style bodies emit nothing but do not shift what follows' => sub {
    my ($pp, $orig, $out)
      = post_process(
      "<html>\n<style>\n.a{color:red}\n</style>\n<script>\nvar l = \"GPL\";\n</script>\n" . "<p>after</p>\n</html>\n",
      'page.html', 'text/html');
    is_deeply $out, ['after'], 'only the prose survives';
    is_deeply line_map($pp, $orig, $out), {1 => 8}, 'mapped past six dropped lines';
  };

  subtest 'a stripped line long enough to wrap maps every piece to one source line' => sub {
    my $long = join ' ', ('protected by copyright and distributed under licenses') x 4;
    my ($pp, $orig, $out) = post_process("<html>\n<p>$long</p>\n<p>tail</p>\n</html>\n", 'page.html', 'text/html');
    is scalar @$out, 3, 'the paragraph wrapped into two lines';
    is_deeply line_map($pp, $orig, $out), {1 => 2, 2 => 2, 3 => 3}, 'both pieces come from line 2';
  };

  # The mirror of the byte-semantics case above: the stripper hands PostProcess character strings,
  # so the same 80 x "e acute" is 85 characters here and must *not* split
  subtest 'stripped text wraps on characters, not bytes' => sub {
    my ($pp, $orig, $out)
      = post_process("<html>\n<p>" . encode('UTF-8', "\x{e9}" x 80) . " tail</p>\n<p>next</p>\n</html>\n",
      'page.html', 'text/html');
    is scalar @$out, 2, 'not split';
    is_deeply line_map($pp, $orig, $out), {1 => 2, 2 => 3}, 'character semantics';
  };

  subtest 'only the wanted lines are resolved' => sub {
    my $tmp = tempdir;
    $tmp->child('big.html')->spew(join '', map {"<p>line $_</p>\n"} 1 .. 5000);
    my $pp = Cavil::PostProcess->new;
    is_deeply $pp->original_lines($tmp->child('big.html')->to_string, [3, 2]), {2 => 2, 3 => 3},
      'stopping at the highest wanted line still answers the lower ones';
  };

  # HTML::Parser recovers from everything we could throw at it, so there is no input that makes
  # strip_markup die mid-parse; the reachable failure is the open, and the fallback wiring is
  # checked by forcing the replay to report one
  subtest 'a parser failure falls back to the plain wrapper' => sub {
    my $tmp = tempdir;
    my $pp  = Cavil::PostProcess->new;
    ok !Cavil::PostProcess::_replay_markup($tmp->child('gone.html')->to_string, sub {0}),
      'unreadable input reports failure';

    $tmp->child('page.html')->spew("<html>\n<body>\n<p>hi</p>\n</body>\n</html>\n");
    no warnings 'redefine';
    local *Cavil::PostProcess::_replay_markup = sub {0};
    is_deeply $pp->original_lines($tmp->child('page.html')->to_string, [1, 3]), {1 => 1, 3 => 3},
      'falls through to the wrap replay, which counts the raw markup lines';
  };
};

# The mapping is derived by replaying post-processing rather than recorded while it runs, so the
# thing that could rot is the two drifting apart. These check the agreement itself rather than
# hand-computed line numbers: whatever the wrapper and the stripper do to a file, the map has to
# have exactly one answer per line they actually wrote, and each of those lines has to be found
# where the map says it came from. A change to post-processing that original_lines does not follow
# fails here without anyone having to remember this file exists.
# .po and .spec files are cut short at their ignore_re line, and original_lines does not replay
# that. The reason it does not have to is worth pinning: truncation only ever removes lines from
# the end, so every line that survives keeps its number - and these two fixtures carry their
# copyright headers in the surviving part, which is exactly what SPDX reports on
subtest 'original_lines: files post-processing truncates' => sub {
  my $pwt = temp_copy('package-with-translations', '96d268b759eb1e18a63a95a2c622ab47d5c34f23');
  my $pp  = Cavil::PostProcess->new(
    {destdir => $pwt, unpacked => {'test.po' => {mime => 'text/x-po'}, 'package.spec' => {mime => 'text/plain'}}});
  $pp->postprocess;

  for my $file (['test.po', 'test.processed.po'], ['package.spec', 'package.processed.spec']) {
    my ($original, $processed) = @$file;
    my @out = split /\n/, $pwt->child($processed)->slurp;
    my @src = split /\n/, $pwt->child($original)->slurp;
    ok @out < @src, "$original was truncated";

    my $map = $pp->original_lines($pwt->child($original)->to_string, [1 .. scalar @out]);
    is_deeply $map, {map { $_ => $_ } 1 .. scalar @out}, "$original: the surviving lines keep their numbers";
    is scalar(grep { $src[$map->{$_} - 1] ne $out[$_ - 1] } keys %$map), 0, "$original: and hold the same text";
  }
};

subtest 'original_lines agrees with what post-processing wrote' => sub {
  my $wrappy = ('b' x 130) . ';' . ('c' x 130) . " end\n";
  my $prose  = join ' ', ('licensed under the terms') x 8;
  my %cases  = (
    'plain text'          => ["short\nplain\n",                                           'f.js',   'text/plain'],
    'one wrap'            => ["short\n" . ('a' x 200) . " tail\nafter\n",                 'f.js',   'text/plain'],
    'repeated wraps'      => [$wrappy x 3,                                                'f.js',   'text/plain'],
    'no split point'      => [('d' x 400) . "\nafter\n",                                  'f.js',   'text/plain'],
    'blank lines'         => ["\n\n" . ('e' x 200) . " x\n\nlast\n",                      'f.js',   'text/plain'],
    'no trailing newline' => ["short\n" . ('f' x 200) . ' tail',                          'f.js',   'text/plain'],
    'utf-8 bytes'         => ["short\n" . encode('UTF-8', "\x{e9}" x 80) . " tail\n",     'f.js',   'text/plain'],
    'markup'              => ["<html>\n<p>\n  hi\n  there\n</p>\n<p>tail</p>\n</html>\n", 'p.html', 'text/html'],
    'markup that wraps'   => ["<html>\n<p>$prose</p>\n<p>tail</p>\n</html>\n",            'p.html', 'text/html'],
  );

  for my $name (sort keys %cases) {
    my ($pp, $orig, $out) = post_process(@{$cases{$name}});
    my $map = line_map($pp, $orig, $out);

    is scalar keys %$map, scalar @$out, "$name: one answer per line post-processing wrote";

    # The plain path copies bytes straight through, so every processed line is literally a piece of
    # the line it maps back to. The markup path rewrites its text (entities decoded, whitespace
    # collapsed), so there the check is that the source line is real and non-empty
    my @src  = split /\n/, path($orig)->slurp;
    my $html = $cases{$name}[2] eq 'text/html';
    my $bad  = grep {
      my $from = $src[$map->{$_} - 1];
      !defined $from || ($html ? $from !~ /\S/ : index($from, $out->[$_ - 1]) < 0)
    } keys %$map;
    is $bad, 0, "$name: every line maps back to the line it came from";
  }
};

subtest 'original_lines: markup post-processing could not strip' => sub {

  # A stripped run over the writer's 60000 character limit makes _process_markup_file give up, and
  # the plain line-wrapper writes the file instead, tags and all. The replay has to give up in the
  # same place: while the limit sat in the writer alone, the replay stripped the file quite happily
  # and mapped every one of its lines back to the single source line that one huge run began on
  my $long = join "\n", map { join ' ', ('licensedundertheterms') x 8 } 1 .. 400;
  my ($pp, $orig, $out) = post_process("<html><body>\n<p>\n$long\n</p>\n</body></html>\n", 'b.html', 'text/html');

  ok length($long =~ s/\s+/ /gr) > 60000, 'the stripped run is over the limit';
  is $out->[-1], '</body></html>', 'the plain wrapper wrote the file, tags and all';

  my $map = line_map($pp, $orig, $out);
  is scalar keys %$map, scalar @$out, 'one answer per line post-processing wrote';

  my @src = split /\n/, path($orig)->slurp;
  my $bad = grep { index($src[$map->{$_} - 1] // '', $out->[$_ - 1]) < 0 } keys %$map;
  is $bad, 0, 'every line maps back to the line it came from';
};

subtest 'a line that is not over-long is exactly one line' => sub {
  my $pp  = Cavil::PostProcess->new;
  my $max = $pp->max_line_length;

  # Both writers print such a line directly instead of asking the splitter, and original_lines
  # counts it as one without asking either - that shortcut is what keeps a multi-million-line file
  # affordable to replay. Were _split_offsets to ever break one of these into two, the writers and
  # the mapper would still agree with each other while both silently disagreed with this, so it is
  # pinned on its own rather than left to the comparison test above
  for my $len (0, 1, $max - 1, $max) {
    my ($plain) = $pp->_split_offsets('x' x $len);
    is scalar @$plain, 1, "length $len is one line";

    # Split characters present, including the '"' that breaks before itself
    my ($mixed) = $pp->_split_offsets(substr('ab cd;ef{gh}ij"kl' x 20, 0, $len));
    is scalar @$mixed, 1, "length $len with split characters is one line";
  }
};

subtest 'original_lines: nothing to map' => sub {
  my $tmp = tempdir;
  $tmp->child('a.js')->spew("one\ntwo\n");
  my $pp = Cavil::PostProcess->new;

  is_deeply $pp->original_lines($tmp->child('a.js')->to_string,    []),    {}, 'no wanted lines';
  is_deeply $pp->original_lines($tmp->child('a.js')->to_string,    undef), {}, 'no wanted lines at all';
  is_deeply $pp->original_lines($tmp->child('gone.js')->to_string, [1]),   {}, 'the original is gone';
  is_deeply $pp->original_lines($tmp->child('a.js')->to_string,    [999]), {}, 'past the end of the file';
};

done_testing;
