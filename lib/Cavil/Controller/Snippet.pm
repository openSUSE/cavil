# Copyright (C) 2019 SUSE Linux GmbH
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

package Cavil::Controller::Snippet;
use Mojo::Base 'Mojolicious::Controller';

sub list {
  my $self = shift;

  $self->render(snippets => $self->snippets->random(100));
}

sub update {
  my $self = shift;

  my $db     = $self->pg->db;
  my $params = $self->req->params->to_hash;
  for my $param (sort keys %$params) {
    next unless $param =~ m/g_(\d+)/;
    my $id      = $1;
    my $license = $params->{$param};
    $db->update(
      'snippets',
      {license => $license, approved => 1, classified => 1},
      {id      => $id}
    );
  }
  $self->redirect_to('snippets');
}

sub edit {
  my $self = shift;

  my $id      = $self->param('id');
  my $snippet = $self->snippets->find($id);

  Spooky::Patterns::XS::init_matcher();
  my $p1 = Spooky::Patterns::XS::normalize($snippet->{text});

  my $best;
  my $min = 10000;
  for my $p (@{$self->patterns->all}) {
    my $p2 = Spooky::Patterns::XS::normalize($p->{pattern});
    my $d  = Spooky::Patterns::XS::distance($p1, $p2);
    if ($min > $d) {
      $min  = $d;
      $best = $p;
    }
  }

  $self->render(snippet => $snippet, best => $best);
}

1;
