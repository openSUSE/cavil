# Copyright (C) 2018 SUSE Linux GmbH
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

package Cavil::Controller::Search;
use Mojo::Base 'Mojolicious::Controller';

sub search {
  my $self = shift;

  my ($suggestions, $results) = ([], []);
  if (my $query = $self->param('q')) {
    my $pkgs = $self->packages;
    $suggestions = $pkgs->name_suggestions($query);
    $results     = $pkgs->find_by_name($query);
  }

  $self->render('search/results', suggestions => $suggestions, results => $results);
}

1;
