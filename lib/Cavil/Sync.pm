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
use Mojo::Base -base, -signatures;

use File::Find qw(find);
use Mojo::File qw(path);
use Mojo::JSON qw(decode_json encode_json);
use Term::ProgressBar;

has 'app';
has silent => 0;

sub load ($self, $path) {

  my $app      = $self->app;
  my $db       = $app->pg->db;
  my $patterns = $app->patterns;
  die "License pattern file $path not found" unless -r ($path = path($path));

  my $handle = $path->open('<');
  my $count  = 0;
  $count++ while <$handle>;

  my $progress = Term::ProgressBar->new(
    {count => $count, name => "Importing $count patterns", term_width => 80, silent => $self->silent});

  my $imported = my $all = 0;
  $handle->seek(0, 0);
  for my $line (<$handle>) {
    chomp $line;
    my $hash = decode_json($line);
    $hash->{token_hexsum} = $patterns->checksum($hash->{pattern});
    $imported++ if $db->insert('license_patterns', $hash, {on_conflict => undef, returning => 'id'})->rows;
    $progress->update;
    $all++;
  }
  say "\n@{[$all - $imported]} duplicates ignored" unless $self->silent;

  $patterns->expire_cache;

  # reclculate the tf-idfs
  $app->minion->enqueue(pattern_stats => [] => {priority => 9});

  return $imported;
}

sub store ($self, $path) {

  my $db = $self->app->pg->db;
  $path = path($path);

  my $count    = $db->query('SELECT COUNT(*) FROM license_patterns')->array->[0];
  my $progress = Term::ProgressBar->new(
    {count => $count, name => "Exporting $count patterns", term_width => 80, silent => $self->silent});

  my $handle = $path->open('>');
  my $last   = '00000000-0000-0000-0000-000000000000';
  my $all    = 0;
  while (1) {
    my $results = $db->query(
      'SELECT id, pattern, created, packname, patent, trademark, token_hexsum, license, risk, unique_id, spdx,
         export_restricted
       FROM license_patterns WHERE unique_id > ? ORDER BY unique_id ASC LIMIT 100', $last
    );
    last unless $results->rows;

    for my $hash ($results->hashes->each) {
      $last = my $uuid = $hash->{unique_id};

      my $json = encode_json(
        {
          license           => $hash->{license},
          spdx              => $hash->{spdx},
          packname          => $hash->{packname},
          patent            => $hash->{patent},
          pattern           => $hash->{pattern},
          risk              => $hash->{risk},
          trademark         => $hash->{trademark},
          export_restricted => $hash->{export_restricted},
          unique_id         => $uuid
        }
      );
      print $handle "$json\n";
      $all++;
      $progress->update;
    }
  }
  say "\n$all license patterns exported to $path" unless $self->silent;

  return $all;
}

1;
