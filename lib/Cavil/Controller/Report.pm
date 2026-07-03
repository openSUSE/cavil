# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package Cavil::Controller::Report;
use Mojo::Base 'Mojolicious::Controller', -signatures;

use Mojo::Asset::File;
use Cavil::Util 'lines_context';
use IO::Uncompress::Gunzip ();

sub report ($self) {
  my $id = $self->stash('id');
  return $self->render(text => 'unknown package', status => 408) unless my $pkg = $self->packages->find($id);

  # Covers various jobs that will modify the report
  return $self->render(text => 'package being processed', status => 408)
    if $self->minion->jobs({states => ['inactive', 'active'], notes => ["pkg_$id"]})->total;

  return $self->render(text => 'not indexed', status => 408) unless $pkg->{indexed};

  return $self->render(text => 'no report', status => 408)
    unless my $report = $self->reports->sanitized_dig_report($id);

  $self->respond_to(
    json => sub { $self->render(json                      => {report => $report, package => $pkg}) },
    txt  => sub { $self->render('reviewer/report', report => $report, package => $pkg) },
    mcp  => sub { $self->render(text                      => $self->helpers->mcp_report($id)) }
  );
}

sub details ($self) {
  my $id = $self->stash('id');
  return $self->render(json => {error => 'unknown package', stage => 1}, status => 408)
    unless my $pkg = $self->packages->find($id);

  return $self->render(json => {error => 'package being processed', %{_stage_payload($pkg)}}, status => 408)
    if $self->minion->jobs({states => ['inactive', 'active'], notes => ["pkg_$id"]})->total;

  my $report = $self->reports->sanitized_dig_report($id);
  return $self->render(json => {error => 'no report', obsolete => \1, report_unavailable => \1})
    if !$report && $pkg->{obsolete};

  return $self->render(json => {error => 'not indexed', %{_stage_payload($pkg)}}, status => 408) unless $pkg->{indexed};

  unless ($report) {
    return $self->render(json => {error => 'no report', %{_stage_payload($pkg)}}, status => 408);
  }

  $self->render(json => $self->helpers->report_details($pkg, $report));
}

sub _stage_payload ($pkg) {
  my $stage = !$pkg->{imported} ? 1 : !$pkg->{unpacked} ? 2 : !$pkg->{indexed} ? 3 : 4;
  return {
    stage          => $stage,
    imported_epoch => $pkg->{imported_epoch},
    unpacked_epoch => $pkg->{unpacked_epoch},
    indexed_epoch  => $pkg->{indexed_epoch}
  };
}

sub source ($self) {
  my $validation = $self->validation;
  $validation->optional('start')->num;
  $validation->optional('end')->num;
  return $self->reply->json_validation_error if $validation->has_error;

  my $id    = $self->stash('id');
  my $start = $validation->param('start') || 0;
  my $end   = $validation->param('end')   || 0;
  return $self->render(json => {error => 'unknown file'}, status => 404)
    unless my $source = $self->reports->source_for($id, $start, $end);

  $source->{lines} = lines_context($source->{lines});
  $self->render(json => {source => $source});
}

sub spdx ($self) {
  my $id     = $self->stash('id');
  my $app    = $self->app;
  my $minion = $app->minion;
  my $pkgs   = $app->packages;

  return $self->render(text     => 'package is obsolete', status => 410) if $pkgs->is_obsolete($id);
  return $self->render(template => 'report/waiting',      status => 408) unless $pkgs->is_indexed($id);

  if ($pkgs->has_spdx_report($id)) {
    my $path    = $pkgs->spdx_report_path($id);
    my $headers = $self->res->headers;
    $headers->content_type('application/json');
    $headers->vary('Accept-Encoding');

    # The report is stored gzip-compressed. Hand it over untouched to clients that accept gzip (the
    # common case, no extra work), and decompress on the fly for those that do not.
    if (($self->req->headers->accept_encoding // '') =~ /gzip/i) {
      $headers->content_encoding('gzip');
      return $self->reply->asset(Mojo::Asset::File->new(path => $path));
    }

    # Rare client without gzip support: stream-decompress to a temporary file so we never hold the
    # whole (potentially large) report in memory
    return $self->render(text => 'Could not read SPDX report', status => 500)
      unless my $gz = IO::Uncompress::Gunzip->new("$path");
    my $asset = Mojo::Asset::File->new;
    my $buffer;
    $asset->add_chunk($buffer) while $gz->read($buffer, 131072) > 0;
    return $self->reply->asset($asset);
  }

  $pkgs->generate_spdx_report($id);
  $self->render(template => 'report/waiting', status => 408);
}

1;
