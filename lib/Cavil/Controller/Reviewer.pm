# Copyright (C) 2018 SUSE Linux GmbH
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

package Cavil::Controller::Reviewer;
use Mojo::Base 'Mojolicious::Controller', -signatures;

use Mojo::File 'path';
use Mojo::JSON 'from_json';
use Cavil::Licenses 'lic';
use Cavil::Util 'lines_context';

my $SMALL_REPORT_RE = qr/
  (?:
    \.spec
  |
    \/(?:copying|copyright|legal|license|readme)(?:\.\w+)?
  )$
/xi;

sub add_ignore ($self) {
  my $validation = $self->validation;
  $validation->required('hash')->like(qr/^[a-f0-9]{32}$/i);
  $validation->required('package');
  return $self->reply->json_validation_error if $validation->has_error;

  my $hash    = lc $validation->param('hash');
  my $package = $validation->param('package');
  $self->packages->ignore_line($package, $hash);

  return $self->render(json => 'ok');
}

sub add_glob ($self) {
  my $validation = $self->validation;
  $validation->required('glob');
  $validation->required('package');
  return $self->reply->json_validation_error if $validation->has_error;

  $self->pg->db->insert('ignored_files',
    {glob => $validation->param('glob'), owner => $self->users->find(login => $self->current_user)->{id}});
  $self->packages->analyze($validation->param('package'));
  return $self->render(json => 'ok');
}

sub calc_report ($self) {
  my $id  = $self->param('id');
  my $pkg = $self->packages->find($id);

  # Covers various jobs that will modify the report
  return $self->render(text => 'package being processed', status => 408)
    if $self->minion->jobs({states => ['inactive', 'active'], notes => ["pkg_$id"]})->total;

  return $self->render(text => 'not indexed', status => 408) unless $pkg->{indexed};

  return $self->render(text => 'no report', status => 408) unless my $report = $self->reports->cached_dig_report($id);

  $report = from_json($report);
  $self->_sanitize_report($report);

  $self->respond_to(
    json => sub { $self->render(json => {report => $report, package => $pkg}) },
    html => sub {
      my $min = $self->app->config('min_files_short_report');
      $self->render('reviewer/report', report => $report, package => $pkg, max_number_of_files => $min);
    }
  );
}

sub details ($self) {
  my $id   = $self->param('id');
  my $pkgs = $self->packages;
  return $self->render(text => 'Package not found', status => 404) unless my $pkg = $pkgs->find($id);
  my $report = $self->reports->specfile_report($id);

  my $should_reindex = $self->patterns->has_new_patterns($pkg->{name}, $pkg->{indexed});

  my $products = $self->products->for_package($id);
  my $history  = $pkgs->history($pkg->{name}, $pkg->{checksum}, $id);
  my $actions  = $pkgs->actions($pkg->{external_link}, $id);

  $self->render(
    spec           => $report,
    package        => $pkg,
    products       => $products,
    history        => $history,
    actions        => $actions,
    should_reindex => $should_reindex
  );
}

sub fasttrack_package ($self) {
  my $user = $self->session('user');

  my $pkg = $self->packages->find($self->param('id'));
  return $self->reply->not_found unless $pkg;

  $pkg->{reviewing_user}   = $self->users->find(login => $user)->{id};
  $pkg->{result}           = $self->param('comment');
  $pkg->{state}            = 'acceptable';
  $pkg->{review_timestamp} = 1;
  $self->packages->update($pkg);

  return $self->render(text => "Reviewed $pkg->{name} as acceptable");
}

sub fetch_source ($self) {
  my $id = $self->param('id');
  return $self->reply->not_found
    unless my $source = $self->reports->source_for($id, $self->param('start') || 0, $self->param('end') || 0);

  $self->respond_to(
    json => sub { $self->render(json => {source => $source}) },
    html => sub {

      return $self->render(
        'reviewer/file_source',
        file     => $id,
        filename => $source->{filename},
        lines    => lines_context($source->{lines}),
        hidden   => 0,
        packname => $source->{name}
      );
    }
  );
}

sub file_view ($self) {
  my $filename = $self->param('file');

  # There are unfortunately few limits on what file can be - but it
  # can't be a backward compat
  # technically Foo..bar is allowed as file name, but we forbid this
  # here for simplicity
  return $self->render(error => 400) if $filename =~ qr/\.\./;
  $filename =~ s,/$,,;
  $self->stash('filename', $filename);

  my $package = $self->packages->find($self->param('id'));
  return $self->reply->not_found unless $package;
  $self->stash('package', $package);

  my $report = $self->reports->specfile_report($package->{id});
  my $lic    = $report->{main}{license};
  $self->stash('license', lic($lic)->to_string);

  my $file
    = path($self->app->config->{checkout_dir}, $package->{name}, $package->{checkout_dir}, '.unpacked', $filename);
  return $self->reply->not_found unless -e $file;

  if (-d $file) {
    opendir(my $dh, $file) || die "Can't opendir $file: $!";
    my @entries = grep {/^[^.]/} readdir($dh);
    closedir $dh;
    return $self->render('reviewer/directory_view', entries => \@entries);
  }

  else { $self->stash('file', $file) }
}

sub list_new_ajax ($self) {
  my $packages = $self->packages->list($self->param('state'), $self->param('package'));
  my $products = $self->products;
  $_->{products} = scalar @{$products->for_package($_->{id})} for @$packages;

  $self->render(
    json => {data => $packages, recordsTotal => scalar(@$packages), recordsFiltered => scalar(@$packages), draw => 1});
}

sub list_recent ($self) {
  $self->render;
}

sub list_recent_ajax ($self) {
  $self->render(json => {data => $self->packages->recent});
}

# Just hooking ajax
sub list_reviews { }

sub reindex_package ($self) {
  return $self->reply->not_found unless $self->packages->reindex($self->param('id'));

  return $self->render(json => {ok => 1});
}

sub review_package ($self) {
  my $user = $self->session('user');

  my $id  = $self->param('id');
  my $pkg = $self->packages->find($id);
  return $self->reply->not_found unless $pkg;

  $pkg->{reviewing_user} = $self->users->find(login => $user)->{id};
  my $result = $pkg->{result} = $self->param('comment');

  if ($self->param('unacceptable')) {
    $pkg->{state} = 'unacceptable';
  }
  elsif ($self->param('acceptable')) {
    $pkg->{state} = 'acceptable';
  }
  elsif ($self->param('correct')) {
    $pkg->{state} = 'correct';
  }
  else {
    die "Unknown state";
  }
  $pkg->{review_timestamp} = 1;

  $self->packages->update($pkg);

  $self->app->log->info(qq{Review by $user: $pkg->{name} ($id) is $pkg->{state}:}, $result);

  $self->render('reviewer/reviewed', package => $pkg);
}

sub _sanitize_report ($self, $report) {

  # Flags
  $report->{flags} = $report->{flags} || [];

  # Files
  my $files    = $report->{files};
  my $expanded = $report->{expanded};
  my $lines    = $report->{lines};
  my $snippets = $report->{missed_snippets};

  # old report
  if (!defined $report->{missed_files}) {
    $report->{missed_files} = [{id => 0, name => "PLEASE REINDEX!", max_risk => 9, license => '', match => 0}];
  }
  else {
    my @missed;
    for my $file (keys %$snippets) {
      $expanded->{$file} = 1;
      my ($max_risk, $match, $license) = @{$report->{missed_files}{$file}};
      $license = 'Snippet' unless $license;
      push(
        @missed,
        {
          id       => $file,
          name     => $files->{$file},
          max_risk => $max_risk,
          license  => $license,
          match    => int($match * 1000 + 0.5) / 10.
        }
      );
    }
    delete $report->{missed_files};
    delete $report->{missed_snippets};
    $report->{missed_files} = [sort { $b->{max_risk} cmp $a->{max_risk} || $a->{name} cmp $b->{name} } @missed];
  }

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
