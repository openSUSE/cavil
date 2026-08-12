# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package Cavil::Controller::Auth::Dummy;
use Mojo::Base 'Mojolicious::Controller', -signatures;

sub login ($self) {
  my $user = $self->users->find_or_create(
    login => 'tester',
    email => 'tester@example.com',
    roles => ['manager', 'admin', 'classifier']
  );

  $self->session(user => $user->{login});
  $self->redirect_to('dashboard');
}

1;
