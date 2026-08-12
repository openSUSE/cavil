# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package Cavil::Bom::Detector::Rubygems;
use Mojo::Base -base, -signatures;

# Verify generic metadata filenames by content to avoid unrelated files.
sub files ($self) {

  # Match both installed and built-in runtime gems.
  return (qr{(?:^|/)specifications/(?:default/)?[^/]+\.gemspec$}, qr{(?:^|/)metadata$});
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

# A digit-led version disambiguates hyphenated names.
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

sub _gemspec_license ($content) {
  return undef unless $$content =~ /\.licenses?\s*=\s*(\[[^\]]*\]|["'][^"']*["'])/;
  my @ids = $1 =~ /["']([^"']+)["']/g;
  return @ids ? join(' OR ', @ids) : undef;
}

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
