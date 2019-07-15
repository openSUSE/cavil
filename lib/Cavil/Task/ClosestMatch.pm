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

package Cavil::Task::ClosestMatch;
use Mojo::Base 'Mojolicious::Plugin';

use Mojo::JSON 'encode_json';
use Cavil::Util;
use Cavil::Text qw(wordcount calculate_tfdifs);

sub register {
  my ($self, $app) = @_;
  $app->minion->add_task(pattern_stats => \&_pattern_stats);
}

sub _count_all_words {
  my $infos = shift;

  my %words;
  my $num_infos = scalar @$infos;
  for my $hash (@$infos) {
    $hash->{wordcount} = wordcount($hash->{pattern});
    for my $word (keys %{$hash->{wordcount}}) {
      $words{$word} += 1;
    }
  }
  my @word_indexed = sort(keys %words);
  my %word2index;
  my $index = 0;
  for my $word (@word_indexed) {
    $word2index{$word} = $index++;
  }

  my %idfs;
  for my $word (@word_indexed) {
    $idfs{$word} = log($num_infos / $words{$word});
  }

  return (\%word2index, \%idfs);
}

sub _pattern_stats {
  Spooky::Patterns::XS::init_matcher();

  my $job = shift;

  my $app = $job->app;
  my $db  = $app->pg->db;

  my $patterns
    = $db->select('license_patterns', '*', {}, {order_by => 'id'})->hashes;

  my ($word2index, $idfs) = _count_all_words($patterns);

  my @pattern_infos;
  for my $hash (@$patterns) {
    my ($sum, $array)
      = calculate_tfdifs($hash->{wordcount}, $word2index, $idfs);
    push(@pattern_infos,
      {id => $hash->{id}, tfidfs_array => $array, square_sum => $sum});

    # safe memory
    delete $hash->{wordcount};
  }

  my $cache = $app->home->child('cache', 'cavil.pattern.words');
  $cache->spurt(
    encode_json(
      {words => $word2index, patterns => \@pattern_infos, idfs => $idfs}
    )
  );
}

1;
