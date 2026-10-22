# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package Cavil::Controller::Settings;
use Mojo::Base 'Mojolicious::Controller', -signatures;

sub add_exclusion ($self) {
  my $v = $self->validation;
  $v->required('package_glob', 'trim')->like(qr/^\S+$/);
  $v->required('file',         'trim')->like(qr/^\S+$/);
  $v->optional('reason', 'trim');
  return $self->reply->json_validation_error if $v->has_error;

  my %rule
    = (package_glob => $v->param('package_glob'), file => $v->param('file'), reason => $v->param('reason') // '');
  my $exclusions = $self->unpack_exclusions;
  if (my $error = $exclusions->invalid(\%rule)) { return $self->render(json => {error => $error}, status => 400) }
  return $self->render(json => {error => 'This file is already excluded for these packages'}, status => 400)
    unless $exclusions->add(\%rule, $self->current_user);
  return $self->render(json => 'ok');
}

sub auto_accept ($self) {
  $self->render(
    json => {%{$self->settings->summary}, last_change => $self->audit_log->last_event(['settings.changed'])});
}

sub first ($self) {
  $self->redirect_to($self->current_user_can('infra') ? '/settings/auto-accept' : '/settings/comment-templates');
}

sub remove_exclusion ($self) {
  return $self->render(json => {error => 'Excluded file does not exist'}, status => 400)
    unless $self->unpack_exclusions->remove($self->param('id'), $self->current_user);
  return $self->render(json => 'ok');
}

sub show ($self) {
  $self->render('settings/show', section => $self->stash('section'));
}

sub update_auto_accept ($self) {
  my $body = $self->req->json;
  return $self->render(json => {error => 'Invalid request'}, status => 400)
    unless ref $body eq 'HASH' && ref($body->{values} // {}) eq 'HASH' && ref($body->{reset} // []) eq 'ARRAY';

  my $result = $self->settings->update($self->current_user, $body->{values} // {}, $body->{reset} // []);
  return $self->render(json => {errors => $result->{errors}}, status => 400) if $result->{errors};

  my $rechecked = $self->packages->analyze_held($result->{old}, $result->{new});
  $self->render(
    json => {
      %{$self->settings->summary},
      rechecked   => $rechecked,
      last_change => $self->audit_log->last_event(['settings.changed'])
    }
  );
}

1;
