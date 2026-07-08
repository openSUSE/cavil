# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package Cavil::Bom::Registry;
use Mojo::Base -base, -signatures;

use Cavil::Bom::Detector::Npm;
use Cavil::Bom::Detector::Cargo;
use Cavil::Bom::Detector::Pypi;
use Cavil::Bom::Detector::Maven;
use Cavil::Bom::Detector::Go;
use Cavil::Bom::Detector::Composer;
use Cavil::Bom::Detector::Nuget;
use Cavil::Bom::Detector::Rubygems;

# One detector per ecosystem; adding an ecosystem is a new module plus a line here
has detectors => sub ($self) {
  [
    Cavil::Bom::Detector::Npm->new,   Cavil::Bom::Detector::Cargo->new, Cavil::Bom::Detector::Pypi->new,
    Cavil::Bom::Detector::Maven->new, Cavil::Bom::Detector::Go->new,    Cavil::Bom::Detector::Composer->new,
    Cavil::Bom::Detector::Nuget->new, Cavil::Bom::Detector::Rubygems->new
  ];
};

# Flat list of [path-regex, detector] pairs, built once from the detectors' file patterns
has _matchers => sub ($self) {
  my @matchers;
  for my $detector (@{$self->detectors}) { push @matchers, [$_, $detector] for $detector->files }
  return \@matchers;
};

# Cheap check for the per-file indexing loop: does this path look like a component metadata file?
sub matches ($self, $path) {
  $path =~ $_->[0] and return 1 for @{$self->_matchers};
  return 0;
}

# Does this path match a *package manifest* that describes the component in its own directory (as opposed
# to a listing file that enumerates other modules, like Go's vendor/modules.txt)? Only such a manifest is
# the primary artifact when it sits at the source root, so only these are skipped there.
sub is_self_manifest ($self, $path) {
  for my $matcher (@{$self->_matchers}) {
    next unless $path =~ $matcher->[0];
    my $detector = $matcher->[1];
    return $detector->can('lists_dependencies') && $detector->lists_dependencies ? 0 : 1;
  }
  return 0;
}

# Parse one file's content into components (empty list on no match or parse failure). Broken metadata
# files are expected in the wild (bad encoding, truncated, wrong types, huge blobs), so every result is
# both parse-guarded and sanitized before it can reach the database.
sub detect_file ($self, $path, $content) {
  for my $matcher (@{$self->_matchers}) {
    next unless $path =~ $matcher->[0];
    my $components = eval { $matcher->[1]->parse($path, $content) };
    return [] unless ref $components eq 'ARRAY';
    return [grep {defined} map { _sanitize($_) } @$components];
  }
  return [];
}

# Reject a component whose identity fields are unusable (non-scalar, absurdly long, or containing control
# characters); a bad *license* only drops the license, not the whole component
sub _sanitize ($component) {
  return undef unless ref $component eq 'HASH';

  for my $field (qw(name version purl type)) {
    next unless defined $component->{$field};
    return undef
      if ref $component->{$field} || length $component->{$field} > 512 || $component->{$field} =~ /[\x00-\x1f]/;
  }
  return undef unless defined $component->{name} && length $component->{name};
  return undef unless defined $component->{purl} && length $component->{purl};

  my $license = $component->{license};
  $component->{license} = undef
    if defined $license && (ref $license || length $license > 512 || $license =~ /[\x00-\x1f]/);

  return $component;
}

1;
