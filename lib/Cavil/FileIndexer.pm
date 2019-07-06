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
has 'ignored_lines';
has 'keywords';
has 'matcher';
has 'package';

sub new {
  my ($class, $app, $package) = @_;
  my $self
    = $class->SUPER::new(app => $app, package => $package);

  my $matcher = Spooky::Patterns::XS::init_matcher();

  my $db = $app->pg->db;
  my $packagename
      = $db->select('bot_packages', 'name', {id => $package})->hash->{name};

  $app->patterns->load_unspecific($matcher);
  $app->patterns->load_specific($matcher, $packagename);
  $self->matcher($matcher);

  my $igls = $db->select('ignored_lines', 'hash', { packname => $packagename} );
  my %hashes = map { $_->{hash} => 1 } @{$igls->hashes};
  $self->ignored_lines(\%hashes);

  $self->db($db);
  $self->_calculate_keyword_dict;
  $self->dir($app->package_checkout_dir($package));
  $self->checkout(Cavil::Checkout->new($self->dir));
  return $self;
}

sub _calculate_keyword_dict {
  my $self = shift;
  my $patterns
    = $self->db->select('license_patterns', 'id', {license_string => undef});
  my %keyword_patterns;
  map { $keyword_patterns{$_->{id}} = 1 } @{$patterns->hashes};
  $self->keywords(\%keyword_patterns);
}

sub _check_missing_snippets {
  my ($self, $path, $report) = @_;

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

  # extend to near matches
  for my $match (@{$report->{matches}}) {
    my ($mid, $ls, $le) = @$match;
    my $prev_line   = _find_near_line(\%needed_lines, $ls - 2, $delta, -1);
    my $follow_line = _find_near_line(\%needed_lines, $le + 2, $delta, +1);
    next unless $prev_line || $follow_line;
    $prev_line   ||= $ls;
    $follow_line ||= $le;
    for (my $line = $prev_line; $line <= $follow_line; $line++) {
      $needed_lines{$line} = 1;
    }
  }

  $path = $self->dir->child('.unpacked', $path);

  # process snippet areas
  my $prev_line;
  my $first_snippet_line;
  for my $line (sort { $a <=> $b } keys %needed_lines) {
    if ($prev_line && $line - $prev_line > 1) {
      $self->_snippet($path, $first_snippet_line, $prev_line);
      $first_snippet_line = undef;
    }
    $first_snippet_line ||= $line;
    $prev_line = $line;
  }
  return unless $first_snippet_line;
  $self->_snippet($path, $first_snippet_line, $prev_line);
}

sub _snippet {
  my ($self, $path, $first_line, $last_line) = @_;

  my %lines;
  for (my $line = $first_line; $line <= $last_line; $line += 1) {
    $lines{$line} = 1;
  }

  my $ctx = Spooky::Patterns::XS::init_hash(0, 0);
  for my $row (@{Spooky::Patterns::XS::read_lines($path, \%lines)}) {
    $ctx->add($row->[2] . "\n");
  }

  say "SNP $path " . $ctx->hex . " " . (defined $self->ignored_lines->{$ctx->hex});
  if ($self->ignored_lines->{$ctx->hex}) {
    say "and now?";
  }
  return $ctx->hex;
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

  for my $match (@{$report->{matches}}) {
    $file_id ||= $self->db->insert(
      'matched_files',
      {package   => $self->package, filename => $path, mimetype => $mime},
      {returning => 'id'}
    )->hash->{id};
    my ($mid, $ls, $le) = @$match;

    $keyword_missed ||= $keywords->{$mid};

    # package is kind of duplicated in file, but the join is just too expensive
    $self->db->insert(
      'pattern_matches',
      {
        file    => $file_id,
        package => $package,
        pattern => $mid,
        sline   => $ls,
        eline   => $le
      }
    );
  }
  return unless $keyword_missed;
  $self->_check_missing_snippets($path, $report);
}

1;
