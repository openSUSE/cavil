# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package Cavil::Controller::CodeSearch;
use Mojo::Base 'Mojolicious::Controller', -signatures;

sub index ($self) {
  return $self->reply->not_found unless $self->codesearch;
  $self->render;
}

sub search ($self) {
  return $self->render(json => {error => 'Code search is not enabled'}, status => 404) unless $self->codesearch;

  my $v = $self->validation;
  $v->required('snippet');
  $v->optional('limit')->num;
  $v->optional('offset')->num;
  return $self->reply->json_validation_error if $v->has_error;

  my $limit = $v->param('limit') // 10;
  $limit = 100 if $limit > 100;
  $limit = 1   if $limit < 1;
  my $offset = $v->param('offset') // 0;
  $offset = 0 if $offset < 0;

  $self->render(json => $self->fingerprints->search(scalar $v->param('snippet'), $limit, $offset));
}

1;
