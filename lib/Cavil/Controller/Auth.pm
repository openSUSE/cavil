# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package Cavil::Controller::Auth;
use Mojo::Base 'Mojolicious::Controller', -signatures;

sub check ($self) {
  my $role = $self->stash('roles');
  my $user = $self->current_user;

  $self->render('login', status => 401, format => 'html') and return undef if !$user && !@$role;

  # User needs to log in or a different role
  $self->render('permissions', status => 403, format => 'html') and return undef
    unless $user && $self->users->has_role($user, @$role);

  return 1;
}

sub logout ($self) {
  delete $self->session->{user};
  $self->redirect_to('dashboard');
}

1;
