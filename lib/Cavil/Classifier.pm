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

package Cavil::Classifier;
use Mojo::Base -base;

use Carp 'croak';
use Mojo::UserAgent;

has ua => sub { Mojo::UserAgent->new(inactivity_timeout => 600) };
has 'url';

sub classify {
  my ($self, $text) = @_;
  croak 'No classifier configured' unless my $url = $self->url;
  return $self->ua->post($url => json => $text)->result->json;
}

1;
