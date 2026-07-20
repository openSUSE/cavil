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

use Mojo::File  qw(path);
use Mojo::Util  qw(humanize_bytes);
use Cavil::Util qw(lines_context);

my $SMALL_REPORT_RE = qr/
  (?:
    \.spec
  |
    \/(?:copying|copyright|legal|license|readme)(?:\.\w+)?
  )$
/xi;

sub details ($self) {
  my $id   = $self->stash('id');
  my $pkgs = $self->packages;
  return $self->render(text => 'Package not found', status => 404) unless my $pkg = $pkgs->find($id);
  my $report = $self->reports->specfile_report($id);

  my $should_reindex = $self->patterns->has_new_patterns($pkg->{name}, $pkg->{indexed});

  $self->render(spec => $report, package => $pkg, should_reindex => $should_reindex);
}

sub meta ($self) {
  my $id = $self->stash('id');
  return $self->render(json => {error => 'Package not found'}, status => 404)
    unless my $summary = $self->helpers->package_summary($id);
  $self->render(json => $summary);
}

sub fasttrack_package ($self) {
  my $validation = $self->validation;
  $validation->optional('comment');
  return $self->reply->json_validation_error if $validation->has_error;

  my $user = $self->session('user');

  my $pkg = $self->packages->find($self->stash('id'));
  return $self->reply->not_found unless $pkg;

  $pkg->{reviewing_user}   = $self->users->find(login => $user)->{id};
  $pkg->{result}           = $validation->param('comment') || 'Reviewed ok';
  $pkg->{state}            = 'acceptable';
  $pkg->{review_timestamp} = 1;
  $self->packages->update($pkg);

  return $self->render(text => "Reviewed $pkg->{name} as acceptable");
}

sub file_view ($self) {
  my $ctx = $self->_file_browser_context;
  return unless $ctx;

  $self->stash(filename => $ctx->{filename}, package => $ctx->{package});
}

sub file_view_meta ($self) {
  my $ctx = $self->_file_browser_context;
  return unless $ctx;

  my $file     = $ctx->{file};
  my $filename = $ctx->{filename};
  my $package  = $ctx->{package};
  my $payload  = {
    package => {
      id         => $package->{id},
      name       => $package->{name},
      detailsUrl => $self->url_for('package_details', id => $package->{id})->to_string
    },
    checkoutDir => $package->{checkout_dir},
    currentPath => $filename,
    breadcrumbs => $self->_file_browser_breadcrumbs($package, $filename)
  };

  if (-d $file) {
    $payload->{kind}    = 'directory';
    $payload->{entries} = $self->_file_browser_entries($package, $file, $filename);
  }
  else {
    $payload->{kind}   = 'file';
    $payload->{source} = $self->_file_browser_source($package, $file, $filename);
  }

  return $self->render(json => $payload);
}

sub _file_browser_context ($self) {
  my $filename = $self->stash('file');

  # There are unfortunately few limits on what file can be - but it
  # can't be a backward compat
  # technically Foo..bar is allowed as file name, but we forbid this
  # here for simplicity
  if ($filename =~ qr/\.\./) {
    $self->render(text => 'Bad Request', status => 400);
    return undef;
  }
  $filename =~ s,/$,,;

  my $pkgs    = $self->packages;
  my $package = $pkgs->find($self->stash('id'));
  unless ($package) {
    $self->reply->not_found;
    return undef;
  }

  my $file
    = path($self->app->config->{checkout_dir}, $package->{name}, $package->{checkout_dir}, '.unpacked', $filename);
  unless (-e $file) {
    $self->reply->not_found;
    return undef;
  }

  return {filename => $filename, package => $package, file => $file};
}

sub _file_browser_breadcrumbs ($self, $package, $filename) {
  my @breadcrumbs = (
    {
      name => $package->{name},
      path => '',
      url  => $self->url_for('file_view', id => $package->{id}, file => '')->to_string
    }
  );
  my @path;
  for my $part (grep { length $_ } split '/', $filename) {
    push @path, $part;
    push @breadcrumbs,
      {
      name => $part,
      path => join('/', @path),
      url  => $self->url_for('file_view', id => $package->{id}, file => join('/', @path))->to_string
      };
  }
  return \@breadcrumbs;
}

sub _file_browser_entries ($self, $package, $file, $filename) {
  my %matched_files = map { $_ => 1 } @{$self->packages->matched_files($package->{id})};
  my (@files, @dirs, @processed);
  for my $entry (sort { lc($a->basename) cmp lc($b->basename) } $file->list({dir => 1})->each) {
    if    (-d $entry)                          { push @dirs,      $entry }
    elsif ($entry =~ /\.processed(?:\.\w+|$)/) { push @processed, $entry }
    else                                       { push @files,     $entry }
  }

  my @entries;
  for my $entry (@dirs, @files, @processed) {
    my $name      = $entry->basename;
    my $path      = length($filename)                 ? "$filename/$name" : $name;
    my $processed = $name =~ /\.processed(?:\.\w+|$)/ ? 1                 : 0;
    my $has_match = $matched_files{$path}             ? 1                 : 0;
    if (-d $entry && !$has_match) {
      my $prefix = "$path/";
      $has_match = grep { index($_, $prefix) == 0 } keys %matched_files ? 1 : 0;
    }
    push @entries,
      {
      name      => $name,
      path      => $path,
      kind      => -d $entry ? 'directory' : 'file',
      processed => $processed,
      hasMatch  => $has_match,
      url       => $self->url_for('file_view', id => $package->{id}, file => $path)->to_string
      };
  }
  return \@entries;
}

sub _file_browser_source ($self, $package, $file, $filename) {
  my $file_id = 0;
  my %info_by_line;
  if (my $matched
    = $self->app->pg->db->select('matched_files', ['id'], {package => $package->{id}, filename => $filename})->hash)
  {
    $file_id      = $matched->{id};
    %info_by_line = %{$self->snippets->file_line_info($package->{id}, $file_id)};
  }

  my $size = -s $file;
  my $max  = $self->app->config->{max_file_browser_size} // 1_000_000;
  if ($max && $size > $max) {
    return {
      id           => $file_id,
      name         => $package->{name},
      filename     => $filename,
      oversized    => 1,
      size         => $size,
      maxSize      => $max,
      sizeLabel    => humanize_bytes($size),
      maxSizeLabel => humanize_bytes($max)
    };
  }

  my @lines;
  my $number = 1;
  my @text   = split /\n/, $self->maybe_utf8($file->slurp), -1;
  pop @text if @text && $text[-1] eq '';
  for my $line (@text) {
    push @lines, [$number, {%{$info_by_line{$number} // {risk => 0}}}, $line];
    $number++;
  }

  return {id => $file_id, lines => lines_context(\@lines), name => $package->{name}, filename => $filename};
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
  return $self->reply->json_validation_error if $validation->has_error;

  my $user = $self->session('user');

  my $id  = $self->stash('id');
  my $pkg = $self->packages->find($id);
  return $self->reply->not_found unless $pkg;

  $pkg->{reviewing_user} = $self->users->find(login => $user)->{id};
  my $result = $pkg->{result} = $validation->param('comment') || 'Reviewed ok';

  # The acceptance state is derived from the reviewer's capability, never taken from the request: only a
  # holder of "review_lawyer" (the lawyer role) can produce acceptable_by_lawyer, so a non-lawyer curator
  # (e.g. a plain admin) can accept a package but can never mint a lawyer sign-off. Mirrors the MCP path.
  if ($validation->param('unacceptable')) {
    $pkg->{state} = 'unacceptable';
  }
  elsif ($validation->param('acceptable')) {
    $pkg->{state} = $self->current_user_can('review_lawyer') ? 'acceptable_by_lawyer' : 'acceptable';
  }
  else {
    die "Unknown state";
  }
  $pkg->{review_timestamp} = 1;
  $pkg->{ai_assisted}      = 0;

  $self->packages->update($pkg);

  $self->app->log->info(qq{Review by $user: $pkg->{name} ($id) is $pkg->{state}:}, $result);

  $self->render('reviewer/reviewed', package => $pkg);
}

1;
