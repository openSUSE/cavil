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

has 'hash';
has max_line_length => 115;

sub _split_find_a_good_spot ($self, $line, $start, $len, $max_line_length) {
  my $length = $len - $start;
  my $index  = $max_line_length;
  return $length if ($index > $length);
  my %splits = (' ' => 1, ';' => 1, '{' => 1, '}' => 1, '"' => 0);

  while ($index < $length) {
    my $char = substr($line, $start + $index, 1);
    return $index + $splits{$char} if (exists $splits{$char});
    $index++;
  }
  return 0;
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
  if ($from =~ m,^(.*)\.([^./]+$),) {
    $to = "$1.processed.$2";
  }
  else {
    $to = "$from.processed";
  }

  my $destdir = $self->hash->{destdir};
  my $ignore_re;

  # mimetype text/x-po only hits most, but it might be good enough
  if ($mimetype && $mimetype =~ m,text/x-po,) {
    $ignore_re = qr(^msgid ");
  }

  # spec files are mostly text/plain
  if ($from =~ m,.spec$,) {
    $ignore_re = qr(^Name *:);
  }
  open(my $f_in,  '<', "$destdir/$from") || die "Can't open $from";
  open(my $f_out, '>', "$destdir/$to")   || die "Can't open $to";

  my $changed = 0;
  while (<$f_in>) {
    my $line = $_;
    if ($ignore_re && $line =~ /$ignore_re/) {
      $changed = 1;
      last;
    }

    if (length($line) > $self->max_line_length) {
      chomp $line;
      $changed = $self->_split_line_by_whitespace($f_out, $line) || $changed;
    }
    else {
      print $f_out $line;
    }
  }

  close($f_in);
  close($f_out);

  if (!$changed) {
    unlink($to);
    return undef;
  }
  return $to;
}

sub new ($class, $hash) { $class->SUPER::new(hash => $hash) }

sub postprocess ($self) {
  my $unpacked = $self->hash->{unpacked};
  for my $file (keys %$unpacked) {
    my $entry = $unpacked->{$file};

    # clean up after file::unpack
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
