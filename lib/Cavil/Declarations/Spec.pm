# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package Cavil::Declarations::Spec;
use Mojo::Base -base, -signatures;

use Cavil::Util qw(expand_spec_macros legal_review_notices);

sub file   ($self) {qr/\.spec$/}
sub format ($self) {'spec'}

# A subpackage license that differs from the main one is a declaration of its own (main GPL, library LGPL), named
# after the first subpackage carrying it
sub parse ($self, $file) {
  my $content = expand_spec_macros($file->slurp);
  my $main    = {'%doc' => [], '%license' => [], notices => legal_review_notices($content)};
  my ($current, @subs) = ($main);
  for my $line (split "\n", $content) {
    if ($line =~ /^%package\s+(-n\s+)?(\S+)/) {
      push @subs, $current = {name => $1 ? $2 : ($main->{name} // '') . "-$2"};
    }
    elsif ($line =~ /^License:\s*(.+)$/)                { $current->{license} //= $1 }
    elsif ($line =~ /^%(doc|license)\s+(.+)$/)          { push @{$main->{"%$1"}}, split ' ', $2 }
    elsif ($current != $main)                           {next}
    elsif ($line =~ /^(Name|Version|Summary):\s*(.+)$/) { $main->{lc $1} //= $2 }
    elsif ($line =~ /^Url:\s*(.+)$/i)                   { $main->{url}   //= $1 }
  }

  my %seen = (($main->{license} // '') => 1);
  return ($main, grep { defined $_->{license} && !$seen{$_->{license}}++ } @subs);
}

1;
