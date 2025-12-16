# Copyright (C) 2021 SUSE Linux GmbH
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

package Cavil::Controller::Report;
use Mojo::Base 'Mojolicious::Controller', -signatures;

use Mojo::Asset::File;
use Mojo::JSON 'from_json';
use Cavil::Util 'lines_context';

sub report ($self) {
  my $id = $self->stash('id');
  return $self->render(text => 'unknown package', status => 408) unless my $pkg = $self->packages->find($id);

  # Covers various jobs that will modify the report
  return $self->render(text => 'package being processed', status => 408)
    if $self->minion->jobs({states => ['inactive', 'active'], notes => ["pkg_$id"]})->total;

  return $self->render(text => 'not indexed', status => 408) unless $pkg->{indexed};

  return $self->render(text => 'no report', status => 408) unless my $report = $self->reports->cached_dig_report($id);

  $report = from_json($report);
  $self->_sanitize_report($report);

  $self->respond_to(
    json => sub { $self->render(json                      => {report => $report, package => $pkg}) },
    txt  => sub { $self->render('reviewer/report', report => $report, package => $pkg) },
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

sub _sanitize_report ($self, $report) {

  # Flags
  $report->{flags} = $report->{flags} || [];

  # Files
  my $files    = $report->{files};
  my $expanded = $report->{expanded};
  my $lines    = $report->{lines};
  my $snippets = $report->{missed_snippets};

  my @missed;
  for my $file (keys %$snippets) {
    $expanded->{$file} = 1;
    my ($max_risk, $match, $license, $spdx) = @{$report->{missed_files}{$file}};
    $license = 'Keyword' unless $license;
    push(
      @missed,
      {
        id       => $file,
        name     => $files->{$file},
        max_risk => $max_risk,
        license  => $license,
        spdx     => $spdx,
        match    => int($match * 1000 + 0.5) / 10.
      }
    );
  }
  delete $report->{missed_files};
  delete $report->{missed_snippets};
  $report->{missed_files} = [sort { $b->{max_risk} cmp $a->{max_risk} || $a->{name} cmp $b->{name} } @missed];

  $report->{files} = [];
  for my $file (sort { $files->{$a} cmp $files->{$b} } keys %$files) {
    my $path = $files->{$file};
    push @{$report->{files}}, my $current = {id => $file, path => $path, expand => $expanded->{$file}};

    if ($lines->{$file}) {
      $current->{lines} = lines_context($lines->{$file});
    }
  }

  # Risks
  my $chart = $report->{chart} = {};
  my $risks = $report->{risks};
  $report->{risks} = {};
  my $licenses = $report->{licenses};
  for my $risk (reverse sort keys %$risks) {
    my $current = $report->{risks}{$risk} = {};
    $risk = $risks->{$risk};

    for my $lic (sort keys %$risk) {
      my $current = $current->{$lic} = {};
      my $license = $licenses->{$lic};
      my $name    = $current->{name} = $license->{name};

      my $matches = $risk->{$lic};
      my %files   = map { $_ => 1 } map {@$_} values %$matches;
      $chart->{$name} = keys %files;

      $current->{flags} = $license->{flags};

      my $list = $current->{files} = [];
      for my $file (sort keys %files) {
        push @$list, [$file, $files->{$file}];
      }
    }
  }

  # Emails and URLs
  my $emails = $report->{emails};
  $report->{emails} = [map { [$_, $emails->{$_}] } sort { $emails->{$b} <=> $emails->{$a} } keys %$emails];
  my $urls = $report->{urls};
  $report->{urls} = [map { [$_, $urls->{$_}] } sort { $urls->{$b} <=> $urls->{$a} } keys %$urls];
}

1;
