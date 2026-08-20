# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package Cavil::Controller::Pagination;
use Mojo::Base 'Mojolicious::Controller', -signatures;

use Cavil::Util qw(external_link_data);

sub comment_templates ($self) {
  my $v = $self->validation;
  $v->optional('limit')->num;
  $v->optional('offset')->num;
  $v->optional('filter');
  return $self->reply->json_validation_error if $v->has_error;
  my $limit  = $v->param('limit')  // 10;
  my $offset = $v->param('offset') // 0;
  my $search = $v->param('filter') // '';

  my $page
    = $self->helpers->comment_templates->paginate_templates({limit => $limit, offset => $offset, search => $search});
  $self->render(json => $page);
}

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
  $v->optional('grouped');
  return $self->reply->json_validation_error if $v->has_error;
  my $limit   = $v->param('limit')   // 10;
  my $offset  = $v->param('offset')  // 0;
  my $search  = $v->param('filter')  // '';
  my $grouped = $v->param('grouped') // 'true';

  my $page = $self->products->paginate_known_products(
    {limit => $limit, offset => $offset, search => $search, grouped => $grouped});
  $self->render(json => $page);
}

sub open_reviews ($self) {
  my $v = $self->validation;
  $v->optional('limit')->num;
  $v->optional('offset')->num;
  $v->optional('priority')->num;
  $v->optional('inProgress');
  $v->optional('notEmbargoed');
  $v->optional('annotated');
  $v->optional('filter');
  return $self->reply->json_validation_error if $v->has_error;
  my $limit         = $v->param('limit')        // 10;
  my $offset        = $v->param('offset')       // 0;
  my $priority      = $v->param('priority')     // 2;
  my $in_progress   = $v->param('inProgress')   // 'false';
  my $not_embargoed = $v->param('notEmbargoed') // 'false';
  my $annotated     = $v->param('annotated')    // 'false';
  my $search        = $v->param('filter')       // '';

  my $page = $self->packages->paginate_open_reviews(
    {
      limit               => $limit,
      offset              => $offset,
      in_progress         => $in_progress,
      not_embargoed       => $not_embargoed,
      priority            => $priority,
      search              => $search,
      notes               => $annotated eq 'true' ? 'with' : 'any',
      include_lawyer_only => $self->_can_see_lawyer_only
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
  $v->optional('cla');
  $v->optional('eula');
  $v->optional('annotated');
  $v->optional('filter');
  return $self->reply->json_validation_error if $v->has_error;
  my $limit              = $v->param('limit')             // 10;
  my $offset             = $v->param('offset')            // 0;
  my $attention          = $v->param('attention')         // 'false';
  my $unresolved_matches = $v->param('unresolvedMatches') // 'false';
  my $patent             = $v->param('patent')            // 'false';
  my $trademark          = $v->param('trademark')         // 'false';
  my $export_restricted  = $v->param('exportRestricted')  // 'false';
  my $cla                = $v->param('cla')               // 'false';
  my $eula               = $v->param('eula')              // 'false';
  my $annotated          = $v->param('annotated')         // 'false';
  my $search             = $v->param('filter')            // '';

  my $name = $self->stash('name');
  my $page = $self->packages->paginate_product_reviews(
    $name,
    {
      limit               => $limit,
      offset              => $offset,
      attention           => $attention,
      unresolved_matches  => $unresolved_matches,
      patent              => $patent,
      trademark           => $trademark,
      export_restricted   => $export_restricted,
      cla                 => $cla,
      eula                => $eula,
      search              => $search,
      notes               => $annotated eq 'true' ? 'with' : 'any',
      include_lawyer_only => $self->_can_see_lawyer_only
    }
  );
  $self->render(json => $self->_mark_active_packages($page));
}

sub recent_reviews ($self) {
  my $v = $self->validation;
  $v->optional('limit')->num;
  $v->optional('offset')->num;
  $v->optional('byUser');
  $v->optional('aiAssisted');
  $v->optional('unresolvedMatches');
  $v->optional('filter');
  return $self->reply->json_validation_error if $v->has_error;
  my $limit              = $v->param('limit')             // 10;
  my $offset             = $v->param('offset')            // 0;
  my $by_user            = $v->param('byUser')            // 'false';
  my $ai_assisted        = $v->param('aiAssisted')        // 'false';
  my $unresolved_matches = $v->param('unresolvedMatches') // 'false';
  my $search             = $v->param('filter')            // '';

  my $page = $self->packages->paginate_recent_reviews(
    {
      limit              => $limit,
      offset             => $offset,
      by_user            => $by_user,
      ai_assisted        => $ai_assisted,
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
  $v->optional('component');
  return $self->reply->json_validation_error if $v->has_error;
  my $limit        = $v->param('limit')       // 10;
  my $offset       = $v->param('offset')      // 0;
  my $not_obsolete = $v->param('notObsolete') // 'false';
  my $search       = $v->param('filter')      // '';
  my $pattern      = $v->param('pattern');
  my $ignore       = $v->param('ignore');
  my $component    = $v->param('component');

  my $name = $self->stash('name');
  my $page = $self->packages->paginate_review_search(
    $name,
    {
      limit        => $limit,
      offset       => $offset,
      not_obsolete => $not_obsolete,
      search       => $search,
      pattern      => $pattern,
      ignore       => $ignore,
      component    => $component
    }
  );
  $self->render(json => $self->_mark_active_packages($page));
}

sub _mark_active_packages ($self, $page) {
  my $minion = $self->minion;
  my $config = $self->app->config;

  # One query for the whole page; the review search names the column "package" instead of "name"
  my $rows
    = [map { {id => $_->{id}, name => $_->{name} // $_->{package}, checksum => $_->{checksum}} } @{$page->{page}}];
  my $notes = $self->notes->relevant_notes($rows, include_lawyer_only => $self->_can_see_lawyer_only);

  for my $pkg (@{$page->{page}}) {
    my $id = $pkg->{id};
    $pkg->{external_link_data} = external_link_data($pkg->{external_link}, $config->{external_link_sources});
    $pkg->{active_jobs}        = $minion->jobs({states => ['inactive', 'active'], notes => ["pkg_$id"]})->total;
    $pkg->{failed_jobs}        = $minion->jobs({states => ['failed'], notes => ["pkg_$id"]})->total;
    $pkg->{relevant_note}      = $notes->{$id} ? ($notes->{$id}{review} ? 'review' : 'note') : undef;
  }
  return $page;
}

# A note icon would give away the existence of a lawyer-only note to someone who cannot read it
sub _can_see_lawyer_only ($self) { $self->current_user_can('curate') ? 1 : 0 }

1;
