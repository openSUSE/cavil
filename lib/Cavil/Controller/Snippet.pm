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

use Mojo::File 'path';
use Cavil::Util qw(read_lines);
use Mojo::JSON  qw(true false);

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

sub list ($self) {
  $self->render(snippets => $self->snippets->random(100));
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

sub edit ($self) {
  my $id      = $self->stash('id');
  my $snippet = $self->snippets->find($id);
  $self->render(snippet => $snippet);
}

sub meta ($self) {
  my $id       = $self->param('id');
  my $snippet  = $self->snippets->with_context($id);
  my $patterns = $self->patterns;
  my $licenses = $patterns->autocomplete;
  my $pattern  = $patterns->closest_pattern($snippet->{text}) // {};
  $self->render(json => {snippet => $snippet, licenses => $licenses, closest => $pattern->{license}});
}

sub _render_conflict ($self, $id, $validation) {
  my $conflicting_pattern = $self->patterns->find($id);
  $self->stash('conflicting_pattern', $conflicting_pattern);
  $self->stash('pattern_text',        $validation->param('pattern'));
  $self->render(template => 'snippet/conflict');
}

sub _create_pattern ($self, $packages, $validation) {
  $validation->required('license');
  $validation->required('pattern');
  $validation->required('risk')->num;
  $validation->optional('patent');
  $validation->optional('trademark');
  $validation->optional('export_restricted');
  return $self->reply->json_validation_error if $validation->has_error;

  my $pattern = $self->patterns->create(
    license => $validation->param('license'),
    pattern => $validation->param('pattern'),
    risk    => $validation->param('risk'),

    # TODO: those checkboxes aren't yet taken over
    patent            => $validation->param('patent'),
    trademark         => $validation->param('trademark'),
    export_restricted => $validation->param('export_restricted')
  );
  if ($pattern->{conflict}) {
    $self->_render_conflict($pattern->{conflict}, $validation);
    return 1;
  }
  $self->flash(success => 'Pattern has been created.');
  $self->stash(pattern => $pattern);

  my $db = $self->pg->db;
  for my $id (@$packages) {
    $self->packages->reindex($id, 3);
  }
  return undef;
}

# proxy function
sub decision ($self) {
  my $validation = $self->validation;
  $validation->optional('create-pattern');
  $validation->optional('mark-non-license');
  return $self->reply->json_validation_error if $validation->has_error;

  my %packages;
  my $db      = $self->pg->db;
  my $id      = $self->param('id');
  my $results = $db->query('select package from file_snippets where snippet=?', $id);
  while (my $next = $results->hash) {
    $packages{$next->{package}} = 1;
  }
  my $packages = [keys %packages];

  if ($validation->param('create-pattern')) {
    return if $self->_create_pattern($packages, $validation);
  }
  elsif ($validation->param('mark-non-license')) {
    $self->snippets->mark_non_license($id);
    for my $pkg (@$packages) {
      $self->packages->analyze($pkg, 4);
    }
  }
  $packages = [map { $self->packages->find($_) } @$packages];
  $self->stash(packages => $packages);
  $self->render;
}

sub top ($self) {
  my $db = $self->pg->db;

  my $result = $db->query(
    'select snippet,count(file) from snippets join file_snippets
       on file_snippets.snippet=snippets.id where snippets.license=TRUE
       group by snippet order by count desc limit 20'
  )->hashes;
  for my $snippet (@$result) {
    $snippet->{packages} = $db->query(
      'select count(distinct package)
       from file_snippets where snippet=?', $snippet->{snippet}
    )->hash->{count};
  }
  $self->render(snippets => $result);
}

sub from_file ($self) {
  my $db      = $self->pg->db;
  my $file_id = $self->stash('file');

  my $file = $db->select('matched_files', '*', {id => $file_id})->hash;
  return $self->reply->not_found unless $file;

  my $package = $db->select('bot_packages', '*', {id => $file->{package}})->hash;
  my $fn      = path($self->app->config->{checkout_dir}, $package->{name}, $package->{checkout_dir}, '.unpacked',
    $file->{filename});

  my $first_line = $self->stash('start');
  my $last_line  = $self->stash('end');
  my $text       = read_lines($fn, $first_line, $last_line);
  my $snippet    = $self->snippets->find_or_create("manual-" . time, $text);
  $db->insert('file_snippets',
    {package => $package->{id}, snippet => $snippet, sline => $first_line, eline => $last_line, file => $file_id});

  return $self->redirect_to('edit_snippet', id => $snippet);
}

1;
