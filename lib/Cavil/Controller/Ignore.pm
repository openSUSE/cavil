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

package Cavil::Controller::Ignore;
use Mojo::Base 'Mojolicious::Controller', -signatures;

sub add_glob ($self) {
  my $validation = $self->validation;
  $validation->required('glob');
  $validation->required('package')->num;
  return $self->reply->json_validation_error if $validation->has_error;

  $self->ignored_files->add($validation->param('glob'), $self->current_user);
  $self->packages->analyze($validation->param('package'));

  return $self->render(json => 'ok');
}

sub add_match ($self) {
  my $validation = $self->validation;
  $validation->required('hash')->like(qr/^[a-f0-9]{32}$/i);
  $validation->required('package');
  $validation->optional('delay')->num;
  $validation->optional('contributor');
  return $self->reply->json_validation_error if $validation->has_error;

  my $owner_id       = $self->users->id_for_login($self->current_user);
  my $contributor    = $validation->param('contributor');
  my $contributor_id = $contributor ? $self->users->id_for_login($contributor) : undef;
  my $delay          = $validation->param('delay') // 0;

  my $hash = $validation->param('hash');
  $self->packages->ignore_line(
    {
      package     => $validation->param('package'),
      hash        => $hash,
      owner       => $owner_id,
      contributor => $contributor_id,
      delay       => $delay
    }
  );
  $self->patterns->remove_proposal($hash);

  return $self->render(json => 'ok');
}

sub list_globs ($self) {
  $self->render('ignore/list_globs');
}

sub list_matches ($self) {
  $self->render('ignore/list_matches');
}

sub remove_glob ($self) {
  return $self->render(status => 400, json => {error => 'Glob does not exist'})
    unless $self->ignored_files->remove($self->param('id'), $self->current_user);
  return $self->render(json => 'ok');
}

sub remove_match ($self) {
  return $self->render(status => 400, json => {error => 'Ignored match does not exist'})
    unless $self->packages->remove_ignored_line($self->param('id'), $self->current_user);
  return $self->render(json => 'ok');
}

1;
