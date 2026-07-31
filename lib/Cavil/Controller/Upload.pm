# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package Cavil::Controller::Upload;
use Mojo::Base 'Mojolicious::Controller', -signatures;

use Digest::MD5;
use Mojo::File  qw(path);
use Cavil::Util qw(incoming_priority);

sub index ($self) {
  $self->render('upload/form');
}

sub store ($self) {
  my $wants_json = ($self->req->headers->accept // '') =~ /application\/json/;

  # No package metadata is required for an arbitrary archive upload; the name is only used
  # for the checkout directory and queue, and is prefilled from the filename in the UI
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

  my $upload = $validation->param('tarball');
  my $file   = $upload->asset->to_file;

  my $name     = $validation->param('name');
  my $filename = path($upload->filename)->basename;

  # The checkout directory is a content hash of the uploaded archive (stream from the start
  # of the file, the asset handle may be positioned at EOF after the upload was stored)
  my $md5    = Digest::MD5->new;
  my $handle = $file->handle;
  seek $handle, 0, 0;
  $md5->addfile($handle);
  my $sum = $md5->hexdigest;

  my $pkgs = $self->packages;
  if (my $obj = $pkgs->find_by_name_and_md5($name, $sum)) {
    my $msg = "Package $name with checksum $sum already exists";
    return $self->render(json => {error => $msg}, status => 409) if $wants_json;
    $self->flash(message => $msg);
    return $self->redirect_to('upload');
  }

  my $user_id = $self->users->id_for_login($self->current_user);
  my $id      = $pkgs->add(
    name            => $name,
    checkout_dir    => $sum,
    api_url         => '',
    requesting_user => $user_id,
    project         => '',
    priority        => $validation->param('priority'),
    package         => $name,
    created         => undef,
    srcmd5          => $sum,
  );
  my $dir = path($self->app->config->{checkout_dir}, $name, $sum)->make_path;
  $file->move_to($dir->child($filename));
  my $obj = $pkgs->find($id);
  $obj->{external_link} = 'upload';
  $pkgs->update($obj);
  $pkgs->imported($id);

  # An arriving package like any other, and the review priority picked on the upload form moves it around
  # inside the incoming band the same way the one a Bot API request carries does
  $pkgs->unpack($id, incoming_priority($validation->param('priority')));

  my $msg = "Package $name has been uploaded and is now being processed";
  if ($wants_json) {
    return $self->render(json => {id => $id, name => $name, url => $self->url_for('package_details', id => $id)});
  }
  $self->flash(message => $msg);
  $self->redirect_to('dashboard');
}

1;
