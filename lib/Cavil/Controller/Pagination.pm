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

sub known_licenses ($self) {
  my $v = $self->validation;
  $v->optional('limit')->num;
  $v->optional('offset')->num;
  $v->optional('filter');
  return $self->reply->json_validation_error if $v->has_error;
  my $limit  = $v->param('limit')  // 10;
  my $offset = $v->param('offset') // 0;
  my $search = $v->param('filter') // '';

  my $page = $self->patterns->paginate_known_licenses({limit => $limit, offset => $offset, search => $search});
  $self->render(json => $page);
}

sub known_products ($self) {
  my $v = $self->validation;
  $v->optional('limit')->num;
  $v->optional('offset')->num;
  $v->optional('filter');
  return $self->reply->json_validation_error if $v->has_error;
  my $limit  = $v->param('limit')  // 10;
  my $offset = $v->param('offset') // 0;
  my $search = $v->param('filter') // '';

  my $page = $self->products->paginate_known_products({limit => $limit, offset => $offset, search => $search});
  $self->render(json => $page);
}

sub open_reviews ($self) {
  my $v = $self->validation;
  $v->optional('limit')->num;
  $v->optional('offset')->num;
  $v->optional('priority')->num;
  $v->optional('inProgress');
  $v->optional('filter');
  return $self->reply->json_validation_error if $v->has_error;
  my $limit       = $v->param('limit')      // 10;
  my $offset      = $v->param('offset')     // 0;
  my $priority    = $v->param('priority')   // 2;
  my $in_progress = $v->param('inProgress') // 'false';
  my $search      = $v->param('filter')     // '';

  my $page = $self->packages->paginate_open_reviews(
    {limit => $limit, offset => $offset, in_progress => $in_progress, priority => $priority, search => $search});
  $self->render(json => $page);
}

sub product_reviews ($self) {
  my $v = $self->validation;
  $v->optional('limit')->num;
  $v->optional('offset')->num;
  $v->optional('attention');
  $v->optional('patent');
  $v->optional('trademark');
  $v->optional('exportRestricted');
  $v->optional('filter');
  return $self->reply->json_validation_error if $v->has_error;
  my $limit             = $v->param('limit')            // 10;
  my $offset            = $v->param('offset')           // 0;
  my $attention         = $v->param('attention')        // 'false';
  my $patent            = $v->param('patent')           // 'false';
  my $trademark         = $v->param('trademark')        // 'false';
  my $export_restricted = $v->param('exportRestricted') // 'false';
  my $search            = $v->param('filter')           // '';

  my $name = $self->stash('name');
  my $page = $self->packages->paginate_product_reviews(
    $name,
    {
      limit             => $limit,
      offset            => $offset,
      attention         => $attention,
      patent            => $patent,
      trademark         => $trademark,
      export_restricted => $export_restricted,
      search            => $search
    }
  );
  $self->render(json => $page);
}

sub recent_reviews ($self) {
  my $v = $self->validation;
  $v->optional('limit')->num;
  $v->optional('offset')->num;
  $v->optional('byUser');
  $v->optional('filter');
  return $self->reply->json_validation_error if $v->has_error;
  my $limit   = $v->param('limit')  // 10;
  my $offset  = $v->param('offset') // 0;
  my $by_user = $v->param('byUser') // 'false';
  my $search  = $v->param('filter') // '';

  my $page = $self->packages->paginate_recent_reviews(
    {limit => $limit, offset => $offset, by_user => $by_user, search => $search});
  $self->render(json => $page);
}

sub review_search ($self) {
  my $v = $self->validation;
  $v->optional('limit')->num;
  $v->optional('offset')->num;
  $v->optional('filter');
  $v->optional('notObsolete');
  $v->optional('pattern')->num;
  return $self->reply->json_validation_error if $v->has_error;
  my $limit        = $v->param('limit')       // 10;
  my $offset       = $v->param('offset')      // 0;
  my $not_obsolete = $v->param('notObsolete') // 'false';
  my $search       = $v->param('filter')      // '';
  my $pattern      = $v->param('pattern');

  my $name = $self->stash('name');
  my $page = $self->packages->paginate_review_search($name,
    {limit => $limit, offset => $offset, not_obsolete => $not_obsolete, search => $search, pattern => $pattern});
  $self->render(json => $page);
}

1;
