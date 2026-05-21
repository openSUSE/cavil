# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package Cavil::Components::Detector::NPM;
use Mojo::Base 'Cavil::Components::Detector', -signatures;

use Mojo::File qw(path);
use Mojo::JSON qw(decode_json);

sub ecosystem         ($self) {'npm'}
sub manifest_patterns ($self) { [qr/^package-lock\.json$/] }

sub purl ($self, $component) {

  # Scope's leading "@" is URL-encoded per the purl-spec npm rules;
  # the version separator "@" stays raw.
  my $name = $component->{name};
  $name =~ s/\@/%40/g;
  my $purl    = "pkg:npm/$name";
  my $version = $component->{version};
  $purl .= "\@$version" if defined $version && length $version;
  return $purl;
}

sub detect ($self, $manifest_abs, $unpacked_root, $manifest_rel) {
  my $data = eval { decode_json(path($manifest_abs)->slurp) };
  if (my $err = $@) {
    $self->log->warn("[components/npm] Failed to parse $manifest_rel: $err") if $self->log;
    return [];
  }
  return [] unless ref $data eq 'HASH';

  my $manifest_dir = path($manifest_abs)->dirname;
  my $version      = $data->{lockfileVersion} // 1;

  my @entries;
  if ($version >= 2 && ref $data->{packages} eq 'HASH') {
    @entries = $self->_from_packages($data->{packages});
  }
  elsif (ref $data->{dependencies} eq 'HASH') {
    @entries = $self->_from_dependencies_v1($data->{dependencies});
  }

  # Build a content-based index once per manifest. This lets us match
  # lockfile entries against any on-disk layout: standard node_modules/,
  # OBS cpio->tgz (where each .tgz lands as <tarball-name>/package/),
  # pnpm flat stores, etc. The lockfile is the source of truth for which
  # components belong; the index is purely enrichment.
  my $index = $self->_build_package_index($manifest_dir);

  # npm hoisting/nesting means the same name+version can appear at multiple
  # lockfile keys (top-level + nested transitive); collapse to one row each.
  my %seen;
  my @components;
  for my $entry (@entries) {
    next unless defined $entry->{name} && length $entry->{name};
    my $key = ($entry->{name} // '') . "\@" . ($entry->{version} // '');
    next if $seen{$key}++;

    my $hit = $self->_index_lookup($index, $entry->{name}, $entry->{version});
    my $present = $hit ? 1 : 0;

    next if $entry->{is_dev} && !$present;

    if ($hit && (!defined $entry->{license} || $entry->{license} eq '')) {
      $entry->{license} = $hit->{license};
    }

    push @components,
      {
      name       => $entry->{name},
      version    => $entry->{version},
      license    => $entry->{license},
      source_url => $entry->{source_url},
      checksum   => $entry->{checksum},
      is_dev     => $entry->{is_dev} ? 1 : 0,
      present    => $present,
      relation   => 'CONTAINS'
      };
  }

  return \@components;
}

# Defensive ceiling: refuse to keep collecting if a tree is pathologically large
use constant _MAX_PACKAGE_JSON => 50_000;

sub _build_package_index ($self, $root) {
  my %by_nv;
  my %by_name;
  my $count = 0;

  for my $file (@{$root->list_tree}) {
    next unless -f $file && $file->basename eq 'package.json';
    if (++$count > _MAX_PACKAGE_JSON) {
      $self->log->warn("[components/npm] package.json count exceeded ceiling at $root, truncating index")
        if $self->log;
      last;
    }

    my $data = eval { decode_json($file->slurp) };
    next unless ref $data eq 'HASH';
    my $name = $data->{name};
    next unless defined $name && length $name;
    my $version = $data->{version};
    my $license = _normalize_license($data->{license});

    my $record = {dir => $file->dirname, license => $license};
    if (defined $version && length $version) {
      $by_nv{"$name\@$version"} //= $record;
    }
    push @{$by_name{$name}}, $record;
  }

  return {by_nv => \%by_nv, by_name => \%by_name};
}

sub _index_lookup ($self, $index, $name, $version) {
  if (defined $version && length $version) {
    return $index->{by_nv}{"$name\@$version"};
  }
  my $matches = $index->{by_name}{$name};
  return $matches && @$matches ? $matches->[0] : undef;
}

sub _from_packages ($self, $packages) {
  my @entries;
  for my $key (sort keys %$packages) {
    next if $key eq '';
    my $entry = $packages->{$key};
    next unless ref $entry eq 'HASH';

    # Workspace entries (no node_modules/ segment) are first-party sources, not vendored deps
    next unless $key =~ m{(?:^|/)node_modules/};

    # Name is the segment after the LAST "node_modules/" so nested
    # transitive deps like "node_modules/a/node_modules/b" yield "b", and
    # scoped names like "node_modules/@scope/foo" yield "@scope/foo".
    my $name = $entry->{name};
    unless (defined $name && length $name) {
      ($name) = $key =~ m{.*node_modules/(.+)$};
    }

    push @entries,
      {
      name       => $name,
      version    => $entry->{version},
      license    => _normalize_license($entry->{license}),
      source_url => $entry->{resolved},
      checksum   => $entry->{integrity},
      is_dev     => $entry->{dev} ? 1 : 0
      };
  }
  return @entries;
}

sub _from_dependencies_v1 ($self, $deps, $entries = []) {
  for my $name (sort keys %$deps) {
    my $entry = $deps->{$name};
    next unless ref $entry eq 'HASH';

    push @$entries,
      {
      name       => $name,
      version    => $entry->{version},
      license    => _normalize_license($entry->{license}),
      source_url => $entry->{resolved},
      checksum   => $entry->{integrity},
      is_dev     => $entry->{dev} ? 1 : 0
      };

    $self->_from_dependencies_v1($entry->{dependencies}, $entries) if ref $entry->{dependencies} eq 'HASH';
  }
  return @$entries;
}

sub _normalize_license ($value) {
  return undef  unless defined $value;
  return $value unless ref $value;
  return $value->{type} if ref $value eq 'HASH' && defined $value->{type};
  return join(' OR ', grep {defined} map { _normalize_license($_) } @$value) if ref $value eq 'ARRAY';
  return undef;
}

1;
