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
  my $purl = "pkg:npm/$name";
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

  my @components;
  for my $entry (@entries) {
    next unless defined $entry->{name} && length $entry->{name};

    my $dep_dir = $manifest_dir->child('node_modules', split(m{/}, $entry->{name}));
    my $present = -d $dep_dir ? 1 : 0;

    next if $entry->{is_dev} && !$present;

    if ($present && (!defined $entry->{license} || $entry->{license} eq '')) {
      $entry->{license} = $self->_license_from_pkg($dep_dir->child('package.json'));
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

sub _from_packages ($self, $packages) {
  my @entries;
  for my $key (sort keys %$packages) {
    next if $key eq '';
    my $entry = $packages->{$key};
    next unless ref $entry eq 'HASH';

    my $name = $entry->{name};
    unless (defined $name && length $name) {
      if   ($key =~ m{(?:^|/)node_modules/(.+)$}) { $name = $1 }
      else                                        { $name = $key }
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

sub _license_from_pkg ($self, $pkg_json) {
  return undef unless -e $pkg_json;
  my $data = eval { decode_json(path($pkg_json)->slurp) };
  return undef unless ref $data eq 'HASH';
  return _normalize_license($data->{license});
}

sub _normalize_license ($value) {
  return undef  unless defined $value;
  return $value unless ref $value;
  return $value->{type} if ref $value eq 'HASH' && defined $value->{type};
  return join(' OR ', grep {defined} map { _normalize_license($_) } @$value) if ref $value eq 'ARRAY';
  return undef;
}

1;
