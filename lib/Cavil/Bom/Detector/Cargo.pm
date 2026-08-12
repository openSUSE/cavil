# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package Cavil::Bom::Detector::Cargo;
use Mojo::Base -base, -signatures;

sub files ($self) { return (qr{(?:^|/)Cargo\.toml$}) }

sub parse ($self, $path, $content) {

  # Workspace manifests have no package table and are skipped.
  my ($in_package, %field);
  for my $line (split /\n/, $$content) {
    if ($line =~ /^\s*\[([^\]]+)\]/) { $in_package = $1 eq 'package'; next }
    next unless $in_package;
    $field{$1} //= $2 if $line =~ /^\s*(name|version|license)\s*=\s*"([^"]*)"/;
  }

  my ($name, $version) = ($field{name}, $field{version});
  return [] unless defined $name && length $name && defined $version && length $version;

  return [
    {
      type    => 'cargo',
      name    => $name,
      version => $version,
      purl    => "pkg:cargo/$name\@$version",
      license => $field{license},
      source  => $path
    }
  ];
}

1;
