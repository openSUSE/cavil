
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
use List::Util qw(uniq);
use Mojo::Util;
use Cavil::Licenses 'lic';

our @EXPORT_OK
  = (qw(estimated_risk incompatible_licenses report_checksum report_shortname summary_delta summary_delta_score));

# For now we only watch out for GPL-2.0-only and Apache-2.0
my $INCOMPATIBLE_LICENSE_RULES = [{licenses => ['GPL-2.0-only', 'Apache-2.0']}];

sub estimated_risk ($risk, $match) {
  my $estimated = int(($risk * $match + 9 * (1 - $match)) + 0.5);
  return $match < 0.9 && $estimated <= 3 ? 4 : $estimated;
}

sub incompatible_licenses ($dig_report, $rules = $INCOMPATIBLE_LICENSE_RULES) {
  return [] unless @$rules;

  my @spdx;
  push @spdx, map { $_->{spdx} } grep { $_->{spdx} } values %{$dig_report->{licenses}  || {}};
  push @spdx, map { $_->[3] } grep    { $_->[3] } values %{$dig_report->{missed_files} || {}};

  my @regexes;
  for my $rule (@$rules) {
    push @regexes, [qr/\Q$_\E/i, $_] for @{$rule->{licenses}};
  }

  my %matches;
  for my $spdx (uniq @spdx) {
    for my $pair (@regexes) {
      next unless $spdx =~ $pair->[0];
      $matches{$pair->[1]}++;
    }
  }

  my @results;
  for my $rule (@$rules) {
    my $licenses = $rule->{licenses};
    my $found    = 0;
    for my $license (@$licenses) {
      last unless $matches{$license};
      $found++;
    }
    push @results, {licenses => [@$licenses]} if $found == @$licenses;
  }

  return \@results;
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

  # License incompatibilities
  if (my $incompat = $dig_report->{incompatible_licenses}) {
    for my $rule (@$incompat) {
      $text .= "INCOMPAT:" . join(':', sort @{$rule->{licenses}}) . "\n";
    }
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
  $max_risk = 9 if $dig_report->{incompatible_licenses} && @{$dig_report->{incompatible_licenses}};

  my $l = lic($specfile_report->{main}{license})->example;
  $l ||= 'Unknown';

  return "$l-$max_risk:$chksum";
}

sub summary_delta ($old, $new) {
  my $text = '';

  # Specfile license change
  if ($new->{specfile} ne $old->{specfile}) {
    $text .= "  Different spec file license: $old->{specfile}\n\n";
  }

  # New snippet matches
  my $new_snippets = _new_snippets($old, $new);
  if (my @files = sort values %$new_snippets) {
    my $file = $files[0];
    my $num  = uniq(@files) - 1;
    if ($num == 0) {
      $text .= "  Found new unresolved matches in $file\n\n";
    }
    elsif ($num == 1) {
      $text .= "  Found new unresolved matches in $file and 1 other file\n\n";
    }
    else {
      $text .= "  Found new unresolved matches in $file and $num other files\n\n";
    }
  }

  # New licenses
  my $new_licenses = _new_licenses($old, $new);
  my @lines;
  for my $lic (sort keys %$new_licenses) {
    push @lines, "  Found new license $lic (risk $new_licenses->{$lic}) not present in old report";
  }
  $text .= join("\n", @lines) . "\n\n" if @lines;

  # License incompatibilities
  if (my @licenses = _new_incompatibilities($old, $new)) {
    my $licenses = join(', ', @licenses);
    $text .= "  Found new possible license incompatibility involving: $licenses\n\n";
  }

  return length $text ? "Diff to closest match $old->{id}:\n\n$text" : '';
}

sub summary_delta_score ($old, $new) {
  my $score = 0;

  # Specfile license change
  $score += 1000 if $new->{specfile} ne $old->{specfile};

  # New snippet matches
  my $new_snippets = _new_snippets($old, $new);
  $score += 10 * keys %$new_snippets;

  # New licenses
  my $new_licenses = _new_licenses($old, $new);
  $score += 10 * $new_licenses->{$_} for keys %$new_licenses;

  # License incompatibilities
  $score += 500 for _new_incompatibilities($old, $new);

  return $score;
}

sub _new_incompatibilities ($old, $new) {
  my @old_incompat = map { @{$_->{licenses}} } @{$old->{incompatible_licenses} || []};
  my @new_incompat = uniq(map { @{$_->{licenses}} } @{$new->{incompatible_licenses} || []});
  my %old          = map { $_ => 1 } @old_incompat;

  my @new;
  for my $lic (@new_incompat) {
    push @new, $lic unless $old{$lic};
  }

  return @new;
}

sub _new_licenses ($old, $new) {
  my %old_licenses = map { $_ => 1 } keys %{$old->{licenses} || {}};

  my %new_licenses;
  for my $lic (keys %{$new->{licenses}}) {
    $new_licenses{$lic} ||= $new->{licenses}{$lic} unless $old_licenses{$lic};
  }
  return \%new_licenses;
}

sub _new_snippets ($old, $new) {
  my $new_snippets = $new->{missed_snippets};
  my %old_snippets = map { $_ => 1 } map { @{$_} } values %{$old->{missed_snippets} || {}};

  my %files_with_new_snippets;
  for my $file (sort keys %$new_snippets) {
    for my $snippet (@{$new_snippets->{$file}}) {
      $files_with_new_snippets{$snippet} ||= $file unless $old_snippets{$snippet};
    }
  }
  return \%files_with_new_snippets;
}

1;
