# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package Cavil::Declarations::ObsPrj;
use Mojo::Base -base, -signatures;

use Cavil::Util qw(decode_json_fast);

sub file   ($self) {qr{(?:^|/)workflow\.config$}}
sub format ($self) {'obsprj'}

sub parse ($self, $file) {
  my $config = eval { decode_json_fast($file->slurp) };
  return () unless ref $config eq 'HASH' && exists $config->{Workflows} && exists $config->{GitProjectName};
  return {};
}

1;
