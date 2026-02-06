# Copyright (C) 2024 SUSE LLC
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

package Cavil::Controller::APIKeys;
use Mojo::Base 'Mojolicious::Controller', -signatures;

sub create ($self) {
  my $validation = $self->validation;
  $validation->optional('description');
  $validation->required('type')->in(qw(read-only read-write));
  $validation->required('expires')->like(qr/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$/);
  return $self->reply->json_validation_error if $validation->has_error;

  my $owner   = $self->users->id_for_login($self->current_user);
  my $api_key = $self->api_keys->create(
    owner       => $owner,
    description => $validation->param('description'),
    type        => $validation->param('type'),
    expires     => $validation->param('expires')
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
  $self->render(json => {removed => $removed});
}

1;
