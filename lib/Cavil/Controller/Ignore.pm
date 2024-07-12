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

1;
