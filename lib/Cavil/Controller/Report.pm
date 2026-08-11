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

  # Jobs working on the package are deliberately not a reason to refuse it one. A rebuild is assembled
  # beside the live report and swapped in with a single commit, so there is always a whole report to hand
  # out - and refusing while anything is queued would refuse after every single build, because the
  # spdx_report job that ends one holds the package for its duration while leaving the report alone.
  return $self->render(text => 'not indexed', status => 408) unless $pkg->{indexed};

  return $self->render(text => 'no report', status => 408)
    unless my $report = $self->reports->sanitized_dig_report($id);

  $self->respond_to(
    json => sub { $self->render(json => {report => $report, package => $pkg}) },
    txt  => sub {

      # Only notes relevant to this review (native or an identical license report) go into the plain
      # text report. Lawyer-only notes are deliberately excluded: these reports are shared publicly.
      my $notes = $self->notes->list(
        $pkg->{name},
        relevant_only => 1,
        package_id    => $id,
        checksum      => $pkg->{checksum},
        limit         => 100
      )->{notes};
      $self->render(
        'reviewer/report',
        report          => $report,
        package         => $pkg,
        notes           => $notes,
        legal_documents => $self->helpers->legal_documents($id)
      );
    },
    mcp => sub { $self->render(text => $self->helpers->mcp_report($id)) }
  );
}

sub details ($self) {
  my $id = $self->stash('id');
  return $self->render(json => {error => 'unknown package', stage => 1}, status => 408)
    unless my $pkg = $self->packages->find($id);

  # A reindex (or any other report-modifying job) is queued or running. The rebuild happens beside the live
  # report and only replaces it at the very end, so the reviewer keeps the report they were reading for the
  # whole ride; the state below tells the UI how far along the rebuild is and that the report is read-only
  # until it lands.
  my $state = $self->helpers->reindex_state($pkg);

  my $report = $self->reports->sanitized_dig_report($id);
  return $self->render(json => {error => 'no report', obsolete => \1, report_unavailable => \1})
    if !$report && $pkg->{obsolete};

  if ($report && $pkg->{indexed}) {
    my $details = $self->helpers->report_details($pkg, $report);
    return $self->render(json => {%$details, %$state});
  }

  return $self->render(json => {error => 'not indexed', %{_stage_payload($pkg)}}, status => 408) unless $pkg->{indexed};
  return $self->render(json => {error => 'no report',   %{_stage_payload($pkg)}}, status => 408);
}

# Cheap poll for a report page that is already on screen: just the rebuild state, with none of the work
# that assembling a dig report costs. A page left open while its package is reindexed asks for this every
# few seconds and only refetches the full report once the state says a new one has been promoted.
sub report_state ($self) {
  my $id = $self->stash('id');
  return $self->render(json => {error => 'unknown package'}, status => 404) unless my $pkg = $self->packages->find($id);
  $self->render(json => $self->helpers->reindex_state($pkg));
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

# Ask for a report to be built. The report page polls report_state afterwards, so the answer is the same
# state payload that poll returns and the button can go straight into its "generating" animation.
sub generate_spdx ($self) {
  my $id = $self->stash('id');
  return $self->render(json => {error => 'unknown package'}, status => 404) unless my $pkg = $self->packages->find($id);

  my $state = $self->helpers->spdx_state($pkg);
  return $self->render(json => $state, status => 410) if $state->{state} eq 'unavailable';

  # Idempotent: does nothing if the report is already there or already queued, so a double click (or two
  # reviewers on the same report) costs one job between them
  $self->packages->generate_spdx_report($id);
  $self->render(json => $self->helpers->spdx_state($pkg));
}

sub spdx ($self) {
  my $id   = $self->stash('id');
  my $pkgs = $self->app->packages;

  return $self->render(text     => 'package is obsolete', status => 410) if $pkgs->is_obsolete($id);
  return $self->render(template => 'report/waiting',      status => 408) unless $pkgs->is_indexed($id);

  if ($pkgs->has_spdx_report($id)) {
    my $path    = $pkgs->spdx_report_path($id);
    my $headers = $self->res->headers;
    $headers->content_type('application/json');
    $headers->vary('Accept-Encoding');

    # Nobody reads one of these in a browser tab, so hand it over as a file. The name is the one the
    # report page's download link advertises. Gzip below is a transfer encoding, which the browser undoes
    # before saving, so what lands on disk is the JSON this names.
    $headers->content_disposition(qq{attachment; filename="$id.spdx.json"});

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
