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
    'i|input=s'  => \my $input,
    'o|output=s' => \my $output;
  die 'Input or output directory is required' unless (defined $output || defined $input);

  my $app = $self->app;
  my $db  = $app->pg->db;

  return _output($db, $output) if $output;
  return _input($db, $input);
}

sub _classify ($db, $name, $license) {
  return 0 unless $name =~ /^(\w+).txt$/;
  return $db->query(
    'UPDATE snippets SET license = ?, classified = true, approved = true WHERE hash = ? AND approved = false',
    $license, $1)->rows;
}

sub _input ($db, $input) {
  my $root = path($input);
  my $good = $root->child('good');
  my $bad  = $root->child('bad');

  return unless -d $good && -d $bad;

  my $count = 0;
  $count += _classify($db, $_->basename, 1) for $good->list->each;
  $count += _classify($db, $_->basename, 0) for $bad->list->each;

  say "Imported $count snippet classifications";
}

sub _output ($db, $output) {
  my $root = path($output);
  my $good = $root->child('good')->make_path;
  my $bad  = $root->child('bad')->make_path;

  # There can be a lot of snippets, do not load all into memory at once
  my $count = my $last_id = 0;
  while (1) {
    my $approved
      = $db->query('SELECT * FROM snippets WHERE approved = true AND id > ? ORDER BY id ASC LIMIT 100', $last_id);
    last if $approved->rows == 0;

    for my $hash ($approved->hashes->each) {
      $count++;
      my $id = $hash->{id};
      $last_id = $id if $id > $last_id;
      my $dir  = $hash->{license} ? $good : $bad;
      my $file = $dir->child("$hash->{hash}.txt");
      next if -e $file;
      open(my $fh, '>', $file) or die "Couldn't open $file: $!";
      print $fh $hash->{text};
      close($fh);
      say "Exporting snippet $id ($file)";
    }
  }

  say "Exported $count snippets";
}

1;

=encoding utf8

=head1 NAME

Cavil::Command::learn - Cavil learn command

=head1 SYNOPSIS

  Usage: APPLICATION learn [OPTIONS]

    script/cavil learn -e ./input
    script/cavil learn -i ./input

  Options:
    -i, --input <dir>    Import snippet classifications from training data
    -o, --output <dir>   Export snippets for training machine learning models
    -h, --help           Show this summary of available options

=cut
