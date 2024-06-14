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

package Cavil::Model::Snippets;
use Mojo::Base -base, -signatures;

use Mojo::File 'path';
use Cavil::Util qw(read_lines);

has [qw(checkout_dir pg)];

sub find ($self, $id) {
  return $self->pg->db->select('snippets', '*', {id => $id})->hash;
}

sub find_or_create ($self, $hash, $text) {
  my $db = $self->pg->db;

  my $snip = $db->select('snippets', 'id', {hash => $hash})->hash;
  return $snip->{id} if $snip;

  $db->query(
    'insert into snippets (hash, text) values (?, ?)
   on conflict do nothing', $hash, $text
  );
  return $db->select('snippets', 'id', {hash => $hash})->hash->{id};
}

sub approve ($self, $id, $license) {
  my $db = $self->pg->db;
  $db->update('snippets', {license => $license eq 'true' ? 1 : 0, approved => 1, classified => 1}, {id => $id});
}

sub unclassified ($self, $options) {
  my $db = $self->pg->db;

  my $before = '';
  if ($options->{before} > 0) {
    my $quoted = $db->dbh->quote($options->{before});
    $before = "AND id < $quoted";
  }

  my $confidence = '';
  if ($options->{confidence} < 100) {
    $confidence = "AND confidence <= " . $options->{confidence};
  }

  my $timeframe = '';
  if ($options->{timeframe} ne 'any') {
    my $interval = "1 $options->{timeframe}";
    $timeframe = "AND created > NOW() - INTERVAL '$interval'";
  }

  my $is_approved   = 'approved = ' . uc($options->{is_approved});
  my $is_classified = 'classified = ' . uc($options->{is_classified});

  my $legal = '';
  if ($options->{is_legal} eq 'true' && $options->{not_legal} eq 'false') {
    $legal = 'AND license = TRUE';
  }
  elsif ($options->{is_legal} eq 'false' && $options->{not_legal} eq 'true') {
    $legal = 'AND license = FALSE';
  }

  my $snippets = $db->query(
    "SELECT *, COUNT(*) OVER() AS total FROM snippets
     WHERE $is_approved AND $is_classified $before $legal $confidence $timeframe ORDER BY id DESC LIMIT 10"
  )->hashes;

  my $total = 0;
  for my $snippet (@$snippets) {
    $total = delete $snippet->{total};
    $snippet->{likelyness} = int($snippet->{likelyness} * 100);
    my $files = $db->query(
      'SELECT fs.sline, mf.filename, mf.package
       FROM file_snippets fs JOIN matched_files mf ON (fs.file = mf.id)
       WHERE fs.snippet = ? ORDER BY fs.id DESC LIMIT 1', $snippet->{id}
    )->hashes;
    $snippet->{files} = $files->size;
    my $file = $files->[0] || {};
    $snippet->{$_} = $file->{$_} for qw(filename sline package);

    my $license = $db->query('SELECT license, risk FROM license_patterns WHERE id = ? AND license != ?',
      $snippet->{like_pattern} // 0, '')->hash // {};
    $snippet->{license_name} = $license->{license};
    $snippet->{risk}         = $license->{risk};
  }

  return {total => $total, snippets => $snippets->to_array};
}

sub mark_non_license ($self, $id) {
  $self->pg->db->update('snippets', {license => 0, approved => 1, classified => 1}, {id => $id});
}

sub packages_for_snippet ($self, $id) {
  return $self->pg->db->query('SELECT DISTINCT(package) FROM file_snippets WHERE snippet = ?', $id)
    ->arrays->flatten->to_array;
}

sub with_context ($self, $id) {
  my $db = $self->pg->db;
  return undef unless my $snippet = $db->select('snippets', '*', {id => $id})->hash;

  my $text     = $snippet->{text};
  my $sline    = 1;
  my $package  = undef;
  my $keywords = {};

  my $example = $db->query(
    'SELECT fs.package, p.name, sline, eline, file, filename, p.checkout_dir
     FROM file_snippets fs JOIN matched_files m ON (m.id = fs.file)
       JOIN bot_packages p ON (p.id = fs.package)
     WHERE snippet = ? LIMIT 1', $id
  )->hash;

  if ($example) {
    $sline   = $example->{sline};
    $package = {id => $example->{package}, name => $example->{name}};

    my $file = path($self->checkout_dir, $package->{name}, $example->{checkout_dir}, '.unpacked', $example->{filename});
    $text = read_lines($file, $example->{sline}, $example->{eline});

    my $patterns = $db->query(
      'SELECT lp.id, lp.license, sline, eline FROM pattern_matches pm JOIN license_patterns lp ON (lp.id = pm.pattern)
     WHERE file = ? AND sline >= ? AND eline <= ? ORDER BY sline', $example->{file}, $example->{sline},
      $example->{eline}
    )->hashes;
    for my $pattern (@$patterns) {
      next if $pattern->{license};
      for (my $line = $pattern->{sline}; $line <= $pattern->{eline}; $line += 1) {
        $keywords->{$line - $example->{sline}} = $pattern->{id};
      }
    }
  }

  return {package => $package, keywords => $keywords, sline => $sline, text => $text};
}

1;
