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

use Mojo::File  qw(path);
use Cavil::Util qw(file_and_checksum read_lines snippet_checksum);
use Spooky::Patterns::XS;

has [qw(checkout_dir pg)];

sub approve ($self, $id, $license) {
  my $db = $self->pg->db;
  $db->update('snippets', {license => $license eq 'true' ? 1 : 0, approved => 1, classified => 1}, {id => $id});
}

sub find ($self, $id) {
  return $self->pg->db->select('snippets', '*', {id => $id})->hash;
}

sub find_or_create ($self, $new) {
  $new->{prefix} //= '';
  my $db = $self->pg->db;

  my $old = $db->query(
    'SELECT s.id, bp.embargoed FROM snippets s LEFT JOIN bot_packages bp ON (bp.id = s.package)
     WHERE hash = ?', $new->{hash}
  )->hash;

  # Inherit embargo status until there is no embargo anymore (the value will tell us which package lifted the embargo)
  if ($old) {
    $db->query('UPDATE snippets SET package = ? WHERE id = ?', $new->{package}, $old->{id}) if $old->{embargoed};
    return $old->{id};
  }

  my $hash = "$new->{prefix}$new->{hash}";
  $db->query('INSERT INTO snippets (hash, text, package) VALUES (?, ?, ?) ON CONFLICT DO NOTHING',
    $hash, $new->{text}, $new->{package});
  return $db->select('snippets', 'id', {hash => $hash})->hash->{id};
}

sub from_file ($self, $file_id, $first_line, $last_line) {
  my $db   = $self->pg->db;
  my $file = $db->select('matched_files', '*', {id => $file_id})->hash;
  return undef unless $file;

  my $package = $db->select('bot_packages', '*', {id => $file->{package}})->hash;
  my $path    = path($self->checkout_dir, $package->{name}, $package->{checkout_dir}, '.unpacked', $file->{filename});

  my ($text, $hash) = file_and_checksum($path, $first_line, $last_line);
  my $snippet_id
    = $self->find_or_create({hash => $hash, text => $text, package => $package->{id}, prefix => 'manual:'});
  $db->insert('file_snippets',
    {package => $package->{id}, snippet => $snippet_id, sline => $first_line, eline => $last_line, file => $file_id});

  return $snippet_id;
}

sub id_for_checksum ($self, $checksum) {
  return undef unless my $hash = $self->pg->db->select('snippets', 'id', {hash => $checksum})->hash;
  return $hash->{id};
}

sub unclassified ($self, $options) {
  my $db = $self->pg->db;

  my $before = '';
  if ($options->{before} > 0) {
    my $quoted = $db->dbh->quote($options->{before});
    $before = "AND s.id < $quoted";
  }

  my $confidence = '';
  if ($options->{confidence} < 100) {
    $confidence = "AND confidence <= " . $options->{confidence};
  }

  my $timeframe = '';
  if ($options->{timeframe} ne 'any') {
    my $interval = "1 $options->{timeframe}";
    $timeframe = "AND s.created > NOW() - INTERVAL '$interval'";
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
    "SELECT s.*, bp.embargoed, COUNT(*) OVER() AS total
     FROM snippets s LEFT JOIN bot_packages bp ON (bp.id = s.package)
     WHERE $is_approved AND $is_classified $before $legal $confidence $timeframe ORDER BY s.id DESC LIMIT 10"
  )->hashes;

  my $total = 0;
  for my $snippet (@$snippets) {
    $total = delete $snippet->{total};
    $snippet->{likelyness} = int($snippet->{likelyness} * 100);
    my $files = $db->query(
      'SELECT fs.sline, mf.filename, mf.package AS filepackage
       FROM file_snippets fs JOIN matched_files mf ON (fs.file = mf.id)
       WHERE fs.snippet = ? ORDER BY fs.id DESC LIMIT 1', $snippet->{id}
    )->hashes;
    $snippet->{files} = $files->size;
    my $file = $files->[0] || {};
    $snippet->{$_} = $file->{$_} for qw(filename sline filepackage);

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
  return undef unless my $snippet = $self->find($id);

  my $text     = $snippet->{text};
  my $sline    = 1;
  my $package  = undef;
  my $matches  = {};
  my $keywords = {};

  my $db      = $self->pg->db;
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
      my $map = $pattern->{license} ? $matches : $keywords;
      for (my $line = $pattern->{sline}; $line <= $pattern->{eline}; $line += 1) {
        $map->{$line - $example->{sline}} = $pattern->{id};
      }
    }
  }

  return {package => $package, matches => $matches, keywords => $keywords, sline => $sline, text => $text};
}

1;
