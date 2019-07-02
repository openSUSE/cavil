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

sub create {
  my $self       = shift;
  my $validation = $self->validation;
  $validation->required('name')->like(qr!\S!);
  my $lid = $self->licenses->create(name => $validation->param('name'));
  return $self->render(text => $self->url_for('license_show', id => $lid));
}

sub create_pattern {
  my $self = shift;

  my $id      = $self->param('license');
  my $pattern = $self->param('pattern');

  my $licenses = $self->licenses;
  my $match    = $licenses->create_pattern(
    $id,
    packname  => $self->param('packname'),
    pattern   => $pattern,
    patent    => $self->param('patent'),
    trademark => $self->param('trademark'),
    opinion   => $self->param('opinion')
  );
  $licenses->expire_cache;
  $self->flash(success => 'Pattern has been created.');
  $self->redirect_to('edit_pattern', id => $match->{id});
}

sub edit_pattern {
  my $self    = shift;
  my $id      = $self->param('id');
  my $pattern = $self->licenses->pattern($id);
  Spooky::Patterns::XS::init_matcher();
  my $p1 = Spooky::Patterns::XS::normalize($pattern->{pattern});

  my $best;
  my $min = 10000;
  for my $p (@{$self->licenses->patterns($pattern->{license})}) {
    next if $p->{id} == $pattern->{id};
    my $p2 = Spooky::Patterns::XS::normalize($p->{pattern});
    my $d  = Spooky::Patterns::XS::distance($p1, $p2);
    if ($min > $d) {
      $min  = $d;
      $best = $p;
    }
  }
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
    $self->stash('diff',      $diff);
    $self->stash('next_best', $best->{id});
  }
  else {
    $self->stash('next_best', undef);
  }
  return $self->_edit_pattern($pattern);
}

sub list {
  my $self = shift;
  $self->render(licenses => $self->licenses->all);
}

sub new_pattern {
  my $self = shift;

  my $lname    = $self->param('license-name');
  my $lid      = $self->param('license-id');
  my $licenses = $self->licenses;
  $lid ||= $licenses->try_to_match_license($lname);
  $licenses->expire_cache;
  $self->stash('diff',      undef);
  $self->stash('next_best', 0);
  return $self->_edit_pattern({license => $lid});
}

# AJAX route
sub remove_pattern {
  my $self = shift;

  my $id       = $self->param('id');
  my $licenses = $self->licenses;
  my $pattern  = $licenses->pattern($id);
  $self->packages->reindex_matched_packages($id);
  $licenses->expire_cache;
  $self->licenses->remove_pattern($id);
  $self->render(json => 'ok');
}

sub show {
  my $self = shift;

  my $id = $self->param('id');
  $self->render(
    license  => $self->licenses->find($id),
    patterns => $self->licenses->patterns($id)
  );
}

sub update {
  my $self = shift;

  $self->licenses->update(
    $self->param('id'),
    url         => $self->param('url'),
    name        => $self->param('name'),
    risk        => $self->param('risk'),
    description => $self->param('description'),
    eula        => $self->param('eula'),
    nonfree     => $self->param('nonfree')
  );
  $self->flash(success => 'License has been updated.');
  $self->redirect_to('license_show');
}

sub update_pattern {
  my $self = shift;

  my $id    = $self->param('id');
  my $match = $self->licenses->pattern($id);

  # expire old license
  my $licenses = $self->licenses;
  $licenses->expire_cache;
  $licenses->update_pattern(
    $id,
    packname  => $self->param('packname'),
    pattern   => $self->param('pattern'),
    license   => $self->param('license'),
    patent    => $self->param('patent'),
    trademark => $self->param('trademark'),
    opinion   => $self->param('opinion')
  );
  $self->packages->mark_matched_for_reindex($id);
  $match = $licenses->pattern($id);
  $self->flash(
    success => 'Pattern has been updated, reindexing all affected packages.');
  $self->redirect_to('license_show', id => $match->{license});
}

sub _edit_pattern {
  my ($self, $match) = @_;

  my $license_id = $self->param('license_id') || $match->{license};

  $self->{licenses} ||= $self->licenses->all;
  my @licenses;
  for my $lic (sort { lc($a->{name}) cmp lc($b->{name}) } @{$self->{licenses}})
  {
    my $val = [$lic->{name} => $lic->{id}];
    if ($lic->{id} == $license_id) {
      push(@$val, (selected => 'selected'));
    }
    push(@licenses, $val);
  }
  $self->render(
    template => 'license/edit_pattern',
    match    => $match,
    licenses => \@licenses
  );
}

1;
