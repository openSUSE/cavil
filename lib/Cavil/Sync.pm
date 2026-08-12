# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

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
    $imported++ if $patterns->insert_pattern(decode_json($line));
    $progress->update;
    $all++;
  }
  say "\n@{[$all - $imported]} duplicates ignored" unless $self->silent;

  $patterns->expire_cache;

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
         export_restricted, cla, eula, catch_all
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
          cla               => $hash->{cla},
          eula              => $hash->{eula},
          catch_all         => $hash->{catch_all},
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
