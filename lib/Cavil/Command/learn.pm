# Copyright (C) 2024 SUSE Linux GmbH
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

package Cavil::Command::learn;
use Mojo::Base 'Mojolicious::Command', -signatures;

use Mojo::Util qw(getopt);
use Mojo::File qw(path);

has description => 'Training data for machine learning';
has usage       => sub ($self) { $self->extract_usage };

sub run ($self, @args) {
  getopt \@args,
    'convert=s'  => \my $convert,
    'i|input=s'  => \my $input,
    'o|output=s' => \my $output,
    'p|patterns' => \my $patterns;
  die 'Input or output directory is required' unless (defined $output || defined $input || defined $convert);

  return $self->_convert($convert)          if $convert;
  return $self->_output($output, $patterns) if $output;
  return $self->_input($input);
}

sub _classify ($db, $name, $license) {
  return 0 unless $name =~ /^(\w+).txt$/;
  my $checksum = $1;
  return 0 unless $db->query('SELECT id FROM snippets WHERE hash = ? AND approved = false', $checksum)->rows;
  return $db->query(
    'UPDATE snippets SET license = ?, classified = true, approved = true WHERE hash = ? AND approved = false',
    $license, $checksum)->rows;
}

sub _convert ($self, $convert) {
  my $patterns = $self->app->patterns;
  my $dir      = path($convert);

  for my $old ($dir->list->each) {
    my $content  = $old->slurp;
    my $checksum = $patterns->checksum($content);
    my $new      = $old->sibling("$checksum.txt");
    $new->spew($content);
    $old->remove;
    say "Converted @{[$old->basename]} to @{[$new->basename]}";
  }
}

sub _input ($self, $input) {
  my $db = $self->app->pg->db;

  my $root = path($input);
  my $good = $root->child('good');
  my $bad  = $root->child('bad');

  return unless -d $good && -d $bad;

  my $count = 0;
  $count += _classify($db, $_->basename, 1) for $good->list->each;
  $count += _classify($db, $_->basename, 0) for $bad->list->each;

  say "Imported $count snippet classifications";
}

sub _output ($self, $output, $patterns) {
  my $root = path($output);
  my $good = $root->child('good')->make_path;
  my $bad  = $root->child('bad')->make_path;
  return $self->_output_patterns($good, $bad) if $patterns;
  return $self->_output_snippets($good, $bad);
}

sub _output_patterns ($self, $good, $bad) {
  my $app      = $self->app;
  my $patterns = $app->patterns;
  my $db       = $app->pg->db;

  my $count = my $last_id = 0;
  while (1) {
    my $batch = $db->query(
      q{SELECT id, pattern FROM license_patterns
        WHERE license != '' AND id > ? ORDER BY id ASC LIMIT 100}, $last_id
    );
    last if $batch->rows == 0;

    for my $hash ($batch->hashes->each) {
      $count++;
      my $id = $hash->{id};
      $last_id = $id if $id > $last_id;

      # Some patterns contain "$SKIP19" and similar keywords
      my $pattern = $hash->{pattern};
      $pattern =~ s/\ *\$SKIP\d+\ */ /sg;

      my $checksum = $patterns->checksum($pattern);
      my $file     = $good->child("$checksum.txt");
      next unless _spew($file, $pattern);
      say "Exporting pattern $id ($file)";
    }
  }

  say "Exported $count patterns";
}

sub _output_snippets ($self, $good, $bad) {
  my $db = $self->app->pg->db;

  my $count = my $last_id = 0;
  while (1) {
    my $batch
      = $db->query('SELECT * FROM snippets WHERE approved = true AND id > ? ORDER BY id ASC LIMIT 100', $last_id);
    last if $batch->rows == 0;

    for my $hash ($batch->hashes->each) {
      $count++;
      my $id = $hash->{id};
      $last_id = $id if $id > $last_id;
      my $dir  = $hash->{license} ? $good : $bad;
      my $file = $dir->child("$hash->{hash}.txt");
      next unless _spew($file, $hash->{text});
      say "Exporting snippet $id ($file)";
    }
  }

  say "Exported $count snippets";
}

sub _spew ($file, $content) {
  return 0 if -e $file;
  open(my $fh, '>', $file) or die "Couldn't open $file: $!";
  print $fh $content;
  close($fh);
  return 1;
}

1;

=encoding utf8

=head1 NAME

Cavil::Command::learn - Cavil learn command

=head1 SYNOPSIS

  Usage: APPLICATION learn [OPTIONS]

    script/cavil learn -o ./ml-data
    script/cavil learn -p -o  ./ml-data
    script/cavil learn -i ./ml-data
    script/cavil learn --convert ./text-files

  Options:
        --convert <dir>   Convert a directory with arbitary text files into
                          training data (this is a destructive operation)
    -i, --input <dir>     Import snippet classifications from training data
    -o, --output <dir>    Export snippets for training machine learning models
    -p, --patterns        Convert license patterns into snippets and export
                          those instead
    -h, --help            Show this summary of available options

=cut
