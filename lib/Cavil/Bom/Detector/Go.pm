# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package Cavil::Bom::Detector::Go;
use Mojo::Base -base, -signatures;

# Go vendors source and lists every vendored module (with its version) in vendor/modules.txt; one file
# enumerates the whole vendored tree
sub files ($self) { return (qr{(?:^|/)vendor/modules\.txt$}) }

sub parse ($self, $path, $content) {
  my @components;
  for my $line (split /\n/, $$content) {

    # Module entries look like "# module/path v1.2.3"; a "=> replacement v2" directive means the
    # replacement's code is what is actually vendored, so prefer its identity ("=> ./local" replacements
    # keep the original module path, which is where the forked code is vendored). "## explicit" lines and
    # blank/comment lines are skipped.
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
