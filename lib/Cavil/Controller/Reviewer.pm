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

use Mojo::File      qw(path);
use Cavil::Licenses qw(lic);
use List::Util      qw(first uniq);

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

sub details ($self) {
  my $id   = $self->stash('id');
  my $pkgs = $self->packages;
  return $self->render(text => 'Package not found', status => 404) unless my $pkg = $pkgs->find($id);
  my $report = $self->reports->specfile_report($id);

  my $should_reindex = $self->patterns->has_new_patterns($pkg->{name}, $pkg->{indexed});

  $self->render(spec => $report, package => $pkg, should_reindex => $should_reindex);
}

sub meta ($self) {
  my $id   = $self->stash('id');
  my $pkgs = $self->packages;
  return $self->render(json => {error => 'Package not found'}, status => 404) unless my $pkg = $pkgs->find($id);

  my $spec = $self->reports->specfile_report($id);
  my $type = first { length $_ } map { $_->{type} } @{$spec->{sub} // []};

  my $main               = $spec->{main};
  my $main_license       = $main->{license};
  my $normalized_license = lic($main_license)->to_string;
  my $package_license    = $normalized_license || $main_license;

  my $version = $main->{version};
  my $summary = $main->{summary};
  my $group   = $main->{group};
  my $url     = $main->{url};

  my $has_spdx_report = $pkgs->has_spdx_report($id);
  my $report          = $pkg->{checksum} // '';
  my ($shortname)     = $report =~ /:(\w+)$/;

  my $requests = $pkgs->requests_for($id);
  my $products = $self->products->for_package($id);

  my $history = [];
  for my $prev (@{$pkgs->history($pkg->{name}, $pkg->{checksum}, $id)}) {
    my $entry = {
      created        => $prev->{created_epoch},
      external_link  => $prev->{external_link},
      id             => $prev->{id},
      result         => $prev->{result} // '',
      reviewing_user => $prev->{login}  // '',
      state          => $prev->{state}
    };
    push @$history, $entry;
  }

  my $actions = [];
  for my $action (@{$pkgs->actions($pkg->{external_link}, $id)}) {
    my $entry = {
      created => $action->{created_epoch},
      id      => $action->{id},
      name    => $action->{name},
      result  => $action->{result} // '',
      state   => $action->{state}
    };
    push @$actions, $entry;
  }

  my (%docs, %lics, @package_files);
  for my $sub (@{$spec->{sub} // []}) {
    my $entry = {
      file     => $sub->{file},
      group    => $sub->{group},
      licenses => [uniq @{$sub->{licenses} // []}],
      sources  => [uniq @{$sub->{sources}  // []}],
      summary  => $sub->{summary},
      url      => $sub->{url},
      version  => $sub->{version}
    };
    push @package_files, $entry;
    for my $line (@{$sub->{'%doc'}}) {
      $docs{$_} = 1 for split(/ /, $line);
    }
    for my $line (@{$sub->{'%license'}}) {
      $lics{$_} = 1 for split(/ /, $line);
    }
  }

  $self->render(
    json => {
      actions           => $actions,
      copied_files      => {'%doc' => [sort keys %docs], '%license' => [sort keys %lics]},
      created           => $pkg->{created_epoch},
      errors            => $spec->{errors} // [],
      external_link     => $pkg->{external_link},
      has_spdx_report   => \!!$has_spdx_report,
      history           => $history,
      package_checksum  => $pkg->{checkout_dir},
      package_files     => \@package_files,
      package_group     => $group,
      package_license   => {name => $package_license, spdx => \!!$normalized_license},
      package_name      => $pkg->{name},
      package_priority  => $pkg->{priority},
      package_shortname => $shortname,
      package_summary   => $summary,
      package_type      => $type,
      package_url       => $url,
      package_version   => $version,
      products          => $products,
      requests          => $requests,
      result            => $pkg->{result},
      reviewed          => $pkg->{reviewed_epoch},
      reviewing_user    => $pkg->{login},
      state             => $pkg->{state},
      warnings          => $spec->{warnings} // []
    }
  );
}

sub fasttrack_package ($self) {
  my $validation = $self->validation;
  $validation->optional('comment');
  return $self->reply->json_validation_error if $validation->has_error;

  my $user = $self->session('user');

  my $pkg = $self->packages->find($self->stash('id'));
  return $self->reply->not_found unless $pkg;

  $pkg->{reviewing_user}   = $self->users->find(login => $user)->{id};
  $pkg->{result}           = $validation->param('comment');
  $pkg->{state}            = 'acceptable';
  $pkg->{review_timestamp} = 1;
  $self->packages->update($pkg);

  return $self->render(text => "Reviewed $pkg->{name} as acceptable");
}

sub file_view ($self) {
  my $filename = $self->stash('file');

  # There are unfortunately few limits on what file can be - but it
  # can't be a backward compat
  # technically Foo..bar is allowed as file name, but we forbid this
  # here for simplicity
  return $self->render(error => 400) if $filename =~ qr/\.\./;
  $filename =~ s,/$,,;
  $self->stash('filename', $filename);

  my $pkgs    = $self->packages;
  my $package = $pkgs->find($self->stash('id'));
  return $self->reply->not_found unless $package;
  $self->stash('package', $package);

  my $report = $self->reports->specfile_report($package->{id});
  my $lic    = $report->{main}{license};
  $self->stash('license', lic($lic)->to_string);

  my $file
    = path($self->app->config->{checkout_dir}, $package->{name}, $package->{checkout_dir}, '.unpacked', $filename);
  return $self->reply->not_found unless -e $file;

  if (-d $file) {
    my %matched_files = map { $_ => 1 } @{$pkgs->matched_files($package->{id})};
    my (@files, @dirs, @processed);
    for my $entry (path($file)->list({dir => 1})->each) {
      if    (-d $entry)                          { push @dirs,      $entry }
      elsif ($entry =~ /\.processed(?:\.\w+|$)/) { push @processed, $entry }
      else                                       { push @files,     $entry }
    }
    return $self->render(
      'reviewer/directory_view',
      dirs          => \@dirs,
      files         => \@files,
      processed     => \@processed,
      matched_files => \%matched_files
    );
  }

  $self->stash('file', $file);
}

sub list_recent ($self) {
  $self->render;
}

# Just hooking ajax
sub list_reviews { }

sub reindex_package ($self) {
  return $self->reply->not_found unless $self->packages->reindex($self->stash('id'));

  return $self->render(json => {ok => 1});
}

sub review_package ($self) {
  my $validation = $self->validation;
  $validation->optional('comment');
  $validation->optional('unacceptable');
  $validation->optional('acceptable');
  $validation->optional('correct');
  return $self->reply->json_validation_error if $validation->has_error;

  my $user = $self->session('user');

  my $id  = $self->stash('id');
  my $pkg = $self->packages->find($id);
  return $self->reply->not_found unless $pkg;

  $pkg->{reviewing_user} = $self->users->find(login => $user)->{id};
  my $result = $pkg->{result} = $validation->param('comment');

  if ($validation->param('unacceptable')) {
    $pkg->{state} = 'unacceptable';
  }
  elsif ($validation->param('acceptable')) {
    $pkg->{state} = 'acceptable';
  }
  elsif ($validation->param('correct')) {
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

1;
