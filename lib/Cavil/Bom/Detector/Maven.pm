# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package Cavil::Bom::Detector::Maven;
use Mojo::Base -base, -signatures;

# A built JAR embeds Maven coordinates in META-INF/maven/<group>/<artifact>/pom.properties (the license
# lives in the sibling pom.xml, so it is left to Cavil's own detection to backfill)
sub files ($self) { return (qr{(?:^|/)META-INF/maven/.+/pom\.properties$}) }

sub parse ($self, $path, $content) {
  my %field;
  for my $line (split /\n/, $$content) {
    $field{$1} = $2 if $line =~ /^\s*(groupId|artifactId|version)\s*=\s*(.+?)\s*$/;
  }

  my ($group, $artifact, $version) = @field{qw(groupId artifactId version)};
  return []
    unless defined $group
    && length $group
    && defined $artifact
    && length $artifact
    && defined $version
    && length $version;

  return [
    {
      type    => 'maven',
      name    => "$group:$artifact",
      version => $version,
      purl    => "pkg:maven/$group/$artifact\@$version",
      license => undef,
      source  => $path
    }
  ];
}

1;
