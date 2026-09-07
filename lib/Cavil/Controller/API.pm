# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package Cavil::Controller::API;
use Mojo::Base 'Mojolicious::Controller', -signatures;

use List::Util qw(uniq);
use Mojo::JSON qw(true false);

sub identify ($self) {
  my $name     = $self->stash('name');
  my $checksum = $self->stash('checksum');
  my $pkg      = $self->packages->find_by_name_and_md5($name, $checksum);
  return $self->render(json => {error => 'Package not found'}, status => 404) unless $pkg;
  $self->render(json => {id => $pkg->{id}});
}

sub reports ($self) {
  my $validation = $self->validation;
  $validation->required('external_link');
  return $self->reply->json_validation_error if $validation->has_error;

  my $external_link = $validation->param('external_link');
  my $request_ids   = $self->requests->find_by_link($external_link);
  my $package_ids   = $self->packages->find_by_link($external_link);
  my @ids           = sort { $a <=> $b } uniq(@$request_ids, @$package_ids);

  $self->render(json => {reports => [map { {id => $_} } @ids]});
}

sub package_search ($self) {
  my $v = $self->validation;
  $v->optional('name');         # exact package name
  $v->optional('component');    # vendored component name or purl
  $v->optional('limit')->num;
  $v->optional('offset')->num;
  return $self->reply->json_validation_error if $v->has_error;

  my $limit  = $v->param('limit')  // 25;
  my $offset = $v->param('offset') // 0;
  $limit  = 100 if $limit > 100;
  $limit  = 1   if $limit < 1;
  $offset = 0   if $offset < 0;

  # Same package search as the web UI, but the API never exposes embargoed or obsolete packages
  my $component = $v->param('component');
  my $page      = $self->packages->paginate_review_search(
    scalar $v->param('name'),
    {
      search        => '',
      component     => $component,
      limit         => $limit,
      offset        => $offset,
      not_obsolete  => 'true',
      not_embargoed => 'true'
    }
  );

  # When searching by component, attach the matching components so a caller sees the exact version shipped
  my @ids        = map { $_->{id} } @{$page->{page}};
  my $components = length($component // '') ? $self->packages->matching_components(\@ids, $component) : {};

  my @packages = map {
    {
      id         => $_->{id},
      name       => $_->{package},
      state      => $_->{state},
      checksum   => $_->{checksum},
      components => $components->{$_->{id}} // []
    }
  } @{$page->{page}};

  $self->render(
    json => {packages => \@packages, total => $page->{total}, start => $page->{start}, end => $page->{end}});
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

  # Resolve links before using the source checksum as identity.
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

sub upload ($self) {

  # Submitting runs the full pipeline and adds to the legal backlog, so it takes the same infra capability the
  # web upload form requires, plus a write-scoped key.
  my %scopes = map { $_ => 1 } @{$self->current_user_scopes};
  return $self->render(
    json   => {error => 'It appears you have insufficient permissions for accessing this resource'},
    status => 403
  ) unless $self->current_user_can('infra') && $scopes{'cavil:write'};

  my $validation = $self->validation;
  $validation->required('name')->like(qr/^[A-Za-z0-9\-\.]+$/);
  $validation->required('priority')->num;
  $validation->required('tarball')->upload->size(1, undef);
  $validation->required('checksum')->like(qr/^[a-f0-9]{32}$/i);
  $validation->optional('external_link');
  return $self->reply->json_validation_error if $validation->has_error;

  my ($obj, $duplicate) = eval {
    $self->packages->store_upload(
      $validation->param('tarball'),
      {
        name            => $validation->param('name'),
        priority        => $validation->param('priority'),
        requesting_user => $self->users->id_for_login($self->current_user),
        external_link   => $validation->param('external_link'),
        checksum        => $validation->param('checksum')
      }
    );
  };
  if (my $err = $@) {
    return $self->render(json => {error => 'Checksum mismatch'}, status => 400)
      if ref $err eq 'HASH' && $err->{checksum_mismatch};
    $self->app->log->error("Upload of package @{[$validation->param('name')]} failed: $err");
    return $self->render(json => {error => 'Upload failed'}, status => 500);
  }

  $self->render(json => {saved => $obj, duplicate => $duplicate ? \1 : \0});
}

sub whoami ($self) {
  my $user = $self->current_user;
  my $id   = $self->users->id_for_login($user);
  $self->render(
    json => {
      id           => $id,
      user         => $user,
      roles        => $self->current_user_roles,
      write_access => $self->current_user_has_write_access ? true : false
    }
  );
}

1;
