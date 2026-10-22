# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package Cavil::Sync;
use Mojo::Base -base, -signatures;

use File::Find  qw(find);
use Mojo::File  qw(path);
use Mojo::JSON  qw(decode_json encode_json);
use Cavil::Util ();
use Term::ProgressBar;

has 'app';
has shipped => sub { path(__FILE__)->dirname->child('resources', 'license_patterns.jsonl') };
has silent  => 0;

# Selected and written from one list, so a new column cannot reach one and be dropped by the other. No id or
# created: those are per-instance, and the import dedupes on unique_id.
my @EXPORTED = (qw(unique_id license spdx packname pattern risk catch_all), @Cavil::Util::PATTERN_FLAGS);

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

sub pending ($self, $path) { scalar @{$self->_unknown($path)} }

sub store ($self, $path) {

  my $db = $self->app->pg->db;
  $path = path($path);

  my $count    = $db->query('SELECT COUNT(*) FROM license_patterns')->array->[0];
  my $progress = Term::ProgressBar->new(
    {count => $count, name => "Exporting $count patterns", term_width => 80, silent => $self->silent});

  my $handle  = $path->open('>');
  my $last    = '00000000-0000-0000-0000-000000000000';
  my $all     = 0;
  my $columns = join ', ', @EXPORTED;
  while (1) {
    my $results
      = $db->query("SELECT $columns FROM license_patterns WHERE unique_id > ? ORDER BY unique_id ASC LIMIT 100", $last);
    last unless $results->rows;

    for my $hash ($results->hashes->each) {
      $last = $hash->{unique_id};
      print $handle encode_json({map { $_ => $hash->{$_} } @EXPORTED}), "\n";
      $all++;
      $progress->update;
    }
  }
  say "\n$all license patterns exported to $path" unless $self->silent;

  return $all;
}

sub update ($self, $path) {
  my $patterns = $self->app->patterns;
  my @added    = grep { $patterns->insert_pattern({%$_}) } @{$self->_unknown($path)};
  $patterns->expire_cache if @added;
  return \@added;
}

# Patterns this instance has never seen. Removed ones count as seen, edited ones keep their unique_id, and an edit
# followed by a removal leaves the shipped text only among the old texts of the edit.
sub _unknown ($self, $path) {
  die "License pattern file $path not found" unless -r ($path = path($path));

  my $db    = $self->app->pg->db;
  my %ids   = map { $_ => 1 } @{$db->query('SELECT unique_id FROM license_patterns')->arrays->flatten};
  my %sums  = map { $_ => 1 } @{$db->query('SELECT token_hexsum FROM license_patterns')->arrays->flatten};
  my $known = $db->query(
    q{SELECT data->>'unique_id' AS unique_id, COALESCE(data->>'text', data->'changes'->'text'->>0) AS text
        FROM audit_events WHERE type IN ('pattern.removed', 'pattern.updated')}
  );
  for my $event ($known->hashes->each) {
    $ids{$event->{unique_id}}                            = 1 if defined $event->{unique_id};
    $sums{Cavil::Util::pattern_checksum($event->{text})} = 1 if defined $event->{text};
  }

  my @unknown;
  for my $line (split /\n/, $path->slurp) {
    my $row = decode_json $line;
    next if $ids{$row->{unique_id} // ''};
    next if $sums{$row->{token_hexsum} = Cavil::Util::pattern_checksum($row->{pattern})};
    push @unknown, $row;
  }
  return \@unknown;
}

1;
