# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package Cavil::Bom::Detector::Go;
use Mojo::Base -base, -signatures;

# One file reliably enumerates the vendored tree.
sub files ($self) { return (qr{(?:^|/)vendor/modules\.txt$}) }

# Unlike a package manifest (package.json, Cargo.toml, ...), this file does not describe the package it
# sits in - it lists *other* vendored modules. So it is never the primary artifact under review and must
# be read even when it sits at the source root (where a package manifest would be skipped as the root).
sub lists_dependencies ($self) {1}

sub parse ($self, $path, $content) {
  my @components;
  for my $line (split /\n/, $$content) {

    # Prefer versioned replacement identity because its code is vendored.
    next unless $line =~ /^#\s+(\S+)\s+(v\S+)(?:\s+=>\s+(\S+)\s+(v\S+))?/;
    my ($module, $version) = defined $3 ? ($3, $4) : ($1, $2);
    push @components,
      {
      type    => 'golang',
      name    => $module,
      version => $version,
      purl    => "pkg:golang/$module\@$version",
      license => undef,
      source  => $path
      };
  }

  return \@components;
}

1;
