# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package Cavil::Declarations::Debian;
use Mojo::Base -base, -signatures;

# The copyright file is the license evidence, the rest comes from its siblings
sub file   ($self) {qr{(?:^|/)debian/copyright$}}
sub format ($self) {'debian'}

sub parse ($self, $file) {
  my $info = {};
  ($info->{license}) = $file->slurp =~ /^License:\s*(.+)$/m;

  my $control = $file->sibling('control');
  if (-f $control) {
    my $content = $control->slurp;
    ($info->{name}) = $content =~ /^Source:\s*(.+)$/m;
    ($info->{url})  = $content =~ /^Homepage:\s*(.+)$/m;
  }

  my $changelog = $file->sibling('changelog');
  ($info->{version}) = $changelog->slurp =~ /\A\S+\s+\(([^)]+)\)/ if -f $changelog;

  return $info;
}

1;
