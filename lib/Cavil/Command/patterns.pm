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

use Mojo::Util 'getopt';

has description => 'License pattern management';
has usage       => sub ($self) { $self->extract_usage };

sub run ($self, @args) {
  getopt \@args, 'check-risks' => \my $check_risks, 'fix-risk=i' => \my $fix_risk, 'license|l=s' => \my $license;

  # Fix risk assessment for license
  return $self->_fix_risk($license, $fix_risk) if defined $fix_risk;

  # Check for licenses with multiple risk assessments
  return $self->_check_risks if $check_risks;

  # License stats
  return $self->_license_stats($license) if $license;

  # Stats
  return $self->_stats;
}

sub _fix_risk ($self, $license, $risk) {
  die 'License name is required' unless $license;
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

sub _license_stats ($self, $license) {
  my $patterns
    = $self->app->pg->db->query('SELECT COUNT(*) AS count FROM license_patterns where license = ?', $license)->hash;
  say "$license has $patterns->{count} patterns";
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

  Options:
        --check-risks       Check for licenses with multiple risk assessments
        --fix-risk <risk>   Fix risk assessments for a license
    -h, --help              Show this summary of available options
    -l, --license <name>    License name

=cut
