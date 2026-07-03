# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package Cavil::Bom::Detector::Pypi;
use Mojo::Base -base, -signatures;

# An installed Python distribution ships RFC822-style metadata
sub files ($self) { return (qr{(?:^|/)[^/]+\.(?:dist-info|egg-info)/(?:METADATA|PKG-INFO)$}) }

sub parse ($self, $path, $content) {
  my (%header, @classifiers);
  for my $line (split /\n/, $$content) {
    $line =~ s/\r$//;
    last if $line eq '';    # headers end at the first blank line (body is the long description)
    next unless $line =~ /^([A-Za-z][A-Za-z-]*):\s*(.*?)\s*$/;
    my ($key, $value) = (lc $1, $2);
    if ($key eq 'classifier') { push @classifiers, $value }
    else                      { $header{$key} //= $value }
  }

  my ($name, $version) = ($header{name}, $header{version});
  return [] unless defined $name && length $name && defined $version && length $version;

  # Prefer the License field; fall back to an OSI Approved classifier
  my $license = $header{license};
  undef $license if defined $license && ($license eq '' || uc $license eq 'UNKNOWN');
  unless (defined $license) {
    for my $classifier (@classifiers) {
      if ($classifier =~ /^License\s*::.*::\s*(.+)$/) { $license = $1; last }
    }
  }

  (my $normalized = lc $name) =~ s/[-_.]+/-/g;    # PyPI-normalized name for the purl
  return [
    {
      type    => 'pypi',
      name    => $name,
      version => $version,
      purl    => "pkg:pypi/$normalized\@$version",
      license => $license,
      source  => $path
    }
  ];
}

1;
