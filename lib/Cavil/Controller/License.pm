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
use Mojo::Base 'Mojolicious::Controller';
use Algorithm::Diff 'sdiff';

sub create_pattern {
  my $self = shift;

  my $license = $self->param('license');
  my $pattern = $self->param('pattern');

  my $patterns = $self->patterns;
  my $match    = $patterns->create(
    license   => $license,
    packname  => $self->param('packname'),
    pattern   => $pattern,
    risk      => $self->param('risk'),
    patent    => $self->param('patent'),
    trademark => $self->param('trademark'),
    opinion   => $self->param('opinion')
  );
  if ($match->{conflict}) {
    my $conflicting_pattern = $self->patterns->find($match->{conflict});
    $self->stash('conflicting_pattern', $conflicting_pattern);
    $self->stash('pattern_text',        $pattern);
    $self->render(template => 'snippet/conflict');
    return;
  }
  $self->flash(success => 'Pattern has been created.');
  $self->redirect_to('edit_pattern', id => $match->{id});
}

sub edit_pattern {
  my $self    = shift;
  my $id      = $self->param('id');
  my $pattern = $self->patterns->find($id);

  my $bag   = Spooky::Patterns::XS::init_bag_of_patterns;
  my $cache = $self->app->home->child('cache', 'cavil.pattern.bag');
  $bag->load($cache);

  my $result = $bag->best_for($pattern->{pattern}, 2);
  my $best   = $result->[0];

  # likely perfect match
  $best = $result->[1] if $best->{pattern} && $best->{pattern} == $id;

  my $sim = $best->{match};
  $best = $self->patterns->find($best->{pattern});

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

sub list {
  my $self = shift;
  $self->render(licenses => $self->patterns->all_licenses);
}

sub new_pattern {
  my $self = shift;

  my $lname = $self->param('license-name');
  $self->stash('diff',      undef);
  $self->stash('next_best', 0);
  return $self->_edit_pattern({license => $lname});
}

# AJAX route
sub remove_pattern {
  my $self = shift;

  my $id       = $self->param('id');
  my $patterns = $self->patterns;
  my $pattern  = $patterns->find($id);
  $self->packages->reindex_matched_packages($id);
  $patterns->expire_cache;
  $patterns->remove($id);
  $self->render(json => 'ok');
}

sub show {
  my $self = shift;
  my $name = $self->param('name');
  $name = '' if $name eq '*Pattern without license*';
  $self->render(license => $name, patterns => $self->patterns->for_license($name));
}

sub update_pattern {
  my $self = shift;

  my $id       = $self->param('id');
  my $patterns = $self->patterns;

  # expire old license pattern
  $patterns->expire_cache;
  my $result = $patterns->update(
    $id,
    packname  => $self->param('packname'),
    pattern   => $self->param('pattern'),
    license   => $self->param('license'),
    patent    => $self->param('patent'),
    trademark => $self->param('trademark'),
    opinion   => $self->param('opinion'),
    risk      => $self->param('risk')
  );
  if ($result->{conflict}) {

    my $conflicting_pattern = $self->patterns->find($result->{conflict});
    $self->stash('conflicting_pattern', $conflicting_pattern);
    $self->stash('pattern_text',        $self->param('pattern'));
    return $self->render(template => 'snippet/conflict');
  }
  $self->packages->mark_matched_for_reindex($id);
  $self->app->minion->enqueue(pattern_stats => [] => {priority => 9});
  $self->flash(success => 'Pattern has been updated, reindexing all affected packages.');
  $self->redirect_to('edit_pattern', id => $id);
}

sub _edit_pattern {
  my ($self, $match) = @_;

  $self->render(template => 'license/edit_pattern', match => $match);
}

1;
