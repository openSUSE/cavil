# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package Cavil::Controller::Upload;
use Mojo::Base 'Mojolicious::Controller', -signatures;

sub index ($self) {
  $self->render('upload/form');
}

sub store ($self) {
  my $wants_json = ($self->req->headers->accept // '') =~ /application\/json/;

  my $validation = $self->validation;
  $validation->required('name')->like(qr/^[A-Za-z0-9\-\.]+$/);
  $validation->required('priority')->num;
  $validation->required('tarball')->upload->size(1, undef);
  if ($validation->has_error) {
    my $failed = join(', ', @{$validation->failed});
    return $self->render(json => {error => "Invalid upload ($failed)"}, status => 400) if $wants_json;
    $self->flash(message => "Invalid upload ($failed)");
    return $self->redirect_to('upload');
  }

  my $name = $validation->param('name');

  # The archive itself is the only required input; the model hashes it, places it and enqueues the
  # review (see Cavil::Model::Packages::store_upload)
  my ($obj, $duplicate) = $self->packages->store_upload(
    $validation->param('tarball'),
    {
      name            => $name,
      priority        => $validation->param('priority'),
      requesting_user => $self->users->id_for_login($self->current_user),
      external_link   => 'upload'
    }
  );

  if ($duplicate) {
    my $msg = "Package $name with checksum $obj->{checkout_dir} already exists";
    return $self->render(json => {error => $msg}, status => 409) if $wants_json;
    $self->flash(message => $msg);
    return $self->redirect_to('upload');
  }

  my $id  = $obj->{id};
  my $msg = "Package $name has been uploaded and is now being processed";
  if ($wants_json) {
    return $self->render(json => {id => $id, name => $name, url => $self->url_for('package_details', id => $id)});
  }
  $self->flash(message => $msg);
  $self->redirect_to('dashboard');
}

1;
