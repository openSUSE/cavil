# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package Cavil::Components::Detector;
use Mojo::Base -base, -signatures;

has 'log';

sub ecosystem         ($self) { die 'ecosystem() must be implemented by subclass' }
sub manifest_patterns ($self) { die 'manifest_patterns() must be implemented by subclass' }

sub matches_manifest ($self, $rel_path) {
  my @parts    = split m{/}, $rel_path;
  my $basename = $parts[-1];
  for my $re (@{$self->manifest_patterns}) {
    return 1 if $basename =~ $re;
  }
  return 0;
}

sub detect ($self, $manifest_abs, $unpacked_root, $manifest_rel) {
  die 'detect() must be implemented by subclass';
}

sub purl ($self, $component) { die 'purl() must be implemented by subclass' }

1;
