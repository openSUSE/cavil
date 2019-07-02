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

package Cavil::Util;
use Mojo::Base -strict;

use Carp 'croak';
use Exporter 'import';
use Mojo::Util 'decode';
use POSIX 'ceil';

our @EXPORT_OK = qw(buckets slurp_and_decode);

my $MAX_FILE_SIZE = 30000;

sub buckets {
  my ($things, $size) = @_;

  my $buckets    = int(@$things / $size) || 1;
  my $per_bucket = ceil @$things / $buckets;
  my @buckets;
  for my $thing (@$things) {
    push @buckets, [] unless @buckets;
    push @buckets, [] if @{$buckets[-1]} >= $per_bucket;
    push @{$buckets[-1]}, $thing;
  }

  return \@buckets;
}

sub slurp_and_decode {
  my $path = shift;

  open my $file, '<', $path or croak qq{Can't open file "$path": $!};
  croak qq{Can't read from file "$path": $!}
    unless defined(my $ret = $file->sysread(my $content, $MAX_FILE_SIZE, 0));

  return $content if -s $path > $MAX_FILE_SIZE;
  return decode('UTF-8', $content) // $content;
}

1;
