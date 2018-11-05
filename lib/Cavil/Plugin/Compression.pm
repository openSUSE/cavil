# Copyright (C) 2018 SUSE Linux GmbH
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, see <http://www.gnu.org/licenses/>.

package Cavil::Plugin::Compression;
use Mojo::Base 'Mojolicious::Plugin';

use IO::Compress::Gzip 'gzip';

sub register {
  my ($self, $app) = @_;

  $app->hook(after_render => \&_gzip);
}

sub _gzip {
  my ($c, $output, $format) = @_;

  return unless $c->stash->{gzip};

  return unless ($c->req->headers->accept_encoding // '') =~ /gzip/i;
  $c->res->headers->append(Vary => 'Accept-Encoding');

  $c->res->headers->content_encoding('gzip');
  gzip $output, \my $compressed;
  $$output = $compressed;
}

1;
