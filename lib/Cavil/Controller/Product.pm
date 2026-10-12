# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package Cavil::Controller::Product;
use Mojo::Base 'Mojolicious::Controller', -signatures;

use Mojo::JSON qw(to_json);

sub list ($self) {
  $self->render;
}

sub show ($self) {
  my $name     = $self->stash('name');
  my $products = $self->products;

  # Only raw codestreams are annotatable; curated groups expose their members instead.
  my $codestream = $products->find($name);
  $self->render(
    can_curate => $self->current_user_can('curate') ? 1                               : 0,
    codestream => $codestream                       ? 1                               : 0,
    annotation => $codestream                       ? ($codestream->{product} // '')  : '',
    priority   => $codestream                       ? ($codestream->{priority} // '') : '',
    members    => to_json($products->codestreams_for_product($name))
  );
}

# Curator-only: attach the current codestream to a human product name (or clear it with an empty value)
sub set_annotation ($self) {
  my $validation = $self->validation;
  $validation->optional('priority', 'not_empty')->like(qr/^([1-9]|10)$/);
  return $self->reply->json_validation_error if $validation->has_error;

  my $name     = $self->stash('name');
  my $priority = $validation->param('priority');
  my $product  = $self->products->set_annotation($name, scalar $self->param('product'), $priority);
  $self->render(json => {product => $product, priority => $priority});
}

1;
