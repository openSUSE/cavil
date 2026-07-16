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

sub _split_line_by_whitespace ($self, $fh, $line) {
  my $changed;
  my $start = 0;
  my $len   = length($line);

  # files with 60K lines are most likley not to be read by humans
  die "too long" if $len > 60000;
  while ($start < $len) {
    my $index = $self->_split_find_a_good_spot($line, $start, $len, $self->max_line_length);
    if (!$index) {
      print $fh substr($line, $start);
      print $fh "\n";
      last;
    }

    print $fh substr($line, $start, $index);
    print $fh "\n";
    $start += $index;
    $changed = 1;
  }
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
  if (looks_like_markup($from, _read_head($source))) {
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
      sub ($line) {
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

sub new ($class, $hash) { $class->SUPER::new(hash => $hash) }

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
