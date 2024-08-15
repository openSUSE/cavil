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
use Mojo::Base 'Mojolicious::Controller', -signatures;

use Mojo::File  qw(path);
use Cavil::Util qw(pattern_matches);
use Mojo::JSON  qw(true false);

sub approve ($self) {
  my $v = $self->validation;
  $v->required('license')->in('true', 'false');
  return $self->reply->json_validation_error if $v->has_error;
  my $license = $v->param('license');

  my $id = $self->param('id');
  $self->snippets->approve($id, $license);

  my $user = $self->session('user');
  $self->app->log->info(qq{Snippet $id approved by $user (License: $license))});

  $self->render(json => {message => 'ok'});
}

sub closest ($self) {
  my $v = $self->validation;
  $v->required('text');
  return $self->reply->json_validation_error if $v->has_error;

  my $text = $v->param('text');
  return $self->render(json => {pattern => undef}) unless my $pattern = $self->patterns->closest_pattern($text);

  $self->render(
    json => {
      pattern => {
        id         => $pattern->{id},
        text       => $pattern->{pattern},
        license    => $pattern->{license},
        risk       => $pattern->{risk},
        package    => $pattern->{packname},
        similarity => $pattern->{similarity}
      }
    }
  );
}

sub decision ($self) {
  my $validation = $self->validation;
  $validation->optional('create-pattern');
  $validation->optional('propose-pattern');
  $validation->optional('propose-ignore');
  $validation->optional('mark-non-license');
  return $self->reply->json_validation_error if $validation->has_error;

  my $id       = $self->param('id');
  my $snippets = $self->snippets;
  my $packages = $snippets->packages_for_snippet($id);

  # Only admins can create patterns or ignore snippets directly
  my $is_admin = $self->current_user_has_role('admin');
  if ($validation->param('create-pattern')) {
    return $self->render('permissions', status => 403) unless $is_admin;
    $self->_create_pattern($packages, $validation);
  }

  elsif ($validation->param('mark-non-license')) {
    return $self->render('permissions', status => 403) unless $is_admin;
    $snippets->mark_non_license($id);
    $self->packages->analyze($_, 4) for @$packages;
    $self->render(packages => $packages);
  }

  elsif ($validation->param('propose-pattern')) { $self->_propose_pattern($validation) }
  elsif ($validation->param('propose-ignore'))  { $self->_propose_ignore($validation) }

  else { $self->reply->not_found }
}

sub edit ($self) {
  my $id      = $self->stash('id');
  my $snippet = $self->snippets->find($id);
  $self->render(snippet => $snippet);
}

sub from_file ($self) {
  my $v = $self->validation;
  $v->optional('hash')->like(qr/^[a-f0-9]{32}$/i);
  $v->optional('from');
  return $self->reply->json_validation_error if $v->has_error;

  my $file_id    = $self->stash('file');
  my $first_line = $self->stash('start');
  my $last_line  = $self->stash('end');

  return $self->reply->not_found
    unless defined(my $snippet = $self->snippets->from_file($file_id, $first_line, $last_line));

  my $hash = $v->param('hash') // '';
  my $from = $v->param('from') // '';
  return $self->redirect_to($self->url_for('edit_snippet', id => $snippet)->query(hash => $hash, from => $from));
}

sub list ($self) {
  $self->render;
}

sub list_meta ($self) {
  my $v = $self->validation;
  $v->optional('isClassified')->in('true', 'false');
  $v->optional('isApproved')->in('true', 'false');
  $v->optional('isLegal')->in('true', 'false');
  $v->optional('notLegal')->in('true', 'false');
  $v->optional('confidence')->num(0, 100);
  $v->optional('timeframe')->in('any', 'year', 'month', 'week', 'day', 'hour');
  $v->optional('before')->num;
  return $self->reply->json_validation_error if $v->has_error;
  my $is_classified = $v->param('isClassified') // 'true';
  my $is_approved   = $v->param('isApproved')   // 'false';
  my $is_legal      = $v->param('isLegal')      // 'true';
  my $not_legal     = $v->param('notLegal')     // 'true';
  my $confidence    = $v->param('confidence')   // 100;
  my $timeframe     = $v->param('timeframe')    // 'any';
  my $before        = $v->param('before')       // 0;

  my $unclassified = $self->snippets->unclassified(
    {
      before        => $before,
      confidence    => $confidence,
      is_classified => $is_classified,
      is_approved   => $is_approved,
      is_legal      => $is_legal,
      not_legal     => $not_legal,
      timeframe     => $timeframe
    }
  );

  my $snippets = $unclassified->{snippets};
  for my $snippet (@$snippets) {
    $snippet->{$_} = $snippet->{$_} ? true : false for qw(license classified approved);
  }

  $self->render(json => {snippets => $snippets, total => $unclassified->{total}});
}

sub meta ($self) {
  my $id       = $self->param('id');
  my $snippet  = $self->snippets->with_context($id);
  my $patterns = $self->patterns;
  my $licenses = $patterns->autocomplete;
  my $pattern  = $patterns->closest_pattern($snippet->{text}) // {};
  $self->render(json => {snippet => $snippet, licenses => $licenses, closest => $pattern->{license}});
}

sub _create_pattern ($self, $packages, $validation) {
  $validation->required('license');
  $validation->required('pattern');
  $validation->required('risk')->num;
  $validation->optional('checksum');
  $validation->optional('patent');
  $validation->optional('trademark');
  $validation->optional('export_restricted');
  $validation->optional('contributor');
  $validation->optional('delay')->num;
  return $self->reply->json_validation_error if $validation->has_error;

  my $owner_id       = $self->users->id_for_login($self->current_user);
  my $contributor    = $validation->param('contributor');
  my $contributor_id = $contributor ? $self->users->id_for_login($contributor) : undef;
  my $delay          = $validation->param('delay') // 0;

  my $patterns = $self->patterns;
  my $pattern  = $patterns->create(
    license           => $validation->param('license'),
    pattern           => $validation->param('pattern'),
    risk              => $validation->param('risk'),
    patent            => $validation->param('patent'),
    trademark         => $validation->param('trademark'),
    export_restricted => $validation->param('export_restricted'),
    owner             => $owner_id,
    contributor       => $contributor_id
  );

  return $self->render(status => 409, error => 'Conflicting license pattern already exists') if $pattern->{conflict};

  if (my $checksum = $validation->param('checksum')) { $patterns->remove_proposal($checksum) }
  $self->packages->reindex($_, 3, [], $delay) for @$packages;
  $self->render(packages => $packages, pattern => $pattern->{id});
}

sub _propose_pattern ($self, $validation) {
  $validation->required('license');
  $validation->required('pattern');
  $validation->required('risk')->num;
  $validation->optional('edited');
  $validation->optional('highlighted', 'comma_separated');
  $validation->optional('package');
  $validation->optional('patent');
  $validation->optional('trademark');
  $validation->optional('export_restricted');
  return $self->reply->json_validation_error if $validation->has_error;

  my $pattern = $validation->param('pattern');
  my $snippet = $self->snippets->find($self->param('id'));
  return $self->render(status => 400, error => 'License pattern does not match the original snippet')
    unless pattern_matches($pattern, $snippet->{text});

  my $user_id = $self->users->id_for_login($self->current_user);
  my $result  = $self->patterns->propose_create(
    snippet           => $snippet->{id},
    pattern           => $pattern,
    highlighted       => $validation->every_param('highlighted'),
    edited            => $validation->param('edited'),
    license           => $validation->param('license'),
    risk              => $validation->param('risk'),
    package           => $validation->param('package'),
    patent            => $validation->param('patent'),
    trademark         => $validation->param('trademark'),
    export_restricted => $validation->param('export_restricted'),
    owner             => $user_id
  );

  return $self->render(
    status => 400,
    error  => 'This license and risk combination is not allowed, only use pre-existing licenses'
  ) if $result->{license_conflict};
  return $self->render(status => 409, error => 'Conflicting license pattern already exists') if $result->{conflict};
  return $self->render(status => 409, error => 'Conflicting license pattern proposal already exists')
    if $result->{proposal_conflict};

  $self->render(proposal => 1);
}

sub _propose_ignore ($self, $validation) {
  $validation->required('hash');
  $validation->required('from');
  $validation->required('pattern');
  $validation->required('edited');
  $validation->optional('highlighted', 'comma_separated');
  $validation->optional('package');
  return $self->reply->json_validation_error if $validation->has_error;

  my $edited = $validation->param('edited');
  return $self->render(status => 400, error => 'Only unedited snippets can be ignored') if $edited;

  my $user_id = $self->users->id_for_login($self->current_user);
  my $result  = $self->patterns->propose_ignore(
    snippet     => $self->param('id'),
    hash        => $validation->param('hash'),
    from        => $validation->param('from'),
    pattern     => $validation->param('pattern'),
    highlighted => $validation->every_param('highlighted'),
    edited      => $edited,
    package     => $validation->param('package'),
    owner       => $user_id
  );

  return $self->render(status => 409, error => 'Conflicting ignore pattern already exists') if $result->{conflict};
  return $self->render(status => 409, error => 'Conflicting ignore pattern proposal already exists')
    if $result->{proposal_conflict};

  $self->render(proposal => 1);
}

1;
