
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

our @EXPORT_OK = (qw(report_checksum));

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

1;
