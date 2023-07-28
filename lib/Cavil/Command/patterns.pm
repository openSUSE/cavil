# Copyright (C) 2023 SUSE Linux GmbH
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

package Cavil::Command::patterns;
use Mojo::Base 'Mojolicious::Command', -signatures;

use Cavil::Licenses qw(lic);
use Mojo::Util      qw(encode getopt tablify);
use YAML::XS        qw(Dump);

has description => 'License pattern management';
has usage       => sub ($self) { $self->extract_usage };

sub run ($self, @args) {
  getopt \@args,
    'check-risks'     => \my $check_risks,
    'check-spdx'      => \my $check_spdx,
    'check-unused'    => \my $check_unused,
    'check-used'      => \my $check_used,
    'fix-risk=i'      => \my $fix_risk,
    'inherit-spdx'    => \my $inherit_spdx,
    'license|l=s'     => \my $license,
    'match=i'         => \my $match,
    'preview|P=i'     => \(my $preview = 57),
    'remove-unused=i' => \my $remove_unused,
    'remove-used=i'   => \my $remove_used;

  # Show pattern match
  return $self->_match($match, $preview) if $match;

  # Remove unused license pattern
  return $self->_remove_unused($remove_unused) if $remove_unused;

  # Remove license pattern currently in use
  return $self->_remove_used($remove_used) if $remove_used;

  # Fix risk assessment for license
  return $self->_fix_risk($license, $fix_risk) if defined $fix_risk;

  # Check license names for valid SPDX expressions
  return $self->_inherit_spdx if $inherit_spdx;

  # Check for licenses with multiple risk assessments
  return $self->_check_risks if $check_risks;

  # Check for licenses patterns with inconsistent SPDX expressions
  return $self->_check_spdx if $check_spdx;

  # Check for unused patterns
  return $self->_check_use(1, $license, $preview) if $check_unused;

  # Check for used patterns
  return $self->_check_use(0, $license, $preview) if $check_used;

  # License stats
  return $self->_license_stats($license) if $license;

  # Stats
  return $self->_stats;
}

sub _check_risks ($self) {
  my $results = $self->app->pg->db->query('SELECT license, risk FROM license_patterns GROUP BY (license, risk)');

  my $licenses = {};
  for my $hash ($results->hashes->each) {
    my $license = $hash->{license};
    my $risk    = $hash->{risk};
    if (exists $licenses->{$license}) {
      push @{$licenses->{$license}}, $risk;
    }
    else {
      $licenses->{$license} = [$risk];
    }
  }

  for my $license (sort keys %$licenses) {
    next if @{$licenses->{$license}} == 1;
    say "$license: @{[join(', ', @{$licenses->{$license}})]}";
  }
}

sub _check_spdx ($self) {
  my $results = $self->app->pg->db->query('SELECT license, spdx FROM license_patterns GROUP BY (license, spdx)');

  my $licenses = {};
  for my $hash ($results->hashes->each) {
    my $license = $hash->{license};
    my $spdx    = $hash->{spdx};
    if (exists $licenses->{$license}) {
      push @{$licenses->{$license}}, $spdx;
    }
    else {
      $licenses->{$license} = [$spdx];
    }
  }

  for my $license (sort keys %$licenses) {
    next if @{$licenses->{$license}} == 1;
    say "$license: @{[join(', ', @{$licenses->{$license}})]}";
  }
}

sub _check_use ($self, $unused, $license, $preview) {
  die 'License name is required' unless defined $license;

  my $db      = $self->app->pg->db;
  my $results = $db->query('SELECT id, risk, pattern FROM license_patterns WHERE license = ? ORDER BY risk ASC, id ASC',
    $license);

  my $table = [];
  for my $pattern ($results->hashes->each) {
    my ($id, $risk, $pattern) = @{$pattern}{qw(id risk pattern)};
    my $count = $db->query('SELECT count(*) AS count FROM pattern_matches WHERE pattern = ?', $id)->hash->{count};

    my $snippet = encode('UTF-8', _preview($pattern, $preview));
    if ($unused) {
      push @$table, [$id, $risk, $snippet] if $count == 0;
    }
    else {
      push @$table, [$id, $count, $risk, $snippet] if $count > 0;
    }
  }

  print tablify $table;
}

sub _fix_risk ($self, $license, $risk) {
  die 'License name is required' unless defined $license;
  my $rows = $self->app->pg->db->query('UPDATE license_patterns SET risk = ? WHERE license = ?', $risk, $license)->rows;
  say "$rows patterns fixed";
}

sub _inherit_spdx ($self) {
  my $db = $self->app->pg->db;
  my $tx = $db->begin;

  for my $license ($db->query('SELECT DISTINCT(license) AS name FROM license_patterns')->hashes->each) {
    next unless my $name = $license->{name};
    my $lic = lic($name);
    next if $lic->error;
    my $rows = $db->query('UPDATE license_patterns SET spdx = ? WHERE license = ?', $lic->to_string, $name)->rows;
    say "$name -> $lic: $rows patterns updated";
  }

  $tx->commit;
}

sub _license_stats ($self, $license) {
  my $patterns
    = $self->app->pg->db->query('SELECT COUNT(*) AS count FROM license_patterns WHERE license = ?', $license)->hash;
  say "$license has $patterns->{count} patterns";
}

sub _match ($self, $id, $preview) {

  # Pattern match
  die "Pattern match not found" unless my $match = $self->_match_info($id);
  $match->{pattern} = _preview($match->{pattern}, $preview);
  say '## Pattern Match';
  say Dump($match);

  # Overlapping pattern matches
  my $db = $self->app->pg->db;
  my @overlapping;
  my $overlapping_matches
    = $db->query('SELECT id FROM pattern_matches WHERE file = ? AND sline <= ? AND eline >= ? AND id != ?',
    @{$match}{qw(file eline sline id)})->hashes;
  for my $overlapping_match ($overlapping_matches->each) {
    push @overlapping, $self->_match_info($overlapping_match->{id});
  }
  if (@overlapping) {
    say '## Overlapping Pattern Matches';
    say Dump(\@overlapping);
  }

  # Snippets
  my @snippets;
  my $snippet_sql = q{
    SELECT s.*, fs.sline, fs.eline, mf.id AS file_id, mf.filename
    FROM file_snippets fs
      LEFT JOIN snippets s ON fs.snippet = s.id
      LEFT JOIN matched_files mf ON fs.file = mf.id
    WHERE file = ? AND sline <= ? AND eline >= ?
  };
  for my $snippet_match ($db->query($snippet_sql, @{$match}{qw(file eline sline)})->hashes->each) {
    $snippet_match->{text} = _preview($snippet_match->{text}, $preview);
    push @snippets, $snippet_match;
  }
  if (@snippets) {
    say '## Related Snippets';
    say Dump(\@snippets);
  }
}

sub _match_info ($self, $id) {
  my $sql = q{
    SELECT pm.*, lp.id AS pattern_id, lp.license, lp.opinion, lp.packname, lp.patent, lp.pattern, lp.spdx,
      lp.token_hexsum, lp.trademark, mf.id AS file_id, mf.filename
    FROM pattern_matches pm
      LEFT JOIN license_patterns lp ON pm.pattern = lp.id
      LEFT JOIN matched_files mf ON pm.file = mf.id
    WHERE pm.id = ?
  };
  return $self->app->pg->db->query($sql, $id)->hash;
}

sub _preview ($pattern, $preview) {
  $pattern =~ s/[^[:print:]]+//g;
  my $len     = length $pattern;
  my $snippet = substr $pattern, 0, $preview;
  $snippet .= '...' . ($len - $preview) if $len > $preview;
  return $snippet;
}

sub _remove_unused ($self, $id) {
  my $app = $self->app;
  my $db  = $app->pg->db;

  my $tx    = $db->begin;
  my $count = $db->query('SELECT count(*) AS count FROM pattern_matches WHERE pattern = ?', $id)->hash->{count};
  die "Pattern $id is still in use and cannot be removed" unless $count == 0;
  $db->query('DELETE FROM license_patterns WHERE id = ?', $id);
  $tx->commit;

  $app->patterns->expire_cache;
}

sub _remove_used ($self, $id) {
  my $app = $self->app;
  my $db  = $app->pg->db;

  my $tx       = $db->begin;
  my $packages = $db->query('SELECT DISTINCT(package) FROM pattern_matches WHERE pattern = ?', $id)
    ->hashes->map(sub { $_->{package} })->to_array;
  $db->query('DELETE FROM license_patterns WHERE id = ?', $id);
  $tx->commit;

  $app->patterns->expire_cache;
  my $pkgs = $app->packages;
  say "@{[scalar @$packages]} packages need to be reindexed";
  $pkgs->reindex($_, 1) for @$packages;
}

sub _stats ($self) {
  return unless my $patterns = $self->app->pg->db->query('SELECT COUNT(*) AS count FROM license_patterns')->hash;
  return
    unless my $licenses
    = $self->app->pg->db->query('SELECT COUNT(DISTINCT license) AS count FROM license_patterns')->hash;
  say "$licenses->{count} licenses with $patterns->{count} patterns";
}

1;

=encoding utf8

=head1 NAME

Cavil::Command::patterns - Cavil command to manage license patterns

=head1 SYNOPSIS

  Usage: APPLICATION patterns

    script/cavil patterns

    # Check risk assessments for inconsistencies
    script/cavil patterns --check-risks

    # Fix risk assessment for a license
    script/cavil patterns --license MIT --fix-risk 3

    # Check for unused license patterns
    script/cavil patterns --check-unused --license Artistic-2.0

    # Remove unused license pattern (cannot remove patterns still in use)
    script/cavil patterns --remove-unused 23

    # Show all known information for a specific pattern match
    script/cavil patterns --match 12345

  Options:
        --match <id>           Show all known information for a pattern match
        --check-risks          Check for licenses with multiple risk assessments
        --check-spdx           Check for licenses patterns with inconsistent
                               SPDX expressions
        --check-unused         Check for unused license patterns
        --check-used           Check for license patterns currently in use
        --fix-risk <risk>      Fix risk assessments for a license
    -h, --help                 Show this summary of available options
        --inherit-spdx         Reuse the license name for all licenses that are
                               already valid SPDX expressions
    -l, --license <name>       License name
        --remove-unused <id>   Remove unused license pattern (cannot remove
                               patterns still in use)
        --remove-used <id>     Remove license pattern despite it being
                               currently in use
    -P, --preview <length>     Length of pattern previews, defaults to 57

=cut
