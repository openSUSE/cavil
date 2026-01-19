# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later
package Cavil::Controller::Report;
use Mojo::Base 'Mojolicious::Controller', -signatures;

use Mojo::Asset::File;
use Cavil::Util 'lines_context';

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
    mcp  => sub { $self->render(text                      => $self->helpers->mcp_report($id)) },
    html => sub {
      my $min = $self->app->config('min_files_short_report');
      $self->render('reviewer/report', report => $report, package => $pkg, max_number_of_files => $min);
    }
  );
}

sub source ($self) {
  my $validation = $self->validation;
  $validation->optional('start')->num;
  $validation->optional('end')->num;
  return $self->reply->json_validation_error if $validation->has_error;

  my $id    = $self->stash('id');
  my $start = $validation->param('start') || 0;
  my $end   = $validation->param('end')   || 0;
  return $self->render(text => 'unknown file', status => 404)
    unless my $source = $self->reports->source_for($id, $start, $end);

  $self->respond_to(
    json => sub { $self->render(json => {source => $source}) },
    html => sub {

      return $self->render(
        'reviewer/file_source',
        file                    => $id,
        filename                => $source->{filename},
        lines                   => lines_context($source->{lines}),
        hidden                  => 0,
        packname                => $source->{name},
        is_admin_or_contributor => $self->current_user_has_role('admin', 'contributor')
      );
    }
  );
}

sub spdx ($self) {
  my $id     = $self->stash('id');
  my $app    = $self->app;
  my $minion = $app->minion;
  my $pkgs   = $app->packages;

  return $self->render(text     => 'package is obsolete', status => 410) if $pkgs->is_obsolete($id);
  return $self->render(template => 'report/waiting',      status => 408) unless $pkgs->is_indexed($id);

  if ($pkgs->has_spdx_report($id)) {
    $self->res->headers->content_type('text/plain');
    return $self->reply->asset(Mojo::Asset::File->new(path => $pkgs->spdx_report_path($id)));
  }

  $pkgs->generate_spdx_report($id);
  $self->render(template => 'report/waiting', status => 408);
}

1;
