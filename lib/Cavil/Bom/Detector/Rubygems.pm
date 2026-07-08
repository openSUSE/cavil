# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package Cavil::Bom::Detector::Rubygems;
use Mojo::Base -base, -signatures;

# Two canonical vendored layouts:
#   1. an installed spec, ".../specifications/<name>-<version>.gemspec" (gem/bundle install)
#   2. a cached gem, ".../<name>-<version>/metadata" (bundle cache, after Cavil unpacks the .gem, which
#      drops the extension; "metadata" is a YAML gemspec). The generic "metadata" filename is confirmed by
#      the Gem::Specification content signature in parse(), so unrelated "metadata" files are ignored.
sub files ($self) {
  return (qr{(?:^|/)specifications/[^/]+\.gemspec$}, qr{(?:^|/)metadata$});
}

sub parse ($self, $path, $content) {

  # Installed gemspec: RubyGems always names the file "<name>-<version>.gemspec", which is the reliable
  # identity (the body is executable Ruby). Licence is best-effort from the body.
  if ($path =~ m{(?:^|/)([^/]+)\.gemspec$}) {
    my ($name, $version) = _split_stem($1);
    return _component($name, $version, _gemspec_license($content), $path);
  }

  # Cached gem metadata is a YAML gemspec; take identity from its content (path naming after unpack is not
  # guaranteed) and only trust files that really are a gem specification
  if ($$content =~ /Gem::Specification/) {
    my ($name)    = $$content =~ /^name:\s*(\S+)/m;
    my ($version) = $$content =~ m{^version:\s*!ruby/object:Gem::Version\s*\n\s*version:\s*["']?([^"'\s]+)}m;
    return _component($name, $version, _yaml_license($content), $path);
  }

  return [];
}

# Split "<name>-<version>" where the version is the first digit-led trailing segment (handles hyphenated
# gem names like "net-http" and platform suffixes like "1.13.0-x86_64-linux")
sub _split_stem ($stem) { return $stem =~ m{^(.+?)-([0-9][^/]*)$} ? ($1, $2) : (undef, undef) }

sub _component ($name, $version, $license, $path) {
  return [] unless defined $name && length $name && defined $version && length $version;
  return [
    {
      type    => 'gem',
      name    => $name,
      version => $version,
      purl    => "pkg:gem/$name\@$version",
      license => $license,
      source  => $path
    }
  ];
}

# gemspec body: s.license = "MIT"  or  s.licenses = ["MIT", "Apache-2.0"]
sub _gemspec_license ($content) {
  return undef unless $$content =~ /\.licenses?\s*=\s*(\[[^\]]*\]|["'][^"']*["'])/;
  my @ids = $1 =~ /["']([^"']+)["']/g;
  return @ids ? join(' OR ', @ids) : undef;
}

# gem metadata (YAML): "licenses:\n- MIT\n- Apache-2.0"  or  "licenses: []"  or  "license: MIT"
sub _yaml_license ($content) {
  if ($$content =~ /^licenses:\s*\n((?:[ \t]*-[ \t]*\S.*\n?)+)/m) {
    my @ids = $1 =~ /-[ \t]*["']?([^"'\n]+?)["']?\s*$/mg;
    return @ids ? join(' OR ', @ids) : undef;
  }
  if ($$content =~ /^licenses?:[ \t]*(\S[^\n]*?)\s*$/m) {
    my $v = $1;
    return undef if $v eq '[]';
    $v =~ s/^["']|["']$//g;
    return length $v ? $v : undef;
  }
  return undef;
}

1;
