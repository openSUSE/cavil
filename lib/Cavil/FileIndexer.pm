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

package Cavil::FileIndexer;
use Mojo::Base -base, -signatures;

use Cavil::Checkout;

has 'app';
has 'checkout';
has 'db';
has 'dir';
has 'ignored_files';
has 'ignored_lines';
has 'matcher';
has 'package';
has 'snippets';

sub new ($class, $app, $package) {
  my $self = $class->SUPER::new(app => $app, package => $package);

  my $matcher = Spooky::Patterns::XS::init_matcher();

  my $db          = $app->pg->db;
  my $packagename = $db->select('bot_packages', 'name', {id => $package})->hash->{name};

  $app->patterns->load_unspecific($matcher);
  $app->patterns->load_specific($matcher, $packagename);
  $self->matcher($matcher);
  $self->ignored_files(Cavil::Util::load_ignored_files($db));

  my $igls   = $db->select('ignored_lines', 'hash', {packname => $packagename});
  my %hashes = map { $_->{hash} => 1 } @{$igls->hashes};
  $self->ignored_lines(\%hashes);

  $self->db($db);
  $self->dir($app->package_checkout_dir($package));
  $self->checkout(Cavil::Checkout->new($self->dir));
  $self->snippets({});
  $self->{no_license} = {};

  return $self;
}

sub _mark_area ($needed_lines, $ls, $le) {
  for (my $line = $ls; $line <= $le; $line++) {
    next unless $line > 0;
    $needed_lines->{$line} = 1;
  }
}

# A 'snippet' is a region of a source file containing keywords.
# The +-1 area around each keyword is taking into it and possible
# keywordless lines in between near keywords too - to form one text
sub _check_missing_snippets ($self, $file_id, $path, $report) {

  # extract missed snippets
  my %needed_lines;

  # pick the keyword matches first
  for my $match (@{$report->{matches}}) {
    my ($mid, $ls, $le) = @$match;
    next unless $self->has_no_license($mid);
    _mark_area(\%needed_lines, $ls - 1, $le + 1);
  }

  while (1) {
    my $marked_lines = scalar(%needed_lines);

    my $delta = 6;

    # now check if matches get close to area 9
    for my $match (@{$report->{matches}}) {
      my ($mid, $ls, $le) = @$match;
      for (my $line = $ls - $delta; $line <= $ls; $line++) {
        if (defined $needed_lines{$line}) {
          _mark_area(\%needed_lines, $line, $le);
          last;
        }
      }
      for (my $line = $le; $line <= $le + $delta; $line++) {
        if (defined $needed_lines{$line}) {
          _mark_area(\%needed_lines, $ls, $line);
          last;
        }
      }
    }
    my $now_marked_lines = scalar(%needed_lines);
    last if $now_marked_lines eq $marked_lines;
  }

  $path = $self->dir->child('.unpacked', $path);

  # process snippet areas
  my $prev_line;
  my $first_snippet_line;
  for my $line (sort { $a <=> $b } keys %needed_lines) {
    if ($prev_line && $line - $prev_line > 1) {
      $self->_snippet($file_id, $report, $path, $first_snippet_line, $prev_line);
      $first_snippet_line = undef;
    }
    $first_snippet_line ||= $line;
    $prev_line = $line;
  }
  return unless $first_snippet_line;
  $self->_snippet($file_id, $report, $path, $first_snippet_line, $prev_line);
}

sub _snippet ($self, $file_id, $report, $path, $first_line, $last_line) {
  my %lines;
  for (my $line = $first_line; $line <= $last_line; $line += 1) {
    $lines{$line} = 1;
  }

  my $ctx  = Spooky::Patterns::XS::init_hash(0, 0);
  my $text = '';
  for my $row (@{Spooky::Patterns::XS::read_lines($path, \%lines)}) {
    my $line = $row->[2] . "\n";
    $text .= $line;
    $ctx->add($line);
  }

  # note that the hash is accounting with the newline included
  chop $text;

  my $hash = $ctx->hex;

  # ignored lines are easy targets
  if ($self->ignored_lines->{$hash}) {
    for my $match (@{$report->{matches}}) {
      my ($mid, $ls, $le, $pm_id) = @$match;
      next if $le < $first_line || $ls > $last_line;
      $self->db->update('pattern_matches', {ignored => 1}, {id => $pm_id});
    }
    return;
  }

  $self->snippets->{$hash} ||= $self->app->snippets->find_or_create($hash, $text);

  my $snippet = $self->snippets->{$hash};
  $self->db->insert('file_snippets',
    {package => $self->package, snippet => $snippet, sline => $first_line, eline => $last_line, file => $file_id});

  return undef;
}

sub has_no_license ($self, $pid) {
  return $self->{no_license}{$pid} if defined $self->{no_license}{$pid};
  my $row = $self->db->select('license_patterns', 'license', {id => $pid})->hash;
  $self->{no_license}{$pid} = $row->{license} eq '';
  return $self->{no_license}{$pid};
}

sub file ($self, $meta, $path, $mime) {
  my $report = $self->checkout->keyword_report($self->matcher, $meta, $path);
  return unless $report;

  my $file_id;
  my $package = $self->package;
  my $keyword_missed;

  my $ignored_file = 0;
  for my $ifre (keys %{$self->ignored_files}) {
    next unless $path =~ $ifre;
    $ignored_file = 1;
    last;
  }

  for my $match (@{$report->{matches}}) {
    $file_id ||= $self->db->insert(
      'matched_files',
      {package   => $self->package, filename => $path, mimetype => $mime},
      {returning => 'id'}
    )->hash->{id};
    my ($mid, $ls, $le) = @$match;

    $keyword_missed ||= $self->has_no_license($mid);

    # package is kind of duplicated in file, but the join is just too expensive
    my $pm_id = $self->db->insert(
      'pattern_matches',
      {file => $file_id, package => $package, pattern => $mid, sline => $ls, eline => $le, ignored => $ignored_file,},
      {returning => 'id'}
    )->hash->{id};
    push(@$match, $pm_id);

    # to mark an ignored file, one pattern is enough
    return if $ignored_file;
  }

  return unless $keyword_missed;
  $self->_check_missing_snippets($file_id, $path, $report);
}

1;
