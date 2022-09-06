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

package Cavil::Controller::Product;
use Mojo::Base 'Mojolicious::Controller', -signatures;

sub list ($self) {
  $self->render(products => $self->products->all);
}

sub list_packages_ajax ($self) {
  my $packages = $self->products->list($self->stash('name'));
  my $data = {data => $packages, recordsTotal => scalar(@$packages), recordsFiltered => scalar(@$packages), draw => 1};
  $self->render(json => $data);
}

sub show ($self) {
  $self->render;
}

1;
