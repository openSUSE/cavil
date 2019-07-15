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
use Mojo::Base 'Mojolicious::Controller';
use Mojo::JSON 'decode_json';
use Cavil::Text 'closest_pattern';
use Encode qw(from_to decode);
use Mojo::File 'path';

sub list {
  my $self = shift;

  $self->render(snippets => $self->snippets->random(100));
}

sub update {
  my $self = shift;

  my $db     = $self->pg->db;
  my $params = $self->req->params->to_hash;
  for my $param (sort keys %$params) {
    next unless $param =~ m/g_(\d+)/;
    my $id      = $1;
    my $license = $params->{$param};
    $db->update(
      'snippets',
      {license => $license, approved => 1, classified => 1},
      {id      => $id}
    );
  }
  $self->redirect_to('snippets');
}

sub edit {
  my $self = shift;

  my $id      = $self->param('id');
  my $snippet = $self->snippets->find($id);

  Spooky::Patterns::XS::init_matcher();

  my $cache = $self->app->home->child('cache', 'cavil.pattern.words');
  my $data  = decode_json $cache->slurp;

  my ($best, $sim) = closest_pattern($snippet->{text}, undef, $data);
  $best = $self->patterns->find($best->{id});

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
  my $package  = $self->packages->find($example->{package});
  my $patterns = $db->query(
    'select * from pattern_matches
     where file=? and sline>=? and eline<=?', $example->{file},
    $example->{sline}, $example->{eline}
  )->hashes;
  my $fn = path(
    $self->app->config->{checkout_dir},
    $package->{name}, $package->{checkout_dir},
    '.unpacked', $example->{filename}
  );

  my %needed_lines;
  for (my $line = $example->{sline}; $line <= $example->{eline}; $line += 1) {
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
  $snippet->{text} = $text;

  # not preserved by textarea/codemirror
  $example->{sline} += 1 if $text =~ m/^\n/;
  $self->render(
    patterns      => $patterns,
    package       => $package,
    example       => $example,
    package_count => $package_count,
    file_count    => $file_count,
    snippet       => $snippet,
    best          => $best,
    similarity    => int($sim * 1000 + 0.5) / 10
  );
}

sub _render_conflict {
  my ($self, $id) = @_;
  my $conflicting_pattern = $self->patterns->find($id);
  $self->stash('conflicting_pattern', $conflicting_pattern);
  $self->stash('pattern_text',        $self->param('pattern'));
  $self->render(template => 'snippet/conflict');
}

sub _create_pattern {
  my ($self, $packages) = @_;

  my $pattern = $self->patterns->create(
    license => $self->param('license'),
    pattern => $self->param('pattern'),
    risk    => $self->param('risk'),

    # TODO: those checkboxes aren't yet taken over
    eula      => $self->param('eula'),
    nonfree   => $self->param('nonfree'),
    patent    => $self->param('patent'),
    trademark => $self->param('trademark'),
    opinion   => $self->param('opinion')
  );
  if ($pattern->{conflict}) {
    $self->_render_conflict($pattern->{conflict});
    return 1;
  }
  $self->flash(success => 'Pattern has been created.');
  $self->stash(pattern => $pattern);

  my $db = $self->pg->db;
  for my $pkg (@$packages) {
    my $pkg = $db->update(
      'bot_packages',
      {indexed => undef, checksum => undef},
      {id        => $pkg, '-not_bool' => 'obsolete', indexed => {'!=', undef}},
      {returning => 'id'}
    )->hash;
    next unless $pkg;
    $db->delete('bot_reports', {package => $pkg->{id}});
    $self->packages->index($pkg->{id}, 7);
  }
  return undef;
}

# proxy function
sub decision {
  my $self = shift;

  my $db = $self->pg->db;

  my %packages;
  my $results = $db->query('select package from file_snippets where snippet=?',
    $self->param('id'));
  while (my $next = $results->hash) {
    $packages{$next->{package}} = 1;
  }
  my $packages = [keys %packages];

  if ($self->param('create-pattern')) {
    return if $self->_create_pattern($packages);
  }
  elsif ($self->param('mark-non-license')) {
    $self->snippets->mark_non_license($self->param('id'));
    for my $pkg (@$packages) {
      $self->packages->analyze($pkg, 7);
    }
  }
  $packages = [map { $self->packages->find($_) } @$packages];
  $self->stash(packages => $packages);
  $self->render;
}

sub top {
  my $self = shift;

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

1;
