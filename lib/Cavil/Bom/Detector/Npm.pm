# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package Cavil::Bom::Detector::Npm;
use Mojo::Base -base, -signatures;

use Mojo::JSON qw(decode_json);

# npm ships a self-describing "package.json" inside every installed module
sub files ($self) { return (qr{(?:^|/)package\.json$}) }

sub parse ($self, $path, $content) {
  my $json = eval { decode_json($$content) };
  return [] unless ref $json eq 'HASH';

  # gx (an IPFS-era package manager) reuses the "package.json" filename to describe Go and other non-npm
  # modules, adding a "gx"/"gxVersion" block and a "language" field that a real npm manifest never carries.
  # Without this guard a vendored Go module like vendor/github.com/blang/semver/package.json is misreported
  # as an npm component.
  return [] if defined $json->{gx} || defined $json->{gxVersion};
  return [] if defined $json->{language} && lc "$json->{language}" ne 'javascript';

  # A real module always has both; a bare config/tsconfig-style file does not. Malformed metadata may
  # carry non-scalar name/version (e.g. "name": {...}); reject those rather than stringify a ref.
  my ($name, $version) = ($json->{name}, $json->{version});
  return [] if ref $name || ref $version;
  return [] unless defined $name && length $name && defined $version && length $version;

  return [
    {
      type    => 'npm',
      name    => "$name",
      version => "$version",
      purl    => _purl($name, $version),
      license => _license($json),
      source  => $path
    }
  ];
}

sub _license ($json) {
  my $license = $json->{license};
  return "$license" if defined $license && !ref $license && length $license;
  return $license->{type} if ref $license eq 'HASH' && $license->{type};

  # Legacy "licenses": [{type => "MIT"}, ...]
  if (ref $json->{licenses} eq 'ARRAY') {
    my @types = grep { defined && length } map { ref $_ eq 'HASH' ? $_->{type} : $_ } @{$json->{licenses}};
    return join ' OR ', @types if @types;
  }

  return undef;
}

sub _purl ($name, $version) {

  # Scoped packages ("@scope/name") keep the scope as an encoded namespace
  my $encoded = $name =~ m{^@([^/]+)/(.+)$} ? "%40$1/$2" : $name;
  return "pkg:npm/$encoded\@$version";
}

1;
