# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package Cavil::Controller::Reviewer;
use Mojo::Base 'Mojolicious::Controller', -signatures;

use Mojo::Asset::File;
use Mojo::File  qw(path);
use Mojo::Util  qw(encode url_escape);
use Cavil::Util qw(checkout_path lines_context tags_from_request PRIORITY_WAITING);

use constant WINDOW_LINES => 2000;

sub details ($self) {
  my $id   = $self->stash('id');
  my $pkgs = $self->packages;
  return $self->render(text => 'Package not found', status => 404) unless my $pkg = $pkgs->find($id);

  my $should_reindex = $self->patterns->has_new_patterns($pkg->{name}, $pkg->{indexed});

  $self->render(package => $pkg, should_reindex => $should_reindex);
}

sub meta ($self) {
  my $id = $self->stash('id');
  return $self->render(json => {error => 'Package not found'}, status => 404)
    unless my $summary = $self->helpers->package_summary($id);
  $self->render(json => $summary);
}

sub tags ($self) {
  $self->render(json => {tags => $self->packages->all_tags});
}

# Curators replace the whole tag set; CVE tags removed here return on the next reindex (derived facts).
sub set_tags ($self) {
  my $id = $self->stash('id');
  return $self->render(json => {error => 'Package not found'}, status => 404) unless $self->packages->find($id);

  my ($tags, $error) = tags_from_request($self->req, qr/^CVE(-|$)/i);
  return $self->render(json => {error => $error}, status => 400) if $error;

  $self->packages->set_tags($id, $tags);
  $self->render(json => {tags => $tags});
}

sub fasttrack_package ($self) {
  my $validation = $self->validation;
  $validation->optional('comment');
  return $self->reply->json_validation_error if $validation->has_error;

  my $user = $self->session('user');

  my $id  = $self->stash('id');
  my $pkg = $self->packages->find($id);
  return $self->render(json => {error => 'Package not found'}, status => 404) unless $pkg;

  $pkg->{reviewing_user} = $self->users->find(login => $user)->{id};
  my $result = $pkg->{result} = $validation->param('comment') || 'Reviewed ok';
  $pkg->{state}            = 'acceptable';
  $pkg->{review_timestamp} = 1;
  $self->packages->update($pkg);

  $self->app->log->info(qq{Fasttrack review by $user: $pkg->{name} ($id) is $pkg->{state}:}, $result);

  return $self->render(json => {ok => 1, id => $pkg->{id}, name => $pkg->{name}, state => $pkg->{state}});
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

  # Disable actions before a pending report replacement can invalidate their context.
  my $state   = $self->helpers->reindex_state($package);
  my $payload = {
    package => {
      id         => $package->{id},
      name       => $package->{name},
      detailsUrl => $self->url_for('package_details', id => $package->{id})->to_string
    },
    checkoutDir  => $package->{checkout_dir},
    currentPath  => $filename,
    breadcrumbs  => $self->_file_browser_breadcrumbs($package, $filename),
    checksum     => $state->{checksum},
    reindexing   => $state->{reindexing},
    rebuildStage => $state->{rebuild_stage}
  };

  if ($ctx->{unavailable}) {
    $payload->{kind} = 'unavailable';
  }
  elsif (-d $file) {
    $payload->{kind}    = 'directory';
    $payload->{entries} = $self->_file_browser_entries($package, $file, $filename);
  }
  else {
    my $from = $self->param('from') // '';
    $payload->{kind}   = 'file';
    $payload->{source} = $self->_file_browser_source($package, $file, $filename, $from =~ /^[1-9]\d*$/ ? $from : 1);
  }

  return $self->render(json => $payload);
}

# Package content is untrusted, so it must never render on this origin: always a download, never sniffed
sub file_raw ($self) {
  return unless my $ctx = $self->_file_browser_context;
  return $self->reply->not_found if $ctx->{unavailable} || -d $ctx->{file};

  my $name    = $ctx->{file}->basename;
  my $ascii   = $name =~ s/[^\x20-\x7e]|["\\]/_/gr;
  my $headers = $self->res->headers;
  $headers->content_type('application/octet-stream');
  $headers->header('X-Content-Type-Options' => 'nosniff');
  $headers->content_disposition(
    qq{attachment; filename="$ascii"; filename*=UTF-8''} . url_escape(encode('UTF-8', $name)));
  return $self->reply->asset(Mojo::Asset::File->new(path => $ctx->{file}));
}

sub _file_browser_context ($self) {
  my $filename = $self->stash('file');

  # Reject parent traversal; this also forbids otherwise valid names containing "..".
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

  my $unpacked
    = checkout_path($self->app->config->{checkout_dir}, $package->{name}, $package->{checkout_dir}, '.unpacked');

  # No unpacked tree at all, which normally means it is being torn down and rebuilt right now (an admin
  # running "script/cavil unpack", a re-import). The report itself keeps working throughout, so this is a
  # temporary gap in the file browser and not a missing page - the callers say so rather than 404ing.
  return {filename => $filename, package => $package, unavailable => 1} unless -d $unpacked;

  my $file = $unpacked->child($filename);
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

sub _file_browser_source ($self, $package, $file, $filename, $from) {
  my $file_id = 0;
  my %info_by_line;
  if (
    my $matched
    = $self->app->pg->db->select('matched_files', ['id'],
      {package => $package->{id}, filename => $filename, generation => 0})->hash
    )
  {
    $file_id      = $matched->{id};
    %info_by_line = %{$self->snippets->file_line_info($package->{id}, $file_id)};
  }

  # Above the budget the file is shown one window at a time, starting wherever the reviewer asked for (a
  # deep link to a line, or paging on from the previous window), so every part of it stays reachable
  my $max      = $self->app->config->{max_file_browser_size} // 256_000;
  my $windowed = $max && -s $file > $max;
  my ($bytes, $more);
  if ($windowed) {
    (my $window, $more) = _read_window($file, $from, $max);
    $bytes = join '', map {"$_\n"} @$window;
  }
  else { ($bytes, $from) = ($file->slurp, 1) }

  my @text = split /\n/, $self->maybe_utf8($bytes), -1;
  pop @text if @text && $text[-1] eq '';
  my @lines = map { my $nr = $from + $_; [$nr, {%{$info_by_line{$nr} // {risk => 0}}}, $text[$_]] } 0 .. $#text;

  my $source = {
    id       => $file_id,
    lines    => lines_context(\@lines),
    name     => $package->{name},
    filename => $filename,
    rawUrl   => $self->url_for('file_raw', id => $package->{id}, file => $filename)->to_string
  };
  return $source unless $windowed;

  # The match map from indexing covers the whole file, so the reviewer can see what lies outside the window.
  # Real pattern matches (any risk, keyed on the pattern id) and unresolved snippets (risk 9) count the same;
  # cleared and covered boilerplate asserts no license and has neither.
  my $to = $from + @lines - 1;
  my ($above, $below) = (0, 0);
  for my $nr (keys %info_by_line) {
    my $info = $info_by_line{$nr};
    next unless defined $info->{pid} || ($info->{risk} // 0) == 9;
    $above++ if $nr < $from;
    $below++ if $nr > $to;
  }
  $source->{window}
    = {from => $from, to => $to, more => $more ? \1 : \0, matchesAbove => $above, matchesBelow => $below};

  return $source;
}

# Stream fixed-size chunks, so neither the lines before the window nor one enormous line (minified code) is
# ever held whole. A line running past the byte budget is clipped and ends the window.
sub _read_window ($file, $from, $budget) {
  my $handle = $file->open('<');
  my ($nr, $used, $line, $open, $more, @lines) = (1, 0, '');
CHUNK: while (read $handle, my $chunk, 65536) {
    for my $piece (split /(?<=\n)/, $chunk) {
      my $ends = $piece =~ s/\n\z//;
      if ($nr >= $from) {
        if (!$open && (@lines >= WINDOW_LINES || $used >= $budget)) { $more = 1; last CHUNK }
        my $take = substr $piece, 0, $budget > $used ? $budget - $used : 0;
        $line .= $take;
        $used += length($take) + 1;
      }
      $open = !$ends;
      next if $open;
      push @lines, $line if $nr >= $from;
      ($line, $nr) = ('', $nr + 1);
    }
  }
  push @lines, $line if $open && $nr >= $from;

  return (\@lines, $more);
}

sub list_recent ($self) {
  $self->render;
}

sub list_ephemeral ($self) {
  $self->render;
}

# Just hooking ajax
sub list_reviews { }

sub reindex_package ($self) {

  # Somebody is sitting in front of the report waiting for the rebuild, so it goes in at the top of the
  # ladder in Cavil::Util, ahead of incoming imports and the weekly sweep. A package that is already
  # rebuilding is not an error: the request is recorded and runs right after, so the answer is "queued",
  # not "not found" - only an ineligible package (gone, obsolete, never indexed) is a 404.
  return $self->reply->not_found unless my $queued = $self->packages->reindex($self->stash('id'), PRIORITY_WAITING);

  return $self->render(json => {ok => 1, queued => $queued});
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
  return $self->render(json => {error => 'Package not found'}, status => 404) unless $pkg;

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
    return $self->render(json => {error => 'Missing decision'}, status => 400);
  }
  $pkg->{review_timestamp} = 1;
  $pkg->{ai_assisted}      = 0;

  $self->packages->update($pkg);

  $self->app->log->info(qq{Review by $user: $pkg->{name} ($id) is $pkg->{state}:}, $result);

  $self->render(json => {ok => 1, id => $pkg->{id}, name => $pkg->{name}, state => $pkg->{state}});
}

1;
