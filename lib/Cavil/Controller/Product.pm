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

use Mojo::JSON qw(to_json);

sub list ($self) {
  $self->render;
}

sub show ($self) {
  my $name     = $self->stash('name');
  my $products = $self->products;

  # A page is annotatable only when its name is an actual codestream (a bot_products row), not a curated
  # product group that aggregates several codestreams; prefill the control with the current annotation.
  # When it is a group, hand the curator the member codestreams so they can drill back down to any of them
  my $codestream = $products->find($name);
  $self->render(
    can_curate => $self->current_user_can('curate') ? 1                              : 0,
    codestream => $codestream                       ? 1                              : 0,
    annotation => $codestream                       ? ($codestream->{product} // '') : '',
    members    => to_json($products->codestreams_for_product($name))
  );
}

# Curator-only: attach the current codestream to a human product name (or clear it with an empty value)
sub set_annotation ($self) {
  my $name    = $self->stash('name');
  my $product = $self->products->set_annotation($name, scalar $self->param('product'));
  $self->render(json => {product => $product});
}

1;
