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
use Mojo::Base 'Mojolicious::Controller', -signatures;

use Mojo::File 'path';

sub create_package ($self) {
  my $validation = $self->validation;

  $validation->optional('type')->in('obs', 'git');
  my $type = $validation->param('type') || 'obs';

  if ($type eq 'git') {
    $validation->required('rev')->like(qr/^[a-f0-9]+$/i);
    $validation->optional('project');
  }
  else {
    $validation->optional('rev')->like(qr/^[a-f0-9]+$/i);
    $validation->required('project');
  }

  $validation->required('api')->like(qr!^https?://.+!i);
  $validation->required('package');
  $validation->optional('created');
  $validation->optional('external_link');
  $validation->optional('priority')->like(qr/^\d+$/);

  return $self->reply->json_validation_error if $validation->has_error;

  my $api     = $validation->param('api');
  my $project = $validation->param('project') // '';
  my $pkg     = $validation->param('package');
  my $rev     = $validation->param('rev');
  my $created = $validation->param('created');
  my $link    = $validation->param('external_link');
  my $prio    = $validation->param('priority') || 5;

  my $app    = $self->app;
  my $config = $app->config;

  my ($srcpkg, $srcmd5, $verifymd5);
  if ($type eq 'git') {
    ($srcpkg, $srcmd5, $verifymd5) = ($pkg, $rev, $rev);
  }

  # Get package infomation, rev may be pointing to link, so we need the
  # canonical srcmd5
  else {
    my $obs  = $app->obs;
    my $info = eval { $obs->package_info($api, $project, $pkg, {rev => $rev}) };
    unless ($info && $info->{verifymd5}) {
      $self->_log("Couldn't get package info", $api, $project, $pkg, $rev, $@);
      return $self->render(json => {error => 'Package not found'}, status => 404);
    }
    ($srcpkg, $srcmd5, $verifymd5) = @{$info}{qw(package srcmd5 verifymd5)};
  }

  # Check if we need to import
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
      type            => $type
    );
    $obj = $pkgs->find($id);
  }

  # Product imports are low priority, and we want real requests if possible
  $obj->{external_link} //= $link;
  $obj->{external_link} = $link if $link && $prio >= $obj->{priority};

  $obj->{obsolete} = 0;
  $pkgs->update($obj);
  if ($create) {
    if ($type eq 'git') {
      $pkgs->git_import($obj->{id},
        {url => $api, pkg => $pkg, hash => $rev, external_link => $obj->{external_link}, priority => $prio},
        $prio + 10);
    }
    else {
      $pkgs->obs_import(
        $obj->{id},
        {
          api           => $api,
          project       => $project,
          pkg           => $pkg,
          srcpkg        => $srcpkg,
          rev           => $rev,
          srcmd5        => $srcmd5,
          verifymd5     => $verifymd5,
          external_link => $obj->{external_link},
          priority      => $prio
        },
        $prio + 10
      );
    }
  }

  $self->render(json => {saved => $obj});
}

sub create_request ($self) {
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

sub import_package ($self) {
  my $validation = $self->validation;
  $validation->optional('state')->in('new');
  $validation->optional('priority');
  $validation->optional('external_link');
  return $self->reply->json_validation_error if $validation->has_error;

  my $pkgs = $self->packages;
  my $id   = $self->stash('id');
  my $obj  = $pkgs->find($id);

  my $reindex;
  if (my $link = $validation->param('external_link')) {
    $obj->{external_link} = $link;
  }
  if (my $priority = $validation->param('priority')) {
    $obj->{priority} = $priority;
  }
  if (my $state = $validation->param('state')) {
    $obj->{state} = $state;
    if ($state eq 'new') {
      $obj->{result}         = undef;
      $obj->{reviewed}       = undef;
      $obj->{reviewing_user} = undef;
      $obj->{obsolete}       = 0;
      $reindex               = 1;
    }
  }
  $pkgs->update($obj);
  $pkgs->reindex($id) if $reindex;

  return $self->render(json => {imported => $obj});
}

sub list_requests ($self) {
  $self->render(json => {requests => $self->requests->all});
}

sub package_status ($self) {
  return $self->render(json => {error => 'No such package'}, status => 404)
    unless my $pkg = $self->packages->find($self->stash('id'));

  my %reply = %$pkg;
  $reply{result} = $pkg->{result} if $pkg->{result};
  if ($pkg->{reviewing_user}) {
    my $user = $self->users->find(id => $pkg->{reviewing_user});
    $reply{reviewing_user} = $user->{login};
  }
  return $self->render(json => \%reply);
}

sub remove_request ($self) {
  my $validation = $self->validation;
  $validation->required('external_link');
  return $self->reply->json_validation_error if $validation->has_error;

  my $link    = $validation->param('external_link');
  my $removed = $self->requests->remove($link);
  my $pkgs    = $self->packages;
  for my $id (@$removed) {
    $pkgs->obsolete_if_not_in_product($id);
  }

  $self->render(json => {removed => $removed});
}

sub remove_product ($self) {
  my $validation = $self->validation;
  $validation->required('name');
  return $self->reply->json_validation_error if $validation->has_error;

  my $removed = $self->products->remove($validation->param('name'));
  $self->render(json => {removed => $removed});
}

sub update_package ($self) {
  my $validation = $self->validation;
  $validation->required('priority')->like(qr/^\d+$/);
  return $self->reply->json_validation_error if $validation->has_error;

  my $pkgs = $self->packages;
  my $obj  = $pkgs->find($self->stash('id'));
  $obj->{priority} = $validation->param('priority');
  $pkgs->update($obj);

  $self->render(json => {updated => $obj});
}

sub update_product ($self) {
  my $validation = $self->validation;
  $validation->required('id')->like(qr/^\d+$/);
  return $self->reply->json_validation_error if $validation->has_error;

  my $name = $self->stash('name');
  $self->log->info("Updating product $name");
  my $products = $self->products;
  my $obj      = $products->find_or_create($name);

  # This might take some time for big products
  $self->inactivity_timeout(600);
  $products->update($obj->{id}, $validation->every_param('id'));

  $self->render(json => {updated => $obj->{id}});
}

sub _errors_to_markdown (@errors) {
  my $markdown = '';
  $markdown .= "* $_\n" for @errors;
  return $markdown;
}

sub _log ($self, $message, $api, $project, $pkg, $rev, $error) {
  my $target = "api=$api, project=$project, package=$pkg" . ($rev ? ", rev=$rev" : '');
  $self->app->log->error("$message ($target): $error");
}

1;
