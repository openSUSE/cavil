# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package Cavil::Declarations::Kiwi;
use Mojo::Base -base, -signatures;

use Mojo::DOM;

sub file   ($self) {qr/\.kiwi$/}
sub format ($self) {'kiwi'}

sub parse ($self, $file) {
  my $dom   = Mojo::DOM->new($file->slurp);
  my $text  = sub ($selector) { my $e = $dom->at($selector); $e ? $e->text : undef };
  my $label = $dom->at('label[name="org.opencontainers.image.licenses"][value]');
  return {
    name    => $dom->at('image[name]') ? $dom->at('image')->{name} : undef,
    version => $text->('image preferences version'),
    license => $label ? $label->{value} : undef,
    summary => $text->('image description specification'),
    url     => $text->('image description contact')
  };
}

1;
