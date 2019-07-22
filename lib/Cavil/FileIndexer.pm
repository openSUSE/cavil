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
use Mojo::Base -base;

use Cavil::Checkout;

has 'app';
has 'checkout';
has 'db';
has 'dir';
has 'ignored_files';
has 'ignored_lines';
has 'keywords';
has 'matcher';
has 'package';
has 'snippets';

sub new {
  my ($class, $app, $package) = @_;
  my $self = $class->SUPER::new(app => $app, package => $package);

  my $matcher = Spooky::Patterns::XS::init_matcher();

  my $db = $app->pg->db;
  my $packagename
    = $db->select('bot_packages', 'name', {id => $package})->hash->{name};

  $app->patterns->load_unspecific($matcher);
  $app->patterns->load_specific($matcher, $packagename);
  $self->matcher($matcher);
  $self->ignored_files(Cavil::Util::load_ignored_files($db));

  my $igls   = $db->select('ignored_lines', 'hash', {packname => $packagename});
  my %hashes = map { $_->{hash} => 1 } @{$igls->hashes};
  $self->ignored_lines(\%hashes);

  $self->db($db);
  $self->_calculate_keyword_dict;
  $self->dir($app->package_checkout_dir($package));
  $self->checkout(Cavil::Checkout->new($self->dir));
  $self->snippets({});

  return $self;
}

sub _calculate_keyword_dict {
  my $self     = shift;
  my $patterns = $self->db->select('license_patterns', 'id', {license => ''});
  my %keyword_patterns;
  map { $keyword_patterns{$_->{id}} = 1 } @{$patterns->hashes};
  $self->keywords(\%keyword_patterns);
}

# A 'snippet' is a region of a source file containing keywords.
# The +-1 area around each keyword is taking into it and possible
# keywordless lines in between near keywords too - to form one text
sub _check_missing_snippets {
  my ($self, $file_id, $path, $report) = @_;

  my $keywords = $self->keywords;

  # extract missed snippets
  my %needed_lines;

  # pick uncategorized matches first
  for my $match (@{$report->{matches}}) {
    my ($mid, $ls, $le) = @$match;
    next unless $keywords->{$mid};
    my $line = $ls - 1;
    while ($line <= $le + 1) {
      $needed_lines{$line++} = 1;
    }
  }

  # possible skip between the keyword areas
  my $delta = 6;

  my %mids_considered;

  my $extended_needed_lines;
  do {
    $extended_needed_lines = 0;

    # extend to near matches
    for my $match (@{$report->{matches}}) {
      my ($mid, $ls, $le, $pm_id) = @$match;
      next if $mids_considered{$mid};
      my $prev_line   = _find_near_line(\%needed_lines, $ls - 2, $delta, -1);
      my $follow_line = _find_near_line(\%needed_lines, $le + 2, $delta, +1);
      next unless $prev_line || $follow_line;
      $prev_line   ||= $ls;
      $follow_line ||= $le;
      for (my $line = $prev_line; $line <= $follow_line; $line++) {
        $needed_lines{$line} = 1;
      }
      $mids_considered{$mid} = 1;
      $extended_needed_lines = 1;
    }
  } while ($extended_needed_lines);

  $path = $self->dir->child('.unpacked', $path);

  # process snippet areas
  my $prev_line;
  my $first_snippet_line;
  for my $line (sort { $a <=> $b } keys %needed_lines) {
    if ($prev_line && $line - $prev_line > 1) {
      $self->_snippet($file_id, $report, $path, $first_snippet_line,
        $prev_line);
      $first_snippet_line = undef;
    }
    $first_snippet_line ||= $line;
    $prev_line = $line;
  }
  return unless $first_snippet_line;
  $self->_snippet($file_id, $report, $path, $first_snippet_line, $prev_line);
}

sub _snippet {
  my ($self, $file_id, $report, $path, $first_line, $last_line) = @_;

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

  $self->snippets->{$hash}
    ||= $self->app->snippets->find_or_create($hash, $text);

  my $snippet = $self->snippets->{$hash};
  $self->db->insert(
    'file_snippets',
    {
      package => $self->package,
      snippet => $snippet,
      sline   => $first_line,
      eline   => $last_line,
      file    => $file_id
    }
  );

  return undef;
}


sub _find_near_line {
  my ($lines, $line, $line_delta, $delta) = @_;
  for (my $count = 0; $count < $line_delta; $count++, $line += $delta) {
    return $line if defined $lines->{$line};
  }
  return undef;
}

sub file {
  my ($self, $meta, $path, $mime) = @_;

  my $report = $self->checkout->keyword_report($self->matcher, $meta, $path);
  return unless $report;

  my $file_id;
  my $keywords = $self->keywords;
  my $package  = $self->package;
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

    $keyword_missed ||= $keywords->{$mid};

    # package is kind of duplicated in file, but the join is just too expensive
    my $pm_id = $self->db->insert(
      'pattern_matches',
      {
        file    => $file_id,
        package => $package,
        pattern => $mid,
        sline   => $ls,
        eline   => $le,
        ignored => $ignored_file,
      },
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
