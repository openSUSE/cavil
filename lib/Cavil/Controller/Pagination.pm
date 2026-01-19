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

sub ignored_matches ($self) {
  my $v = $self->validation;
  $v->optional('limit')->num;
  $v->optional('offset')->num;
  $v->optional('filter');
  return $self->reply->json_validation_error if $v->has_error;
  my $limit  = $v->param('limit')  // 10;
  my $offset = $v->param('offset') // 0;
  my $search = $v->param('filter') // '';

  my $page
    = $self->helpers->patterns->paginate_ignored_matches({limit => $limit, offset => $offset, search => $search});
  $self->render(json => $page);
}

sub ignored_files ($self) {
  my $v = $self->validation;
  $v->optional('limit')->num;
  $v->optional('offset')->num;
  $v->optional('filter');
  return $self->reply->json_validation_error if $v->has_error;
  my $limit  = $v->param('limit')  // 10;
  my $offset = $v->param('offset') // 0;
  my $search = $v->param('filter') // '';

  my $page
    = $self->helpers->ignored_files->paginate_ignored_files({limit => $limit, offset => $offset, search => $search});
  $self->render(json => $page);
}

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
  $v->optional('notEmbargoed');
  $v->optional('filter');
  return $self->reply->json_validation_error if $v->has_error;
  my $limit         = $v->param('limit')        // 10;
  my $offset        = $v->param('offset')       // 0;
  my $priority      = $v->param('priority')     // 2;
  my $in_progress   = $v->param('inProgress')   // 'false';
  my $not_embargoed = $v->param('notEmbargoed') // 'false';
  my $search        = $v->param('filter')       // '';

  my $page = $self->packages->paginate_open_reviews(
    {
      limit         => $limit,
      offset        => $offset,
      in_progress   => $in_progress,
      not_embargoed => $not_embargoed,
      priority      => $priority,
      search        => $search
    }
  );
  $self->render(json => $self->_mark_active_packages($page));
}

sub product_reviews ($self) {
  my $v = $self->validation;
  $v->optional('limit')->num;
  $v->optional('offset')->num;
  $v->optional('attention');
  $v->optional('unresolvedMatches');
  $v->optional('patent');
  $v->optional('trademark');
  $v->optional('exportRestricted');
  $v->optional('filter');
  return $self->reply->json_validation_error if $v->has_error;
  my $limit              = $v->param('limit')             // 10;
  my $offset             = $v->param('offset')            // 0;
  my $attention          = $v->param('attention')         // 'false';
  my $unresolved_matches = $v->param('unresolvedMatches') // 'false';
  my $patent             = $v->param('patent')            // 'false';
  my $trademark          = $v->param('trademark')         // 'false';
  my $export_restricted  = $v->param('exportRestricted')  // 'false';
  my $search             = $v->param('filter')            // '';

  my $name = $self->stash('name');
  my $page = $self->packages->paginate_product_reviews(
    $name,
    {
      limit              => $limit,
      offset             => $offset,
      attention          => $attention,
      unresolved_matches => $unresolved_matches,
      patent             => $patent,
      trademark          => $trademark,
      export_restricted  => $export_restricted,
      search             => $search
    }
  );
  $self->render(json => $self->_mark_active_packages($page));
}

sub recent_reviews ($self) {
  my $v = $self->validation;
  $v->optional('limit')->num;
  $v->optional('offset')->num;
  $v->optional('byUser');
  $v->optional('unresolvedMatches');
  $v->optional('filter');
  return $self->reply->json_validation_error if $v->has_error;
  my $limit              = $v->param('limit')             // 10;
  my $offset             = $v->param('offset')            // 0;
  my $by_user            = $v->param('byUser')            // 'false';
  my $unresolved_matches = $v->param('unresolvedMatches') // 'false';
  my $search             = $v->param('filter')            // '';

  my $page = $self->packages->paginate_recent_reviews(
    {
      limit              => $limit,
      offset             => $offset,
      by_user            => $by_user,
      unresolved_matches => $unresolved_matches,
      search             => $search
    }
  );
  $self->render(json => $self->_mark_active_packages($page));
}

sub review_search ($self) {
  my $v = $self->validation;
  $v->optional('limit')->num;
  $v->optional('offset')->num;
  $v->optional('filter');
  $v->optional('notObsolete');
  $v->optional('pattern')->num;
  $v->optional('ignore')->num;
  return $self->reply->json_validation_error if $v->has_error;
  my $limit        = $v->param('limit')       // 10;
  my $offset       = $v->param('offset')      // 0;
  my $not_obsolete = $v->param('notObsolete') // 'false';
  my $search       = $v->param('filter')      // '';
  my $pattern      = $v->param('pattern');
  my $ignore       = $v->param('ignore');

  my $name = $self->stash('name');
  my $page = $self->packages->paginate_review_search(
    $name,
    {
      limit        => $limit,
      offset       => $offset,
      not_obsolete => $not_obsolete,
      search       => $search,
      pattern      => $pattern,
      ignore       => $ignore
    }
  );
  $self->render(json => $self->_mark_active_packages($page));
}

sub _mark_active_packages ($self, $page) {
  my $minion = $self->minion;
  for my $pkg (@{$page->{page}}) {
    my $id = $pkg->{id};
    $pkg->{active_jobs} = $minion->jobs({states => ['inactive', 'active'], notes => ["pkg_$id"]})->total;
    $pkg->{failed_jobs} = $minion->jobs({states => ['failed'], notes => ["pkg_$id"]})->total;
  }
  return $page;
}

1;
