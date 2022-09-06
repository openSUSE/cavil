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

use Encode qw(from_to decode);
use Mojo::File 'path';

sub list ($self) {
  $self->render(snippets => $self->snippets->random(100));
}

sub update ($self) {
  my $db     = $self->pg->db;
  my $params = $self->req->params->to_hash;
  for my $param (sort keys %$params) {
    next unless $param =~ m/g_(\d+)/;
    my $id      = $1;
    my $license = $params->{$param};
    $db->update('snippets', {license => $license, approved => 1, classified => 1}, {id => $id});
  }
  $self->redirect_to('snippets');
}

sub edit ($self) {
  my $id      = $self->stash('id');
  my $snippet = $self->snippets->find($id);

  my $bag   = Spooky::Patterns::XS::init_bag_of_patterns;
  my $cache = $self->app->home->child('cache', 'cavil.pattern.bag');
  $bag->load($cache);

  my $best = $bag->best_for($snippet->{text}, 1)->[0];
  my $sim  = $best->{match} // 0;
  $best = $self->patterns->find($best->{pattern});

  my $db            = $self->pg->db;
  my $package_count = $db->query(
    'select count(distinct package)
       from file_snippets where snippet=?', $id
  )->hash->{count};
  my $file_count = $db->query(
    'select count(distinct file)
       from file_snippets where snippet=?', $id
  )->hash->{count};
  my $example = $db->query(
    'select fs.package, file, filename,
       sline,eline from file_snippets fs
       join matched_files m on m.id=fs.file
       where snippet=? limit 1', $id
  )->hash;

  my $package;
  my %lines;

  if ($example) {
    $package = $self->packages->find($example->{package});
    my $patterns = $db->query(
      'select lp.id,lp.license,sline,eline from pattern_matches
       join license_patterns lp on lp.id = pattern_matches.pattern
       where file=? and sline>=? and eline<=? order by sline', $example->{file}, $example->{sline}, $example->{eline}
    )->hashes;

    for my $pattern (@$patterns) {
      for (my $line = $pattern->{sline}; $line <= $pattern->{eline}; $line += 1) {
        my $cm_line = $line - $example->{sline};

        # keywords overwrite everything
        if (!$pattern->{license}) {
          $lines{$cm_line} = {pattern => $pattern->{id}, keyword => 1};
        }
        else {
          $lines{$cm_line} ||= {pattern => $pattern->{id}, keyword => 0};
        }
      }
    }
    my $fn = path(
      $self->app->config->{checkout_dir},
      $package->{name}, $package->{checkout_dir},
      '.unpacked',      $example->{filename}
    );

    $snippet->{text}  = _read_lines($fn, $example->{sline}, $example->{eline});
    $example->{delta} = 0;
  }

  # not preserved by textarea/codemirror
  $example->{delta} = 1 if $snippet->{text} =~ m/^\n/;
  $self->render(
    patterns      => \%lines,
    package       => $package,
    example       => $example,
    package_count => $package_count,
    file_count    => $file_count,
    snippet       => $snippet,
    best          => $best,
    similarity    => int($sim * 1000 + 0.5) / 10
  );
}

sub _read_lines ($fn, $start_line, $end_line) {
  my %needed_lines;
  for (my $line = $start_line; $line <= $end_line; $line += 1) {
    $needed_lines{$line} = 1;
  }

  my $text = '';
  for my $row (@{Spooky::Patterns::XS::read_lines($fn, \%needed_lines)}) {
    my ($index, $pid, $line) = @$row;

    # Sanitize line - first try UTF-8 strict and then LATIN1
    eval { $line = decode 'UTF-8', $line, Encode::FB_CROAK; };
    if ($@) {
      from_to($line, 'ISO-LATIN-1', 'UTF-8', Encode::FB_DEFAULT);
      $line = decode 'UTF-8', $line, Encode::FB_DEFAULT;
    }
    $text .= "$line\n";
  }
  return $text;
}

sub _render_conflict ($self, $id, $validation) {
  my $conflicting_pattern = $self->patterns->find($id);
  $self->stash('conflicting_pattern', $conflicting_pattern);
  $self->stash('pattern_text',        $validation->param('pattern'));
  $self->render(template => 'snippet/conflict');
}

sub _create_pattern ($self, $packages, $validation) {
  my $pattern = $self->patterns->create(
    license => $validation->param('license'),
    pattern => $validation->param('pattern'),
    risk    => $validation->param('risk'),

    # TODO: those checkboxes aren't yet taken over
    patent    => $validation->param('patent'),
    trademark => $validation->param('trademark'),
    opinion   => $validation->param('opinion')
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
  $validation->required('id')->num;
  $validation->required('license');
  $validation->required('pattern');
  $validation->required('risk')->num;
  $validation->optional('patent');
  $validation->optional('trademark');
  $validation->optional('opinion');
  $validation->optional('create-pattern');
  $validation->optional('mark-non-license');
  return $self->reply->json_validation_error if $validation->has_error;

  my $db = $self->pg->db;

  my %packages;
  my $results = $db->query('select package from file_snippets where snippet=?', $validation->param('id'));
  while (my $next = $results->hash) {
    $packages{$next->{package}} = 1;
  }
  my $packages = [keys %packages];

  if ($validation->param('create-pattern')) {
    return if $self->_create_pattern($packages, $validation);
  }
  elsif ($validation->param('mark-non-license')) {
    $self->snippets->mark_non_license($validation->param('id'));
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
  my $text       = _read_lines($fn, $first_line, $last_line);
  my $snippet    = $self->snippets->find_or_create("manual-" . time, $text);
  $db->insert('file_snippets',
    {package => $package->{id}, snippet => $snippet, sline => $first_line, eline => $last_line, file => $file_id});

  return $self->redirect_to('edit_snippet', id => $snippet);
}

1;
