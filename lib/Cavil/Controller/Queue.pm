# Copyright (C) 2018-2020 SUSE LLC
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

package Cavil::Controller::Queue;
use Mojo::Base 'Mojolicious::Controller';

use Mojo::File 'path';

sub create_package {
  my $self = shift;

  my $validation = $self->validation;
  $validation->required('api')->like(qr!^https?://.+!i);
  $validation->required('project');
  $validation->required('package');
  $validation->optional('rev')->like(qr/^[a-f0-9]+$/i);
  $validation->optional('created');
  $validation->optional('external_link');
  $validation->optional('priority')->like(qr/^\d+$/);
  return $self->reply->json_validation_error if $validation->has_error;

  my $api     = $validation->param('api');
  my $project = $validation->param('project');
  my $pkg     = $validation->param('package');
  my $rev     = $validation->param('rev');
  my $created = $validation->param('created');
  my $link    = $validation->param('external_link');
  my $prio    = $validation->param('priority') || 5;

  my $app    = $self->app;
  my $config = $app->config;
  my $obs    = $app->obs;

  # Get package infomation, rev may be pointing to link, so we need the
  # canonical srcmd5
  my $info = eval { $obs->package_info($api, $project, $pkg, {rev => $rev}) };
  unless ($info && $info->{verifymd5}) {
    $self->_log("Couldn't get package info", $api, $project, $pkg, $rev, $@);
    return $self->render(json => {error => 'Package not found'}, status => 404);
  }
  my ($srcpkg, $srcmd5, $verifymd5) = @{$info}{qw(package srcmd5 verifymd5)};

  # Check if we need to import from OBS
  my $dir    = path($config->{checkout_dir}, $srcpkg, $verifymd5);
  my $create = !-e $dir;

  my $user = $self->users->licensedigger;
  my $pkgs = $self->packages;
  my $obj  = $pkgs->find_by_name_and_md5($srcpkg, $verifymd5);
  if (!$obj) {
    my $id = $pkgs->add(
      name            => $srcpkg,
      checkout_dir    => $verifymd5,
      api_url         => $api,
      requesting_user => $user->{id},
      project         => $project,
      priority        => $prio,
      package         => $pkg,
      created         => $created,
      srcmd5          => $srcmd5,
    );
    $obj = $pkgs->find($id);
  }
  $obj->{external_link} //= $link;
  $obj->{obsolete} = 0;
  $pkgs->update($obj);
  $pkgs->obs_import(
    $obj->{id},
    {
      api       => $api,
      project   => $project,
      pkg       => $pkg,
      srcpkg    => $srcpkg,
      rev       => $rev,
      srcmd5    => $srcmd5,
      verifymd5 => $verifymd5,
      priority  => $prio
    },
    $prio + 10
  ) if $create;

  $self->render(json => {saved => $obj});
}

sub create_request {
  my $self = shift;

  my $validation = $self->validation;
  $validation->required('external_link');
  $validation->required('package')->like(qr/^\d+$/);
  return $self->reply->json_validation_error if $validation->has_error;

  my $link = $validation->param('external_link');
  my $pkgs = $validation->every_param('package');

  my $requests = $self->requests;
  $requests->add($link, $_) for @$pkgs;

  $self->render(json => {created => $link});
}

sub import_package {
  my $self = shift;

  my $validation = $self->validation;
  $validation->required('result');
  $validation->optional('approved_by');
  $validation->optional('state');
  $validation->optional('priority');
  $validation->optional('external_link');
  return $self->reply->json_validation_error if $validation->has_error;

  my $pkgs = $self->packages;
  my $id   = $self->param('id');
  my $obj  = $pkgs->find($id);

  my $reindex;
  if (my $link = $validation->param('external_link')) {
    $obj->{external_link} = $link;
  }
  if (my $priority = $validation->param('priority')) {
    $obj->{priority} = $priority;
  }
  $obj->{result} = $validation->param('result');
  if (my $state = $validation->param('state')) {
    $obj->{state} = $state;
    if ($state eq 'new') {
      $obj->{obsolete} = 0;
      $reindex = 1;
    }
  }
  if (my $approved = $validation->param('approved_by')) {
    my $user = $self->users->find_or_create(login => $approved);
    $obj->{reviewing_user} = $user->{id};
  }
  $pkgs->update($obj);
  $pkgs->reindex($id) if $reindex;

  return $self->render(json => {imported => $obj});
}

sub list_requests {
  my $self = shift;
  $self->render(json => {requests => $self->requests->all});
}

sub package_status {
  my $self = shift;

  return $self->render(json => {error => 'No such package'}, status => 404)
    unless my $pkg = $self->packages->find($self->param('id'));

  return $self->_render_state($pkg);
}

sub remove_request {
  my $self = shift;

  my $validation = $self->validation;
  $validation->required('external_link');
  return $self->reply->json_validation_error if $validation->has_error;

  my $link    = $validation->param('external_link');
  my $removed = $self->requests->remove($link);
  my $pkgs    = $self->packages;
  for my $pkg (@$removed) {
    $pkg = $pkgs->find($pkg);
    if ($pkg->{state} eq 'new' || $pkg->{state} eq 'unacceptable') {
      $pkg->{state}    = 'obsolete';
      $pkg->{obsolete} = 1;

      $pkgs->update($pkg);
    }
  }

  $self->render(json => {removed => $removed});
}

sub update_package {
  my $self = shift;

  my $validation = $self->validation;
  $validation->required('priority')->like(qr/^\d+$/);
  return $self->reply->json_validation_error if $validation->has_error;

  my $pkgs = $self->packages;
  my $obj  = $pkgs->find($self->param('id'));
  $obj->{priority} = $validation->param('priority');
  $pkgs->update($obj);

  $self->render(json => {updated => $obj});
}

sub update_product {
  my $self = shift;

  my $validation = $self->validation;
  $validation->required('id')->like(qr/^\d+$/);
  return $self->reply->json_validation_error if $validation->has_error;

  my $products = $self->products;
  my $obj      = $products->find_or_create($self->param('name'));

  # This might take some time for big products
  $self->inactivity_timeout(600);
  $products->update($obj->{id}, $self->every_param('id'));

  $self->render(json => {updated => $obj->{id}});
}

sub _errors_to_markdown {
  my @errors   = @_;
  my $markdown = '';
  $markdown .= "* $_\n" for @errors;
  return $markdown;
}

sub _log {
  my ($self, $message, $api, $project, $pkg, $rev, $error) = @_;
  my $target = "api=$api, project=$project, package=$pkg" . ($rev ? ", rev=$rev" : '');
  $self->app->log->error("$message ($target): $error");
}

sub _render_state {
  my ($self, $pkg) = @_;

  my %reply = %$pkg;
  $reply{result} = $pkg->{result} if $pkg->{result};
  if ($pkg->{reviewing_user}) {
    my $user = $self->users->find(id => $pkg->{reviewing_user});
    $reply{reviewing_user} = $user->{login};
  }
  return $self->render(json => \%reply);
}

1;
