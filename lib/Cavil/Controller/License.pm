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

use Algorithm::Diff qw(sdiff);
use Cavil::Licenses qw(lic);

sub create_pattern ($self) {
  my $validation = $self->validation;
  $validation->required('pattern');
  $validation->optional('license');
  $validation->optional('packname');
  $validation->optional('risk')->num;
  $validation->optional('patent');
  $validation->optional('trademark');
  $validation->optional('export_restricted');
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
    export_restricted => $validation->param('export_restricted')
  );

  if ($match->{conflict}) {
    $self->flash(danger => 'Conflicting license pattern already exists.');
    return $self->redirect_to('new_pattern');
  }
  $self->flash(success => 'Pattern has been created.');
  $self->redirect_to('edit_pattern', id => $match->{id});
}

sub edit_pattern ($self) {
  my $id       = $self->stash('id');
  my $patterns = $self->patterns;

  my $pattern = $patterns->find($id);

  my $count = $patterns->match_count($id);
  $pattern->{matches}  = $count->{matches};
  $pattern->{packages} = $count->{packages};

  my $result = $patterns->closest_matches($pattern->{pattern}, 2);
  my $best   = $result->[0];

  # likely perfect match
  $best = $result->[1] if $best->{pattern} && $best->{pattern} == $id;

  my $sim = $best->{match};
  $best = $patterns->find($best->{pattern});

  my $p1 = Spooky::Patterns::XS::normalize($pattern->{pattern});
  $self->stash('diff', undef);
  if ($best) {
    my $p2     = Spooky::Patterns::XS::normalize($best->{pattern});
    my @words1 = map { $_->[1] } @$p1;
    my @words2 = map { $_->[1] } @$p2;
    my $diff   = sdiff(\@words1, \@words2);

    my $line = 1;
    for my $row (@$diff) {
      if ($row->[0] eq 'u' || $row->[0] eq 'c' || $row->[0] eq '-') {
        my $w1 = shift @$p1;
        $line = $w1->[0];
      }
      push(@$row, $line);
    }
    $self->stash('diff',       $diff);
    $self->stash('next_best',  $best);
    $self->stash('similarity', int($sim * 1000 + 0.5) / 10);
  }
  else {
    $self->stash('next_best', undef);
  }

  return $self->_edit_pattern($pattern);
}

sub list ($self) {
  $self->render;
}

sub new_pattern ($self) {
  my $validation = $self->validation;
  $validation->required('license-name');
  return $self->reply->json_validation_error if $validation->has_error;

  my $lname = $validation->param('license-name');
  $self->stash('diff',      undef);
  $self->stash('next_best', 0);
  return $self->_edit_pattern({license => $lname});
}

sub proposed ($self) {
  $self->render('license/proposed_patterns');
}

sub proposed_meta ($self) {
  my $v = $self->validation;
  $v->optional('before')->num;
  return $self->reply->json_validation_error if $v->has_error;
  my $before = $v->param('before') // 0;

  my $changes = $self->patterns->proposed_changes({before => $before});

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
  my $pattern  = $patterns->find($id);
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

  my $rows = $patterns->remove_proposal($checksum);
  $self->render(json => {removed => $rows});
}

sub show ($self) {
  my $name = $self->stash('name');
  $name = '' if $name eq '*Pattern without license*';
  $self->render(license => $name, patterns => $self->patterns->for_license($name));
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

sub _edit_pattern ($self, $match) {
  $self->render(template => 'license/edit_pattern', match => $match);
}

1;
