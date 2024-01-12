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
  getopt \@args, 'e|export=s' => \my $export;
  die 'Export directory is required' unless defined $export;

  my $app = $self->app;
  my $db  = $app->pg->db;

  my $root = path($export);
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

  Usage: APPLICATION learn

    script/cavil learn -e ./input

  Options:
    -e, --export <dir>   Export snippets for training machine learning models
    -h, --help           Show this summary of available options

=cut
