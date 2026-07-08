# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package Cavil::Bom::Detector::Composer;
use Mojo::Base -base, -signatures;

use Mojo::JSON qw(decode_json);

# "composer install" records every installed PHP package in vendor/composer/installed.json, so its presence
# means the packages are physically vendored. This is the safe source (unlike composer.lock, which sits at
# the project root even when nothing is vendored).
sub files ($self) { return (qr{(?:^|/)vendor/composer/installed\.json$}) }

# The file lists other packages, not the package it lives in, so it is never the primary artifact and must
# be read even when it sits near the source root (mirrors Go's vendor/modules.txt)
sub lists_dependencies ($self) {1}

sub parse ($self, $path, $content) {
  my $json = eval { decode_json($$content) };

  # Composer 2 wraps the list in a "packages" key; Composer 1 is a bare top-level array
  my $packages = ref $json eq 'HASH' ? $json->{packages} : $json;
  return [] unless ref $packages eq 'ARRAY';

  my @components;
  for my $pkg (@$packages) {
    next unless ref $pkg eq 'HASH';
    my ($name, $version) = ($pkg->{name}, $pkg->{version});
    next if ref $name || ref $version;
    next unless defined $name && length $name && defined $version && length $version;

    push @components,
      {
      type    => 'composer',
      name    => "$name",
      version => "$version",
      purl    => "pkg:composer/$name\@$version",
      license => _license($pkg->{license}),
      source  => $path
      };
  }

  return \@components;
}

# Composer stores licences as an array of SPDX-ish identifiers
sub _license ($license) {
  return undef unless ref $license eq 'ARRAY';
  my @ids = grep { defined && !ref && length } @$license;
  return @ids ? join(' OR ', @ids) : undef;
}

1;
