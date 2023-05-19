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

use Mojo::Util qw(encode getopt tablify);

has description => 'License pattern management';
has usage       => sub ($self) { $self->extract_usage };

sub run ($self, @args) {
  getopt \@args,
    'check-risks'     => \my $check_risks,
    'check-unused'    => \my $check_unused,
    'check-used'      => \my $check_used,
    'fix-risk=i'      => \my $fix_risk,
    'license|l=s'     => \my $license,
    'preview|P=i'     => \(my $preview = 57),
    'remove-unused=i' => \my $remove_unused,
    'remove-used=i'   => \my $remove_used;

  # Remove unused license pattern
  return $self->_remove_unused($remove_unused) if $remove_unused;

  # Remove license pattern currently in use
  return $self->_remove_used($remove_used) if $remove_used;

  # Fix risk assessment for license
  return $self->_fix_risk($license, $fix_risk) if defined $fix_risk;

  # Check for licenses with multiple risk assessments
  return $self->_check_risks if $check_risks;

  # Check for unused patterns
  return $self->_check_use(1, $license, $preview) if $check_unused;

  # Check for used patterns
  return $self->_check_use(0, $license, $preview) if $check_used;

  # License stats
  return $self->_license_stats($license) if $license;

  # Stats
  return $self->_stats;
}

sub _fix_risk ($self, $license, $risk) {
  die 'License name is required' unless defined $license;
  my $rows = $self->app->pg->db->query('UPDATE license_patterns SET risk = ? WHERE license = ?', $risk, $license)->rows;
  say "$rows patterns fixed";
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

sub _check_use ($self, $unused, $license, $preview) {
  die 'License name is required' unless defined $license;

  my $db      = $self->app->pg->db;
  my $results = $db->query('SELECT id, risk, pattern FROM license_patterns WHERE license = ? ORDER BY risk ASC, id ASC',
    $license);

  my $table = [];
  for my $pattern ($results->hashes->each) {
    my ($id, $risk, $pattern) = @{$pattern}{qw(id risk pattern)};
    my $count = $db->query('SELECT count(*) AS count FROM pattern_matches WHERE pattern = ?', $id)->hash->{count};

    $pattern =~ s/[^[:print:]]+//g;
    my $len     = length $pattern;
    my $snippet = substr encode('UTF-8', $pattern), 0, $preview;
    $snippet .= '...' . ($len - $preview) if $len > $preview;
    if ($unused) {
      push @$table, [$id, $risk, $snippet] if $count == 0;
    }
    else {
      push @$table, [$id, $count, $risk, $snippet] if $count > 0;
    }
  }

  print tablify $table;
}

sub _license_stats ($self, $license) {
  my $patterns
    = $self->app->pg->db->query('SELECT COUNT(*) AS count FROM license_patterns WHERE license = ?', $license)->hash;
  say "$license has $patterns->{count} patterns";
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

  Options:
        --check-risks          Check for licenses with multiple risk assessments
        --check-unused         Check for unused license patterns
        --check-used           Check for license patterns currently in use
        --fix-risk <risk>      Fix risk assessments for a license
    -h, --help                 Show this summary of available options
    -l, --license <name>       License name
        --remove-unused <id>   Remove unused license pattern (cannot remove
                               patterns still in use)
        --remove-used <id>     Remove license pattern despite it being
                               currently in use
    -P, --preview <length>     Length of pattern previews, defaults to 57

=cut
