# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package Cavil::Controller::CommentTemplates;
use Mojo::Base 'Mojolicious::Controller', -signatures;

sub add ($self) {
  my $validation = $self->validation;
  $validation->required('name');
  $validation->required('body');
  return $self->reply->json_validation_error if $validation->has_error;

  my $templates = $self->comment_templates;
  my $name      = $validation->param('name');
  return $self->render(json => {error => 'Comment template already exists'}, status => 400)
    if defined $templates->find_name($name);

  my $id = $templates->add($name, $validation->param('body'), $self->current_user);

  return $self->render(json => {id => $id});
}

# Not gated on "curate", managers write review comments too and need the picker
sub all ($self) {
  return $self->render(json => $self->comment_templates->all);
}

sub list ($self) {
  $self->render('comment_templates/list');
}

sub remove ($self) {
  return $self->render(json => {error => 'Comment template does not exist'}, status => 400)
    unless $self->comment_templates->remove($self->param('id'), $self->current_user);
  return $self->render(json => 'ok');
}

sub update ($self) {
  my $validation = $self->validation;
  $validation->required('name');
  $validation->required('body');
  return $self->reply->json_validation_error if $validation->has_error;

  my $templates = $self->comment_templates;
  my $id        = $self->param('id');
  my $name      = $validation->param('name');
  my $conflict  = $templates->find_name($name);
  return $self->render(json => {error => 'Comment template already exists'}, status => 400)
    if defined $conflict && $conflict != $id;

  return $self->render(json => {error => 'Comment template does not exist'}, status => 400)
    unless my $template = $templates->edit($id, $name, $validation->param('body'));

  return $self->render(json => $template);
}

1;
