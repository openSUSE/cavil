# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package Cavil::Controller::APIKeys;
use Mojo::Base 'Mojolicious::Controller', -signatures;

sub create ($self) {
  my $validation = $self->validation;
  $validation->optional('description');
  $validation->required('type')->in(qw(read-only read-write));
  $validation->required('expires')->like(qr/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$/);
  $validation->optional('can_finalize_reviews')->in('0', '1');
  return $self->reply->json_validation_error if $validation->has_error;

  my $owner   = $self->users->id_for_login($self->current_user);
  my $api_key = $self->api_keys->create(
    owner                => $owner,
    description          => $validation->param('description'),
    type                 => $validation->param('type'),
    can_finalize_reviews => ($validation->param('can_finalize_reviews') // '0') eq '1' ? 1 : 0,
    expires              => $validation->param('expires')
  );

  $self->render(json => {created => $api_key->{id}});
}

sub list ($self) {
  $self->render('api_keys/list');
}

sub list_meta ($self) {
  my $owner_id = $self->users->id_for_login($self->current_user);
  my $keys     = $self->api_keys->list($owner_id);
  $self->render(json => {keys => $keys});
}

sub remove ($self) {
  my $api_key_id = $self->param('id');
  my $owner_id   = $self->users->id_for_login($self->current_user);
  my $removed    = $self->api_keys->remove($api_key_id, $owner_id);
  $self->render(json => {removed => $removed ? 1 : 0});
}

1;
