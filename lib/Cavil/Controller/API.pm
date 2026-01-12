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

package Cavil::Controller::API;
use Mojo::Base 'Mojolicious::Controller', -signatures;

sub identify ($self) {
  my $name     = $self->stash('name');
  my $checksum = $self->stash('checksum');
  my $pkg      = $self->packages->find_by_name_and_md5($name, $checksum);
  return $self->render(json => {error => 'Package not found'}, status => 404) unless $pkg;
  $self->render(json => {id => $pkg->{id}});
}

sub source ($self) {

  my $validation = $self->validation;
  $validation->required('api')->like(qr!^https?://.+!i);
  $validation->required('project');
  $validation->required('package');
  $validation->optional('rev')->like(qr/^[a-f0-9]+$/i);
  return $self->reply->json_validation_error if $validation->has_error;

  my $api     = $validation->param('api');
  my $project = $validation->param('project');
  my $pkg     = $validation->param('package');
  my $rev     = $validation->param('rev');

  # Get package infomation, rev may be pointing to link, so we need the
  # canonical srcmd5
  my $obs  = $self->app->obs;
  my $info = eval { $obs->package_info($api, $project, $pkg, {rev => $rev}) };
  unless ($info && $info->{verifymd5}) {
    return $self->render(json => {error => 'Package not found'}, status => 404);
  }
  my ($srcpkg, $verifymd5) = @{$info}{qw(package verifymd5)};

  my $pkgs = $self->packages;
  return $self->render(json => {error => 'Package not found'}, status => 404)
    unless my $obj = $self->packages->find_by_name_and_md5($srcpkg, $verifymd5);

  my $history = [];
  $history = [map { $_->{id} } @{$pkgs->history(@{$obj}{qw(name checksum id)})}] if $obj->{checksum};
  $self->render(json => {review => $obj->{id}, history => $history});
}

sub status ($self) {
  my $name = $self->stash('name');
  $self->render(json => {package => $name, requests => $self->packages->states($name)});
}

sub whoami ($self) {
  my $user = $self->current_user;
  my $id   = $self->users->id_for_login($user);
  $self->render(json => {id => $id, user => $user});
}

1;
