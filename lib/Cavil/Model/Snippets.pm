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
use Cavil::Util qw(file_and_checksum read_lines snippet_checksum SNIPPET_SCORE_VERSION);
use Spooky::Patterns::XS;

has [qw(checkout_dir pg snippet_fold)];

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

  # Avoid duplicate links when the same range is requested again (e.g. an agent retry)
  my $exists = $db->select('file_snippets', 'id',
    {file => $file_id, snippet => $snippet_id, sline => $first_line, eline => $last_line})->hash;
  $db->insert('file_snippets',
    {package => $package->{id}, snippet => $snippet_id, sline => $first_line, eline => $last_line, file => $file_id})
    unless $exists;

  return $snippet_id;
}

sub from_file_path ($self, $package_id, $filename, $first_line, $last_line) {
  return undef
    unless my $file
    = $self->pg->db->select('matched_files', 'id', {package => $package_id, filename => $filename})->hash;
  return $self->from_file($file->{id}, $first_line, $last_line);
}

sub id_for_checksum ($self, $checksum) {
  return undef unless my $hash = $self->pg->db->select('snippets', 'id', {hash => $checksum})->hash;
  return $hash->{id};
}

# The thresholds half of Cavil::ReportUtil::should_fold_snippet expressed as SQL, over a query that
# aliases snippets as "s" and LEFT JOINs license_patterns as "lp" on s.like_pattern. ($sql, \@binds).
sub _fold_sql ($cfg) {
  my @parts = (
    's.classified', 's.license',
    's.score_version = ?',
    's.likelyness >= ?',
    '(s.likelyness - s.second_match) >= ?',
    "lp.license <> ''"
  );
  my @binds = (SNIPPET_SCORE_VERSION, $cfg->{threshold} // 1, $cfg->{min_margin} // 0);
  if (defined $cfg->{max_risk}) {
    push @parts, 'lp.risk <= ?';
    push @binds, $cfg->{max_risk};
  }
  return (join(' AND ', @parts), \@binds);
}

# SQL counterpart of the should_fold_snippet / should_clear_boilerplate gates, for filtering large
# snippet lists where running the Perl gate per row would not scale to a million rows. Returns
# ($where_sql, \@binds) over the "s"/"lp" aliases above. Deliberately ignores $cfg->{enabled}: the
# filter answers "would this fold/clear at the current thresholds", so reviewers can audit even when
# the feature is toggled off. The drift guard in t/snippets.t asserts it agrees with the Perl gates
# run with enabled forced on. $kind is 'fold' or 'clear'; 'clear' excludes 'fold' so the two
# partition the resolved set exactly like the report (fold wins).
# Correlated EXISTS: does the snippet's region overlap a non-ignored license match whose license
# satisfies $license_cond (over the "olp" alias)? Written once and reused for both the "overlaps any
# licensed match" check and the guard's "overlaps the snippet's own license" check.
sub _overlap_exists ($license_cond) {
  return "EXISTS (SELECT 1 FROM file_snippets ofs
      JOIN pattern_matches opm ON opm.file = ofs.file AND opm.sline <= ofs.eline AND opm.eline >= ofs.sline
        AND opm.ignored = false
      JOIN license_patterns olp ON olp.id = opm.pattern AND $license_cond
      WHERE ofs.snippet = s.id)";
}

sub snippet_resolution_sql ($cfg, $kind) {
  my ($fold_sql, $fold_binds) = _fold_sql($cfg);
  return ("($fold_sql)", [@$fold_binds]) if $kind eq 'fold';

  if ($kind eq 'clear') {

    # "Cleared" = dropped from the backlog without asserting a license, by either mechanism, and never
    # something that would fold. The SQL below mirrors should_clear_boilerplate + should_overlap_clear
    # exactly; the drift guard in t/snippets.t fails if the SQL and the Perl gates ever diverge.
    my (@parts, @binds);

    # Similarity boilerplate-clear
    if ($cfg->{clear_threshold}) {
      push @parts, "(s.score_version = ? AND s.likelyness >= ? AND lp.license <> '')";
      push @binds, SNIPPET_SCORE_VERSION, $cfg->{clear_threshold};
    }

    # Overlap-clear: region overlaps a real licensed match, unless the snippet's own closest license
    # resembles a *different* license than any it overlaps (guard -> kept for review).
    if ($cfg->{overlap_clear}) {
      my $guard = '(s.like_pattern IS NOT NULL AND lp.license <> \'\' AND s.likelyness >= ? AND NOT '
        . _overlap_exists('olp.license = lp.license') . ')';
      push @parts, '(' . _overlap_exists("olp.license <> ''") . " AND NOT $guard)";
      push @binds, $cfg->{overlap_guard} // 0.9;
    }

    return ('false', []) unless @parts;    # neither clearing mechanism configured -> matches nothing
    my $any = join ' OR ', @parts;
    return ("(s.classified AND s.license AND ($any) AND NOT ($fold_sql))", [@binds, @$fold_binds]);
  }

  return (undef, []);
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

  # Resolution filter: "would fold / would clear at the current thresholds" (ignores the enabled
  # flag, see snippet_resolution_sql). Needs the license_patterns join below for the risk gate.
  my $resolution = '';
  my @binds;
  if (($options->{resolution} // 'any') =~ /^(fold|clear)$/) {
    my ($sql, $rbinds) = snippet_resolution_sql($self->snippet_fold, $1);
    if (defined $sql) {
      $resolution = "AND $sql";
      push @binds, @$rbinds;
    }
  }

  # Full-text (lexeme) search over snippet bodies; expression matches the GIN index exactly.
  my $search = '';
  if (defined $options->{search} && $options->{search} ne '') {
    $search = "AND to_tsvector('english', s.text) @@ websearch_to_tsquery('english', ?)";
    push @binds, $options->{search};
  }

  # Keyset pagination with no exact total: fetch one extra row to learn whether a next page exists
  # (COUNT(*) OVER() scanned the whole filtered set on every page and does not scale to 1M snippets).
  my $snippets = $db->query(
    "SELECT s.*, bp.embargoed
     FROM snippets s
       LEFT JOIN bot_packages bp ON (bp.id = s.package)
       LEFT JOIN license_patterns lp ON (lp.id = s.like_pattern)
     WHERE $is_approved AND $is_classified $before $legal $confidence $timeframe $resolution $search
     ORDER BY s.id DESC LIMIT 11", @binds
  )->hashes->to_array;

  my $has_more = @$snippets > 10 ? 1 : 0;
  splice @$snippets, 10 if $has_more;

  for my $snippet (@$snippets) {
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

  return {has_more => $has_more, snippets => $snippets};
}

sub mark_non_license ($self, $id) {
  $self->pg->db->update('snippets', {license => 0, approved => 1, classified => 1}, {id => $id});
}

sub packages_for_snippet ($self, $id) {
  return $self->pg->db->query('SELECT DISTINCT(package) FROM file_snippets WHERE snippet = ?', $id)
    ->arrays->flatten->to_array;
}

sub _occurrence ($db, $id, $file_id) {
  my $sql = 'SELECT fs.package, p.name, sline, eline, file, filename, p.checkout_dir
     FROM file_snippets fs JOIN matched_files m ON (m.id = fs.file)
       JOIN bot_packages p ON (p.id = fs.package)
     WHERE snippet = ?';
  my @bind = ($id);
  if (defined $file_id) {
    $sql .= ' AND fs.file = ?';
    push @bind, $file_id;
  }
  $sql .= ' LIMIT 1';
  return $db->query($sql, @bind)->hash;
}

sub with_context ($self, $id, $file_id = undef) {
  return undef unless my $snippet = $self->find($id);

  my $text     = $snippet->{text};
  my $sline    = 1;
  my $package  = undef;
  my $matches  = {};
  my $keywords = {};

  my $db = $self->pg->db;

  # Snippets are deduplicated by content hash, so the same snippet can occur in
  # many files across many packages, each with its own line numbers. When a
  # caller knows which occurrence it is showing (file_id), scope the lookup to
  # that file so the reported line numbers and context match it; otherwise fall
  # back to an arbitrary occurrence (standalone snippet views).
  my $example;
  $example = _occurrence($db, $id, $file_id) if defined $file_id;
  $example //= _occurrence($db, $id, undef);

  if ($example) {
    $sline   = $example->{sline};
    $package = {id => $example->{package}, name => $example->{name}, filename => $example->{filename}};

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

  return {
    package  => $package,
    matches  => $matches,
    keywords => $keywords,
    sline    => $sline,
    text     => $text,
    hash     => $snippet->{hash}
  };
}

1;
