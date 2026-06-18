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

package Cavil::Controller::License;
use Mojo::Base 'Mojolicious::Controller', -signatures;

use Cavil::Licenses qw(lic);
use Cavil::Util     qw(spdx_link);

sub create_pattern ($self) {
  my $validation = $self->validation;
  $validation->required('pattern');
  $validation->optional('license');
  $validation->optional('packname');
  $validation->optional('risk')->num;
  $validation->optional('patent');
  $validation->optional('trademark');
  $validation->optional('export_restricted');
  $validation->optional('cla');
  $validation->optional('eula');
  return $self->reply->json_validation_error if $validation->has_error;

  my $pattern = $validation->param('pattern');

  my $patterns = $self->patterns;
  my $match    = $patterns->create(
    license           => $validation->param('license'),
    packname          => $validation->param('packname'),
    pattern           => $pattern,
    risk              => $validation->param('risk'),
    patent            => $validation->param('patent'),
    trademark         => $validation->param('trademark'),
    export_restricted => $validation->param('export_restricted'),
    cla               => $validation->param('cla'),
    eula              => $validation->param('eula')
  );

  if ($match->{conflict}) {
    $self->flash(danger => 'Conflicting license pattern already exists.');
    return $self->redirect_to('new_pattern');
  }
  $self->flash(success => 'Pattern has been created.');
  $self->redirect_to('edit_pattern', id => $match->{id});
}

sub edit_pattern ($self) {
  my $id      = $self->stash('id');
  my $pattern = $self->patterns->find($id);
  return $self->reply->not_found unless $pattern;
  $self->render(template => 'license/edit_pattern', match => $pattern);
}

sub match_count_json ($self) {
  my $id    = $self->stash('id');
  my $count = $self->param('capped') ? $self->patterns->capped_match_count($id) : $self->patterns->match_count($id);
  $self->render(json => $count);
}

sub list ($self) {
  $self->render;
}

sub pattern_detail ($self) {
  my $id      = $self->stash('id');
  my $pattern = $self->patterns->find($id);
  return $self->reply->not_found unless $pattern;
  $self->render(json => $pattern);
}

sub show_meta ($self) {
  my $name = $self->stash('name');
  $name = '' if $name eq '*Pattern without license*';
  my $patterns = $self->patterns->for_license($name);
  return $self->reply->not_found unless @$patterns;
  my $spdx = $patterns->[0]{spdx} // '';
  $self->render(
    json => {
      license         => $name,
      display_license => $name eq '' ? '*Pattern without license*' : $name,
      spdx            => $spdx,
      spdx_html       => spdx_link($spdx),
      patterns        => $patterns,
      can_admin       => $self->current_user_has_role('admin') ? \1 : \0
    }
  );
}

sub missing ($self) {
  $self->render('license/missing_licenses');
}

sub new_pattern ($self) {
  my $validation = $self->validation;
  $validation->required('license-name');
  return $self->reply->json_validation_error if $validation->has_error;

  my $lname = $validation->param('license-name');
  $self->render(
    template => 'license/edit_pattern',
    match    => {
      license           => $lname,
      pattern           => '',
      risk              => 0,
      patent            => 0,
      trademark         => 0,
      export_restricted => 0,
      cla               => 0,
      eula              => 0,
      packname          => ''
    }
  );
}

sub proposed ($self) {
  $self->render('license/proposed_patterns');
}

sub proposal_stats ($self) {
  $self->render(json => $self->patterns->proposal_stats);
}

sub proposed_meta ($self) {
  my $v = $self->validation;
  $v->optional('action')->in('missing_license', 'create_pattern', 'create_ignore');
  $v->optional('before')->num;
  $v->optional('filter');
  return $self->reply->json_validation_error if $v->has_error;
  my $before  = $v->param('before') // 0;
  my $actions = $v->every_param('action');
  my $search  = $v->param('filter') // '';

  my $changes = $self->patterns->proposed_changes({actions => $actions, before => $before, search => $search});

  $self->render(json => {changes => $changes->{changes}, total => $changes->{total}});
}

sub recent ($self) {
  $self->render('license/recent_patterns');
}

sub recent_meta ($self) {
  my $v = $self->validation;
  $v->optional('before')->num;
  $v->optional('hasContributor')->in('true', 'false');
  $v->optional('timeframe')->in('any', 'year', 'month', 'week', 'day', 'hour');
  return $self->reply->json_validation_error if $v->has_error;
  my $before          = $v->param('before')         // 0;
  my $has_contributor = $v->param('hasContributor') // 'false';
  my $timeframe       = $v->param('timeframe')      // 'any';

  my $recent
    = $self->patterns->recent({before => $before, has_contributor => $has_contributor, timeframe => $timeframe});

  $self->render(json => {patterns => $recent->{patterns}, total => $recent->{total}});
}

# AJAX route
sub remove_pattern ($self) {
  my $id       = $self->stash('id');
  my $patterns = $self->patterns;
  $self->packages->reindex_matched_packages($id);
  $patterns->expire_cache;
  $patterns->remove($id);
  $self->render(json => 'ok');
}

sub remove_proposal ($self) {
  my $checksum = $self->param('checksum');

  my $patterns = $self->patterns;
  my $is_admin = $self->current_user_has_role('admin');
  my $is_owner = $patterns->is_proposal_owner($checksum, $self->current_user);
  return $self->render('permissions', status => 403) unless $is_owner || $is_admin;

  my $removed = $patterns->remove_proposal($checksum);
  $self->render(json => {removed => $removed ? 1 : 0});
}

sub show ($self) {
  my $name = $self->stash('name');
  $name = '' if $name eq '*Pattern without license*';
  $self->render(license => $name);
}

sub update_pattern ($self) {
  my $validation = $self->validation;
  $validation->required('pattern');
  $validation->optional('license');
  $validation->optional('packname');
  $validation->optional('risk')->num;
  $validation->optional('patent');
  $validation->optional('trademark');
  $validation->optional('export_restricted');
  $validation->optional('cla');
  $validation->optional('eula');
  return $self->reply->json_validation_error if $validation->has_error;

  my $id       = $self->stash('id');
  my $patterns = $self->patterns;
  my $pattern  = $validation->param('pattern');
  my $owner_id = $self->users->id_for_login($self->current_user);

  # expire old license pattern
  my $result = $patterns->update(
    $id,
    packname          => $validation->param('packname'),
    pattern           => $pattern,
    license           => $validation->param('license'),
    patent            => $validation->param('patent'),
    trademark         => $validation->param('trademark'),
    export_restricted => $validation->param('export_restricted'),
    cla               => $validation->param('cla'),
    eula              => $validation->param('eula'),
    risk              => $validation->param('risk'),
    owner             => $owner_id
  );
  if ($result->{conflict}) {
    $self->flash(danger => 'Conflicting license pattern already exists.');
    return $self->redirect_to('edit_pattern', id => $id);
  }
  $patterns->expire_cache;
  $self->packages->mark_matched_for_reindex($id);
  $self->flash(success => 'Pattern has been updated, reindexing all affected packages.');
  $self->redirect_to('edit_pattern', id => $id);
}

sub update_pattern_json ($self) {
  my $validation = $self->validation;
  $validation->required('pattern');
  $validation->optional('license');
  $validation->optional('packname');
  $validation->optional('risk')->num;
  $validation->optional('patent');
  $validation->optional('trademark');
  $validation->optional('export_restricted');
  $validation->optional('cla');
  $validation->optional('eula');
  return $self->reply->json_validation_error if $validation->has_error;

  my $id       = $self->stash('id');
  my $patterns = $self->patterns;
  my $pattern  = $validation->param('pattern');
  my $owner_id = $self->users->id_for_login($self->current_user);

  my $result = $patterns->update(
    $id,
    packname          => $validation->param('packname'),
    pattern           => $pattern,
    license           => $validation->param('license'),
    patent            => $validation->param('patent'),
    trademark         => $validation->param('trademark'),
    export_restricted => $validation->param('export_restricted'),
    cla               => $validation->param('cla'),
    eula              => $validation->param('eula'),
    risk              => $validation->param('risk'),
    owner             => $owner_id
  );
  return $self->render(json => {error => 'Conflicting license pattern already exists.'}, status => 409)
    if $result->{conflict};

  $patterns->expire_cache;
  $self->packages->mark_matched_for_reindex($id);
  $self->render(json => {updated => 1});
}

sub update_patterns ($self) {
  my $validation = $self->validation;
  $validation->required('license');
  $validation->optional('spdx');
  return $self->reply->json_validation_error if $validation->has_error;

  my $license = $validation->param('license');

  my $spdx = $validation->param('spdx') // '';
  if ($spdx eq '' || lic($spdx)->is_valid_expression) {
    my $rows = $self->pg->db->query('UPDATE license_patterns SET spdx = ? WHERE license = ?', $spdx, $license)->rows;
    $self->flash(success => "$rows patterns have been updated.");
  }
  else {
    $self->flash(danger =>
        qq{"$spdx" is not a valid SPDX expression. Use a "LicenseRef-*" prefix for licenses not yet part of the spec.});
  }


  $self->redirect_to('license_show', name => $license);
}

sub update_patterns_json ($self) {
  my $validation = $self->validation;
  $validation->required('license');
  $validation->optional('spdx');
  return $self->reply->json_validation_error if $validation->has_error;

  my $license = $validation->param('license');
  my $spdx    = $validation->param('spdx') // '';
  return $self->render(
    json => {
      error =>
        qq{"$spdx" is not a valid SPDX expression. Use a "LicenseRef-*" prefix for licenses not yet part of the spec.}
    },
    status => 400
  ) unless $spdx eq '' || lic($spdx)->is_valid_expression;

  my $rows = $self->pg->db->query('UPDATE license_patterns SET spdx = ? WHERE license = ?', $spdx, $license)->rows;
  $self->render(json => {updated => $rows, spdx => $spdx, spdx_html => spdx_link($spdx)});
}

1;
