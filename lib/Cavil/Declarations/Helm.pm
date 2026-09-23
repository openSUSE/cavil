# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package Cavil::Declarations::Helm;
use Mojo::Base -base, -signatures;

use Cavil::Util qw(legal_review_notices);
use YAML::XS    qw(Load);

sub file   ($self) {qr{(?:^|/)Chart\.yaml$}}
sub format ($self) {'helm'}

sub parse ($self, $file) {
  my $content = $file->slurp;
  my $info    = {notices => legal_review_notices($content)};
  ($info->{license}) = $content =~ /^\s*#\s*SPDX-License-Identifier\s*:\s*(.+)$/m;

  my $chart = eval { Load($content) };
  @$info{qw(name version summary url)} = @$chart{qw(name version description home)} if ref $chart eq 'HASH';

  return $info;
}

1;
