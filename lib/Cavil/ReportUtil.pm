
# Copyright (C) 2024 SUSE LLC
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

package Cavil::ReportUtil;
use Mojo::Base -strict, -signatures;

use Exporter 'import';
use List::Util 'uniq';
use Mojo::Util;
use Cavil::Licenses 'lic';

our @EXPORT_OK = (qw(estimated_risk report_checksum report_shortname summary_delta summary_delta_score));

sub estimated_risk ($risk, $match) {
  my $estimated = int(($risk * $match + 9 * (1 - $match)) + 0.5);
  return $match < 0.9 && $estimated <= 3 ? 4 : $estimated;
}

sub report_checksum ($specfile_report, $dig_report) {

  # Specfile license
  my $canon_license = lic($specfile_report->{main}{license})->canonicalize->to_string;
  $canon_license ||= "Unknown";
  my $text = "RPM-License $canon_license\n";

  # Licenses
  for my $license (sort { $a cmp $b } keys %{$dig_report->{licenses}}) {
    next if $dig_report->{licenses}{$license}{risk} == 0;
    $text .= "LIC:$license";
    for my $flag (@{$dig_report->{licenses}{$license}{flags}}) {
      $text .= ":$flag";
    }
    $text .= "\n";
  }

  # Unique snippets of unresolved keyword matches
  if (my $snippets = $dig_report->{snippets}) {
    my @all;
    for my $file (sort keys %$snippets) {
      my $matches = $snippets->{$file};
      push @all, $matches->{$_} for sort keys %$matches;
    }
    $text .= "SNIPPET:$_\n" for uniq @all;
  }

  return Mojo::Util::md5_sum $text;
}

sub report_shortname ($chksum, $specfile_report, $dig_report) {
  my $max_risk = 0;
  for my $risk (keys %{$dig_report->{risks}}) {
    $max_risk = $risk if $risk > $max_risk;
  }
  for my $file (keys %{$dig_report->{missed_files}}) {
    my $risk = $dig_report->{missed_files}{$file}[0];
    $max_risk = $risk if $risk > $max_risk;
  }

  my $l = lic($specfile_report->{main}{license})->example;
  $l ||= 'Error';

  return "$l-$max_risk:$chksum";
}

sub summary_delta ($old, $new) {
  my $text = '';

  # Specfile license change
  if ($new->{specfile} ne $old->{specfile}) {
    $text .= "  Different spec file license: $old->{specfile}\n\n";
  }

  # Files with new missed snippets
  my @files_with_new_snippets;
  my $new_snippets = $new->{missed_snippets};
  for my $file (sort keys %$new_snippets) {
    my %old_snippets = map { $_ => 1 } @{$old->{missed_snippets}{$file} || []};
    for my $snippet (@{$new_snippets->{$file}}) {
      next if $old_snippets{$snippet};
      push @files_with_new_snippets, $file;
      last;
    }
  }
  if (@files_with_new_snippets) {
    $text .= "  New unresolved matches in " . (shift @files_with_new_snippets);
    if (@files_with_new_snippets) {
      my $num = scalar @files_with_new_snippets;
      $text .= " and $num " . ($num > 1 ? 'files' : 'file') . ' more';
    }
    $text .= "\n\n";
  }

  # New licenses
  my %lics = %{$new->{licenses}};
  delete $lics{$_} for keys %{$old->{licenses}};
  if (keys %lics) {
    my @lines;
    for my $lic (sort keys %lics) {
      push @lines, "  Found new license $lic (risk $lics{$lic}) not present in old report";
    }
    $text .= join("\n", @lines) . "\n\n";
  }

  return length $text ? "Diff to closest match $old->{id}:\n\n$text" : '';
}

sub summary_delta_score ($old, $new) {

  # Specfile license change
  if ($new->{specfile} ne $old->{specfile}) {
    return 1000;
  }

  my $score = 0;

  # New files with missed snippets (count)
  if (keys %{$new->{missed_snippets}} > keys %{$old->{missed_snippets}}) {
    $score += 250;
  }

  # Check each file
  else {
    my $new_snippets = $new->{missed_snippets};
    for my $file (sort keys %$new_snippets) {
      if (my $old_snippets = $old->{missed_snippets}{$file}) {
        my %old_snippets = map { $_ => 1 } @$old_snippets;
        for my $snippet (@{$new_snippets->{$file}}) {
          $score += 20 unless $old_snippets{$snippet};
        }
      }

      # New file with missed snippets (filename)
      else {
        $score += 150;
      }
    }
  }

  # New licenses
  my %lics = %{$new->{licenses}};
  delete $lics{$_} for keys %{$old->{licenses}};
  for my $risk (values %lics) {
    $score += $risk * 10;
  }

  return $score;
}

1;
