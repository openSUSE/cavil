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
    %info_by_line = %{$self->_file_browser_line_info($package, $file_id)};
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

sub _file_browser_line_info ($self, $package, $file_id) {
  my $db   = $self->app->pg->db;
  my $info = {};

  my %matched;    # lines covered by a real, curated licensed pattern match
  my $matches = $db->query(
    'SELECT pm.sline, pm.eline, lp.id, lp.license, lp.spdx, lp.risk
       FROM pattern_matches pm JOIN license_patterns lp ON lp.id = pm.pattern
      WHERE pm.package = ? AND pm.file = ? AND pm.ignored = false AND lp.license <> ?', $package->{id}, $file_id, ''
  );
  for my $match ($matches->hashes->each) {
    for my $line ($match->{sline} .. $match->{eline}) {
      $matched{$line} = 1;
      my $current = $info->{$line} // {risk => 0};
      next if $current->{risk} > $match->{risk};
      $info->{$line} = {risk => $match->{risk}, name => $match->{license}, spdx => $match->{spdx}, pid => $match->{id}};
    }
  }

  # Snippets render from their stored resolution (computed once by resolve_snippets): 'fold' as the
  # inferred license, 'clear'/'overlap' as resolved (cleared) noise, anything else as an unresolved
  # snippet. Folded/cleared rows keep the snippet handle so reviewers can correct them inline.
  my $snippets = $db->query(
    'SELECT fs.sline, fs.eline, fs.resolution, s.id, s.hash, s.classified, s.license, s.like_pattern,
            lp.license AS plicense, lp.spdx AS pspdx, lp.risk AS prisk
       FROM file_snippets fs
       JOIN snippets s ON s.id = fs.snippet
       LEFT JOIN license_patterns lp ON lp.id = s.like_pattern
      WHERE fs.package = ? AND fs.file = ?', $package->{id}, $file_id
  );
  for my $snippet ($snippets->hashes->each) {
    next if $snippet->{classified} && !$snippet->{license};

    my $resolution = $snippet->{resolution} // '';
    my $line_info;
    if ($resolution eq 'fold') {
      $line_info = {
        risk    => $snippet->{prisk},
        name    => $snippet->{plicense},
        spdx    => $snippet->{pspdx},
        pid     => $snippet->{like_pattern},
        snippet => $snippet->{id},
        hash    => $snippet->{hash},
        folded  => 1
      };
    }
    elsif ($resolution eq 'clear' || $resolution eq 'overlap') {
      $line_info
        = {risk => 0, name => 'Cleared boilerplate', snippet => $snippet->{id}, hash => $snippet->{hash}, cleared => 1};
    }
    else {
      $line_info
        = {risk => 9, snippet => $snippet->{id}, hash => $snippet->{hash}, name => 'Snippet of missing keywords'};
      $line_info->{pids} = [$snippet->{like_pattern}] if $snippet->{like_pattern};
    }

    # A resolved snippet (fold/clear/overlap) describes the region, but a real licensed match is
    # authoritative for its own line - it must not repaint a line that has its own curated match (e.g. a
    # "Free Software Foundation" match on the first line of a folded GPL header). Unresolved snippets
    # still take over their region (matching the report's needed_lines precedence).
    my $defers_to_match = $resolution =~ /^(?:fold|clear|overlap)$/;
    for my $line ($snippet->{sline} .. $snippet->{eline}) {
      next if $defers_to_match && $matched{$line};
      my $current = $info->{$line} // {risk => 0};
      next if $current->{risk} > $line_info->{risk};    # do not hide a higher-risk match
      $info->{$line} = $line_info;
    }
  }

  return $info;
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
  $validation->optional('acceptable_by_lawyer');
  return $self->reply->json_validation_error if $validation->has_error;

  my $user = $self->session('user');

  my $id  = $self->stash('id');
  my $pkg = $self->packages->find($id);
  return $self->reply->not_found unless $pkg;

  $pkg->{reviewing_user} = $self->users->find(login => $user)->{id};
  my $result = $pkg->{result} = $validation->param('comment') || 'Reviewed ok';

  if ($validation->param('unacceptable')) {
    $pkg->{state} = 'unacceptable';
  }
  elsif ($validation->param('acceptable')) {
    $pkg->{state} = 'acceptable';
  }
  elsif ($validation->param('acceptable_by_lawyer')) {
    $pkg->{state} = 'acceptable_by_lawyer';
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
