# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package Cavil::Controller::Search;
use Mojo::Base 'Mojolicious::Controller', -signatures;

sub search ($self) {
  my $validation = $self->validation;
  $validation->optional('q');
  return $self->reply->json_validation_error if $validation->has_error;

  $self->render('search/results');
}

sub autocomplete ($self) {
  my $validation = $self->validation;
  $validation->optional('q');
  return $self->reply->json_validation_error if $validation->has_error;

  my $suggestions = [];
  if (defined(my $query = $validation->param('q'))) {
    $suggestions = $self->packages->name_autocomplete($query);
  }

  $self->render(json => $suggestions);
}

1;
