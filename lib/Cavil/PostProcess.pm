# Copyright (C) 2019 SUSE Linux GmbH
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

package Cavil::PostProcess;
use Mojo::Base -base, -signatures;

use List::Util                 qw(max);
use Mojo::File                 qw(path);
use Cavil::PostProcess::Markup qw(looks_like_markup strip_markup);

has 'hash';
has max_line_length => 115;

# Find the offset (relative to $start) at which to break an over-long line: the first
# split character (space/;/{/} keep the char on the current chunk, " breaks before it)
# at or after $max_line_length, or 0 when none exists. A single regex scan replaces the
# former character-by-character substr walk; behaviour is identical.
sub _split_find_a_good_spot ($self, $line, $start, $len, $max_line_length) {
  my $length = $len - $start;
  return $length if ($max_line_length > $length);

  my $rest = substr($line, $start + $max_line_length, $length - $max_line_length);
  return 0 unless $rest =~ /([ ;{}"])/;
  return $max_line_length + $-[0] + ($1 eq '"' ? 0 : 1);
}

# The lines a line becomes, as [offset, length] pairs into it, plus the "changed" flag the writer
# reports. Both the writer below and the line-number mapper (original_lines) drive this one
# function, so the number of lines written can never disagree with the number the mapper counts -
# the mapper's correctness rests on that. Every line becomes at least one line: a short one is a
# single chunk covering all of it, an empty one a single empty chunk.
sub _split_offsets ($self, $line) {
  my $max = $self->max_line_length;
  my $len = length($line);

  # files with 60K lines are most likley not to be read by humans. The guard belongs here rather
  # than in the writer so that the replay walks into the same wall: a markup file with a stripped
  # run this long makes _process_markup_file give up and the plain wrapper handle the file, and
  # _replay_markup has to give up in the same place or it maps against a transformation that never
  # happened
  die "too long" if $len > 60000;

  my ($start, $changed, @chunks) = (0, undef);
  while ($start < $len) {
    my $index = $self->_split_find_a_good_spot($line, $start, $len, $max);
    if (!$index) {
      push @chunks, [$start, $len - $start];
      last;
    }

    push @chunks, [$start, $index];
    $start += $index;
    $changed = 1;
  }

  return (@chunks ? \@chunks : [[0, 0]], $changed);
}

sub _split_line_by_whitespace ($self, $fh, $line) {
  my ($chunks, $changed) = $self->_split_offsets($line);
  print $fh substr($line, $_->[0], $_->[1]), "\n" for @$chunks;

  return $changed;
}

sub _process_file ($self, $from, $mimetype) {

  # avoid doing it again
  return undef if $from =~ m/.processed/;
  my $to;
  if ($from =~ m,^(.*)\.([A-Za-z0-9][^./]*$),) {
    $to = "$1.processed.$2";
  }
  else {
    $to = "$from.processed";
  }

  my $destdir     = $self->hash->{destdir};
  my $source      = "$destdir/$from";
  my $destination = path($destdir, $to)->to_string;

  # Markup files (HTML/XML, incl. unpacked ODF/OOXML component XML) are stripped to
  # plain text - otherwise reviewers and the matcher only ever see tag soup. The
  # stripped text is line-wrapped just like any other processed file. On any parser
  # error we fall back to the plain line-wrapper below, so a file is never dropped.
  if (_is_markup($source)) {
    return $to if $self->_process_markup_file($source, $destination);
  }

  my $ignore_re;

  # mimetype text/x-po only hits most, but it might be good enough
  if ($mimetype && $mimetype =~ m,text/x-po,) {
    $ignore_re = qr(^msgid ");
  }

  # spec files are mostly text/plain
  if ($from =~ m,.spec$,) {
    $ignore_re = qr(^Name *:);
  }

  # Only rewrite the file when a line actually needs splitting (or an ignore_re cut
  # applies). The common short-lined file then costs a single read and no write -
  # previously every text file was fully written and then unlinked again.
  return undef unless $self->_needs_processing($source, $ignore_re);

  open(my $f_in,  '<', $source)      || die "Can't open $from";
  open(my $f_out, '>', $destination) || die "Can't open $to";

  while (<$f_in>) {
    my $line = $_;
    last if $ignore_re && $line =~ /$ignore_re/;

    if (length($line) > $self->max_line_length) {
      chomp $line;
      $self->_split_line_by_whitespace($f_out, $line);
    }
    else {
      print $f_out $line;
    }
  }

  close($f_in);
  close($f_out);

  return $to;
}

# Does this file go through the markup stripper instead of the plain line-wrapper? Asked once when
# the file is processed and again when original_lines replays that processing, so the two cannot
# disagree about which transformation a file was put through.
sub _is_markup ($source) { return looks_like_markup($source, _read_head($source)) }

# First chunk of a file, for the markup content sniff. Returns '' if unreadable.
sub _read_head ($source, $bytes = 4096) {
  open(my $fh, '<', $source) or return '';
  my $head = '';
  read($fh, $head, $bytes);
  close($fh);
  return $head;
}

# Does the file actually need rewriting? True when an ignore_re line is present, or a
# line is long enough to have a split point at/after max_line_length. Mirrors the exact
# conditions under which the rewrite loop produces different content, so skipping is
# byte-for-byte equivalent to the old "write, then unlink if unchanged" behaviour.
sub _needs_processing ($self, $source, $ignore_re) {
  my $max = $self->max_line_length;
  open(my $fh, '<', $source) || die "Can't open $source";
  while (my $line = <$fh>) {
    if ($ignore_re && $line =~ /$ignore_re/) { close($fh); return 1 }
    if (length($line) > $max) {
      chomp(my $chomped = $line);
      if (substr($chomped, $max) =~ /[ ;{}"]/) { close($fh); return 1 }
    }
  }
  close($fh);
  return 0;
}

# Strip markup from $source into $destination, wrapping each stripped line to
# max_line_length via the shared line-splitter. Returns 1 on success, 0 (removing any
# partial file) on parser failure so the caller can fall back to plain processing.
sub _process_markup_file ($self, $source, $destination) {
  my $max = $self->max_line_length;
  my $ok  = eval {
    open(my $f_out, '>:encoding(UTF-8)', $destination) || die "Can't open $destination";
    strip_markup(
      $source,
      sub ($line, $lineno) {
        if (length($line) > $max) { $self->_split_line_by_whitespace($f_out, $line) }
        else                      { print $f_out "$line\n" }
      }
    );
    close($f_out);
    1;
  };
  unless ($ok) {
    unlink($destination);
    return 0;
  }
  return 1;
}

# Translate line numbers in the ".processed" copy of a file back into line numbers in the
# original. The indexer only ever scans the processed copy, so every sline/eline in the database
# is a position in that copy - but Cavil::SPDX reports the file under its original name, and
# post-processing moves lines around (long lines are wrapped, markup is stripped to its text).
#
# Post-processing only ever expands a file and is deterministic, so the mapping is replayed from
# the original here instead of being stored anywhere: the same code that decides where a line
# breaks decides where it came from, which is the only way the two cannot drift apart.
#
# $wanted is an arrayref of line numbers in the processed copy; the returned hashref holds just
# those as {processed line => original line}, so the cost does not scale with the size of the
# file. Reading stops as soon as the highest wanted line is resolved, which makes a license near
# the top of a huge generated file almost free. Lines that cannot be resolved (past the end of
# the file, unreadable original) are simply absent, so the caller can report no range rather than
# a wrong one.
sub original_lines ($self, $original, $wanted) {
  return {} unless $wanted && @$wanted && -f $original;
  my %want = map { $_ => 1 } @$wanted;
  my $last = max @$wanted;

  # One counter, fed by both replays below: it takes an original line with its number, asks
  # _split_offsets how many lines that becomes, and notes the ones asked for. Because neither
  # replay does any counting of its own, the two cannot drift apart - they only differ in how they
  # read the file. It returns true once every wanted line has an answer, so reading can stop. A
  # fresh counter (and map) per attempt keeps a failed markup replay from polluting the retry.
  my $max     = $self->max_line_length;
  my $counter = sub {
    my (%map, $processed);
    return (
      \%map,
      sub ($line, $lineno) {

        # Short lines take the same shortcut both writers take: they print anything that is not
        # over-long directly, without consulting the splitter, because such a line is always a
        # single chunk. Worth ~7x on the replay, since almost every line of almost every file is
        # short. (The plain writer measures the line with its newline still attached, so one of
        # exactly max_line_length does reach the splitter there - and comes back as one chunk,
        # the same answer this branch gives.)
        if (length($line) <= $max) {
          $processed++;
          $map{$processed} = $lineno if $want{$processed};
          return $processed >= $last ? 1 : 0;
        }

        my ($chunks) = $self->_split_offsets($line);
        for (@$chunks) {
          $processed++;
          $map{$processed} = $lineno if $want{$processed};
          return 1                   if $processed >= $last;
        }
        return 0;
      }
    );
  };

  if (_is_markup($original)) {
    my ($map, $count) = $counter->();
    return $map if _replay_markup($original, $count);
  }

  my ($map, $count) = $counter->();
  _replay_wrapped($original, $count);
  return $map;
}

# Replay the plain line-wrapper of _process_file. The original is opened without an encoding layer
# on purpose: _process_file reads bytes, so both the decision to split a line and the spot it
# splits at are made on byte lengths, and reading this as UTF-8 would silently shift every mapping
# in a file with non-ASCII text before its first wrap. _process_file also truncates .po and .spec
# files at their ignore_re line, which is deliberately not replayed - truncation only drops trailing
# lines, so nothing before the cut moves and nothing after it can be asked about.
sub _replay_wrapped ($original, $count) {
  open(my $fh, '<', $original) || return;
  while (my $line = <$fh>) {
    chomp $line;
    last if $count->($line, $.);
  }
  close($fh);
}

# Replay the markup stripper of _process_markup_file. False when the parse fails or a stripped run
# is too long to write, which is exactly when post-processing fell back to the plain line-wrapper,
# so the caller replays that instead.
# Stripped lines are character strings and wrap on character length here, matching
# _process_markup_file - the asymmetry with the byte-based plain path above is deliberate on both
# sides. Dying is the only way to stop parse_file early, and there is no point stripping the rest
# of a huge document once every wanted line has an answer.
sub _replay_markup ($original, $count) {
  my $ok = eval {
    strip_markup($original, sub ($line, $lineno) { die "line map complete\n" if $count->($line, $lineno) });
    1;
  };
  return $ok || $@ eq "line map complete\n";
}

sub new ($class, $hash = {}) { $class->SUPER::new(hash => $hash) }

sub postprocess ($self) {
  my $unpacked = $self->hash->{unpacked};
  for my $file (keys %$unpacked) {
    my $entry = $unpacked->{$file};

    # clean up after file::unpack2
    if ($file eq '.unpacked.json' || exists $entry->{unpacked}) {
      delete $unpacked->{$file};
      next;
    }

    next unless $entry->{mime} =~ m,text/,;

    my $new_fname = eval { $self->_process_file($file, $entry->{mime}) };
    if ($@) {

      # if we can't open the file, we plainly erase it
      delete $unpacked->{$file};
      next;
    }
    next unless $new_fname;
    $unpacked->{$new_fname} = {mime => $entry->{mime}};
    delete $unpacked->{$file};
  }
}

1;
