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

package Cavil::Text;
use Mojo::Base -strict;

use Spooky::Patterns::XS;

use Exporter 'import';

our @EXPORT_OK = qw(wordcount calculate_tfdifs closest_pattern);

sub wordcount {
  my $text = shift;

  # normalize returns [ line number, word, token ] - we only want the word
  my @wordlist = map { $_->[1] } @{Spooky::Patterns::XS::normalize($text)};
  my %wordcount;
  for my $word (@wordlist) {
    $wordcount{$word} += 1;
  }
  return \%wordcount;
}

sub calculate_tfdifs {
  my ($wordcounts, $word2index, $idfs) = @_;

  my $square_sum = 0;
  my @tfidfs_array;
  for my $word (keys %{$wordcounts}) {
    my $tfidf = $wordcounts->{$word} * $idfs->{$word};
    $square_sum += $tfidf * $tfidf;
    push(@tfidfs_array, [$word2index->{$word}, $tfidf]);
  }
  @tfidfs_array = sort { $a->[0] <=> $b->[0] } @tfidfs_array;

  return (sqrt($square_sum), [map { ($_->[0], $_->[1]) } @tfidfs_array]);
}

sub closest_pattern {
  my ($text, $id, $data) = @_;

  my ($sum, $array)
    = calculate_tfdifs(wordcount($text), $data->{words}, $data->{idfs});

  return _find_best_pattern(
    {square_sum => $sum, tfidfs_array => $array, id => $id},
    $data->{patterns});
}

sub _find_best_pattern {
  my ($template, $infos) = @_;

  my $best = -1;
  my $best_pattern;
  for my $hash (@$infos) {
    next if $hash->{id} == ($template->{id} // 0);
    next unless $hash->{square_sum};

    my $sum         = 0;
    my $short_array = $hash->{tfidfs_array};
    my $long_array  = $template->{tfidfs_array};

    if ($short_array < $long_array) {
      my $t = $long_array;
      $long_array  = $short_array;
      $short_array = $t;
    }
    my $long_length  = scalar(@$long_array);
    my $short_length = scalar(@$short_array);

    my $long_index  = 0;
    my $short_index = 0;
    while ($short_index < $short_length) {
      my $index1 = $short_array->[$short_index];
      while ($long_index < $long_length && $long_array->[$long_index] < $index1)
      {
        $long_index += 2;
      }
      last unless $long_index < $long_length;
      if ($index1 == $long_array->[$long_index]) {
        $sum
          += $short_array->[$short_index + 1] * $long_array->[$long_index + 1];
      }
      $short_index += 2;
    }
    my $sim = $sum / $hash->{square_sum};
    if ($best < $sim) {
      $best         = $sim;
      $best_pattern = $hash;
    }
  }
  return ($best_pattern, $best / $template->{square_sum});
}
