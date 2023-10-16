# Copyright (C) 2020 SUSE Linux GmbH
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

package Cavil::Controller::Upload;
use Mojo::Base 'Mojolicious::Controller', -signatures;

use Digest::MD5;
use Mojo::File qw(path);
use Mojo::JSON qw(encode_json);
use Mojo::Util qw(md5_sum);

sub index ($self) {
  $self->render('upload/form');
}

sub store ($self) {
  my $validation = $self->validation;
  $validation->required('name')->like(qr/^[A-Za-z0-9\-\.]+$/);
  $validation->required('licenses')->like(qr/^[A-Za-z0-9\-\.]+$/);
  $validation->required('version')->like(qr/^[0-9\.]+$/);
  $validation->required('priority')->num;
  $validation->required('tarball')->upload->size(1, undef);
  return $self->render('upload/form') if $validation->has_error;

  my $upload = $validation->param('tarball');
  my $file   = $upload->asset->to_file;
  my $md5    = Digest::MD5->new;
  $md5->addfile($file->handle);
  my $name     = $validation->param('name');
  my $licenses = $validation->param('licenses');
  my $version  = $validation->param('version');
  my $sum      = md5_sum($name . $version . $licenses . $md5->hexdigest);

  my $pkgs = $self->packages;
  if (my $obj = $pkgs->find_by_name_and_md5($name, $sum)) {
    $self->flash(message => "Package $name with checksum $sum already exists");
    return $self->render('dashboard');
  }

  my $user = $self->users->find(login => $self->current_user);
  my $id   = $pkgs->add(
    name            => $name,
    checkout_dir    => $sum,
    api_url         => '',
    requesting_user => $user->{id},
    project         => '',
    priority        => $validation->param('priority'),
    package         => $name,
    created         => undef,
    srcmd5          => $sum,
  );
  my $dir = path($self->app->config->{checkout_dir}, $name, $sum)->make_path;
  $dir->child('.cavil.json')->spew(encode_json({licenses => $licenses, version => $version}));
  my $filename = path($upload->filename)->basename;
  $file->move_to($dir->child($filename));
  my $obj = $pkgs->find($id);
  $obj->{external_link} = 'upload';
  $pkgs->update($obj);
  $pkgs->imported($id);

  $pkgs->unpack($id);
  $self->flash(message => "Package $name has been uploaded and is now being processed");
  $self->redirect_to('dashboard');
}

1;
