# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package Cavil::Controller::Stats;
use Mojo::Base 'Mojolicious::Controller', -signatures;

sub index ($self) {
  $self->render;
}

sub meta ($self) {
  my $stats = $self->packages->stats;
  $self->render(json => $stats);
}

1;
