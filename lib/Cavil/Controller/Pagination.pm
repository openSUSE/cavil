# Copyright (C) 2022 SUSE Linux GmbH
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

package Cavil::Controller::Pagination;
use Mojo::Base 'Mojolicious::Controller', -signatures;

sub open_reviews ($self) {
  my $v = $self->validation;
  $v->optional('limit')->num;
  $v->optional('offset')->num;
  $v->optional('inProgress');
  $v->optional('search');
  return $self->reply->json_validation_error if $v->has_error;
  my $limit       = $v->param('limit')      // 10;
  my $offset      = $v->param('offset')     // 0;
  my $in_progress = $v->param('inProgress') // 'false';
  my $search      = $v->param('search')     // '';

  my $page = $self->packages->paginate_open_reviews(
    {limit => $limit, offset => $offset, in_progress => $in_progress, search => $search});
  $self->render(json => $page);
}

sub recent_reviews ($self) {
  my $v = $self->validation;
  $v->optional('limit')->num;
  $v->optional('offset')->num;
  $v->optional('byUser');
  $v->optional('search');
  return $self->reply->json_validation_error if $v->has_error;
  my $limit   = $v->param('limit')  // 10;
  my $offset  = $v->param('offset') // 0;
  my $by_user = $v->param('byUser') // 'false';
  my $search  = $v->param('search') // '';

  my $page = $self->packages->paginate_recent_reviews(
    {limit => $limit, offset => $offset, by_user => $by_user, search => $search});
  $self->render(json => $page);
}

1;
