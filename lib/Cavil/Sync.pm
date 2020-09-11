# Copyright (C) 2020 SUSE Linux GmbH
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

package Cavil::Sync;
use Mojo::Base -base;

use Mojo::File qw(path);
use Mojo::JSON qw(decode_json encode_json);

has 'app';
has silent => 0;

sub load {
  my ($self, $dir) = @_;

  my $app      = $self->app;
  my $db       = $app->pg->db;
  my $patterns = $app->patterns;
  die "License pattern directory $dir not found" unless -d ($dir = path($dir));

  my $imported = my $all = 0;
  for my $first ($dir->list({dir => 1})->each) {
    for my $second ($first->list({dir => 1})->each) {
      for my $target ($second->list->each) {
        my $hash = decode_json($target->slurp);
        $hash->{token_hexsum} = $patterns->checksum($hash->{pattern});
        $imported++ if $db->insert('license_patterns', $hash, {on_conflict => undef, returning => 'id'})->rows;
        $all++;
      }
    }
  }

  $patterns->expire_cache;

  # reclculate the tf-idfs
  $app->minion->enqueue(pattern_stats => [] => {priority => 9});

  say "Imported $imported license patterns (@{[$all - $imported]} duplicates ignored)." unless $self->silent;

  return $imported;
}

sub store {
  my ($self, $dir) = @_;

  my $db = $self->app->pg->db;
  die "License pattern directory $dir not found" unless -d ($dir = path($dir));

  my $last  = my $all = 0;
  my $count = {};
  while (1) {
    my $results = $db->query('select * from license_patterns where id > ? order by id asc limit 100', $last);
    last unless $results->rows;

    for my $hash ($results->hashes->each) {
      $last = $hash->{id};

      my $uuid = $hash->{unique_id};
      my ($first, $second) = (substr($uuid, 0, 1), substr($uuid, 1, 1));
      $count->{"$first$second"}++;
      my $subdir = $dir->child($first, $second);
      $subdir->make_path unless -d $subdir;

      my $target = $subdir->child($uuid);
      $target->spurt(
        encode_json(
          {
            license   => $hash->{license},
            opinion   => $hash->{opinion},
            packname  => $hash->{packname},
            patent    => $hash->{patent},
            pattern   => $hash->{pattern},
            risk      => $hash->{risk},
            trademark => $hash->{trademark},
            unique_id => $uuid
          }
        )
      );
      $all++;
    }
  }

  my $max = (sort { $a <=> $b } values %$count)[-1];
  say "Exported $all license patterns (with a maximum of $max files per directory)." unless $self->silent;

  return $all;
}

1;
