# Copyright (C) 2019 SUSE Linux GmbH
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

package Cavil::Controller::Snippet;
use Mojo::Base 'Mojolicious::Controller', -signatures;

use Mojo::File        qw(path);
use Cavil::ReportUtil qw(smart_edit_snippet spdx_edit_snippet);
use Cavil::Util       qw(pattern_matches pattern_contains_redundant_skip pattern_checksum);
use Mojo::JSON        qw(true false);

my $CHECKSUM_RE = qr/^(?:[a-f0-9]{32}|manual[\w:-]+)$/i;

sub approve ($self) {
  my $v = $self->validation;
  $v->required('license')->in('true', 'false');
  return $self->reply->json_validation_error if $v->has_error;
  my $license = $v->param('license');

  my $id = $self->param('id');
  $self->snippets->approve($id, $license);
  my $user = $self->session('user');
  $self->app->log->info(qq{Snippet $id approved by $user (License: $license))});

  # The stored fold/clear/overlap resolution is derived from the snippet's license, so a manual
  # approval has to refresh it. Re-analyze every package this snippet appears in (mirrors the
  # automatic classify task) - analyze recomputes the resolution and the cached report.
  my $pkgs = $self->packages;
  $pkgs->analyze($_->{package})
    for $self->pg->db->query('SELECT DISTINCT package FROM file_snippets WHERE snippet = ?', $id)->hashes->each;

  $self->render(json => {message => 'ok'});
}

sub closest ($self) {
  my $v = $self->validation;
  $v->required('text');
  $v->optional('exclude')->num;
  return $self->reply->json_validation_error if $v->has_error;

  my $text     = $v->param('text');
  my $exclude  = $v->param('exclude');
  my $patterns = $self->patterns;

  # Ask for 2 matches when excluding, in case the best match is the excluded pattern itself
  my $matches = $patterns->closest_matches($text, defined $exclude ? 2 : 1);
  my $match   = $matches->[0];
  $match = $matches->[1] if defined $exclude && $match && $match->{pattern} == $exclude;

  return $self->render(json => {pattern => undef}) unless $match;
  my $pattern = $patterns->find($match->{pattern});
  return $self->render(json => {pattern => undef}) unless $pattern;
  $pattern->{similarity} = int(($match->{match} // 0) * 1000 + 0.5) / 10;

  $self->render(
    json => {
      pattern => {
        id         => $pattern->{id},
        text       => $pattern->{pattern},
        license    => $pattern->{license},
        risk       => $pattern->{risk},
        package    => $pattern->{packname},
        similarity => $pattern->{similarity}
      }
    }
  );
}

my %BATCH_KINDS = map { $_ => 1 } qw(
  create-pattern create-ignore create-glob mark-non-license
  propose-pattern propose-ignore propose-glob propose-missing
);

my %ADMIN_ONLY_KINDS = map { $_ => 1 } qw(create-pattern create-ignore create-glob mark-non-license);

# Glob proposals are file-path based, not snippet based, so they carry no snippet id.
my %SNIPPETLESS_KINDS = map { $_ => 1 } qw(propose-glob create-glob);

# Apply a list of snippet decisions as a single batch.
#
# All actions are validated up front. If any action fails validation, nothing
# is written and the response carries a per-action error list. Otherwise the
# actions are applied sequentially with reindex calls suppressed, then one
# reindex job is queued per affected package - so a batch of N create-pattern
# actions on the same package produces exactly one reindex, never a race.
sub batch_decision ($self) {
  my $body = $self->req->json;
  return $self->render(json => {error => 'Request body must be JSON'}, status => 400)
    unless $body && ref $body eq 'HASH' && ref $body->{actions} eq 'ARRAY';

  my $actions = $body->{actions};
  return $self->render(json => {error => 'No actions provided'}, status => 400) unless @$actions;

  my $is_admin = $self->current_user_has_role('admin');

  # Phase 1: validate everything up front; surface all errors at once.
  my @results;
  my $worst_status = 200;
  for my $a (@$actions) {
    my $error = $self->_validate_action($a, $is_admin);
    if (defined $error) {
      push @results, {error => $error->{message}};
      $worst_status = $error->{status} if $error->{status} > $worst_status;
    }
    else {
      push @results, {ok => \1};
    }
  }
  if ($worst_status != 200) {
    return $self->render(json => {ok => \0, results => \@results}, status => $worst_status);
  }

  # Phase 2: apply each action, deferring per-package reindex jobs until the
  # whole batch is done. If any application step fails we still report what
  # succeeded but mark the failed index so the caller can show errors.
  my %packages_to_reindex;
  for my $i (0 .. $#$actions) {
    my $result = $self->_apply_action($actions->[$i], \%packages_to_reindex);
    $results[$i] = $result;
    if ($result->{error}) {
      my $s = delete($result->{status}) // 409;
      $worst_status = $s if $s > $worst_status;
    }
  }

  # Trigger reindex once per affected package, after all writes are done.
  $self->packages->reindex($_, 3) for sort { $a <=> $b } keys %packages_to_reindex;

  my $status = $worst_status == 200 ? 200 : $worst_status;
  $self->render(json => {ok => $status == 200 ? \1 : \0, results => \@results}, status => $status);
}

sub edit ($self) {
  $self->render;
}

sub from_file ($self) {
  my $v = $self->validation;
  $v->optional('hash')->like($CHECKSUM_RE);
  $v->optional('from');
  return $self->reply->json_validation_error if $v->has_error;

  my $file_id    = $self->stash('file');
  my $first_line = $self->stash('start');
  my $last_line  = $self->stash('end');

  my $snippets = $self->snippets;
  return $self->reply->not_found unless defined(my $snippet = $snippets->from_file($file_id, $first_line, $last_line));

  my $hash = $v->param('hash') // '';
  my $from = $v->param('from') // '';
  $self->respond_to(
    json => sub { $self->render(json => {snippet => $snippet, hash => $hash, from => $from}) },
    any  => sub {
      $self->redirect_to($self->url_for('edit_snippet', id => $snippet)->query(hash => $hash, from => $from));
    }
  );
}

sub list ($self) {
  $self->render;
}

sub list_meta ($self) {
  my $v = $self->validation;
  $v->optional('isClassified')->in('true', 'false');
  $v->optional('isApproved')->in('true', 'false');
  $v->optional('isLegal')->in('true', 'false');
  $v->optional('notLegal')->in('true', 'false');
  $v->optional('confidence')->num(0, 100);
  $v->optional('timeframe')->in('any', 'year', 'month', 'week', 'day', 'hour');
  $v->optional('before')->num;
  $v->optional('offset')->num;
  $v->optional('resolution')->in('any', 'unresolved', 'fold', 'clear', 'overlap', 'covered');
  $v->optional('order')->in('occurrences', 'packages', 'risk', 'recent');
  $v->optional('search');    # free text, used only as a bound parameter; empty means "no search"
  return $self->reply->json_validation_error if $v->has_error;
  my $is_classified = $v->param('isClassified') // 'true';
  my $is_approved   = $v->param('isApproved')   // 'false';
  my $is_legal      = $v->param('isLegal')      // 'true';
  my $not_legal     = $v->param('notLegal')     // 'true';
  my $confidence    = $v->param('confidence')   // 100;
  my $timeframe     = $v->param('timeframe')    // 'any';
  my $before        = $v->param('before')       // 0;
  my $offset        = $v->param('offset')       // 0;
  my $resolution    = $v->param('resolution')   // 'any';
  my $order         = $v->param('order')        // 'recent';
  my $search        = $v->param('search')       // '';

  my $unclassified = $self->snippets->unclassified(
    {
      before        => $before,
      confidence    => $confidence,
      is_classified => $is_classified,
      is_approved   => $is_approved,
      is_legal      => $is_legal,
      not_legal     => $not_legal,
      offset        => $offset,
      order         => $order,
      timeframe     => $timeframe,
      resolution    => $resolution,
      search        => $search
    }
  );

  my $snippets = $unclassified->{snippets};
  for my $snippet (@$snippets) {
    $snippet->{$_} = $snippet->{$_} ? true : false for qw(embargoed license classified approved);
  }

  $self->render(json => {snippets => $snippets, hasMore => $unclassified->{has_more} ? true : false});
}

sub meta ($self) {
  my $id       = $self->param('id');
  my $snippet  = $self->snippets->with_context($id);
  my $patterns = $self->patterns;
  my $licenses = $patterns->autocomplete;
  my $pattern  = $patterns->closest_pattern($snippet->{text}) // {};
  $self->render(json => {snippet => $snippet, licenses => $licenses, closest => $pattern->{license}});
}

sub smart_edit ($self) {
  my $snippet = $self->snippets->with_context($self->param('id')) or return $self->reply->not_found;
  my $mode    = $self->param('mode') // 'smart';
  my $result  = $mode eq 'spdx' ? spdx_edit_snippet($snippet) : smart_edit_snippet($snippet);
  $self->render(
    json => {pattern => $result->{text}, start_line => $result->{start_line}, changed => $result->{changed} ? \1 : \0});
}

sub _check_form_keys ($form, @required) {
  for my $key (@required) {
    return "Missing required field: $key"
      unless defined $form->{$key} && (ref $form->{$key} ? 1 : length $form->{$key});
  }
  return undef;
}

sub _bad       ($message) { return {message => $message, status => 400} }
sub _forbidden ($message) { return {message => $message, status => 403} }
sub _conflict  ($message) { return {message => $message, status => 409} }

sub _validate_action ($self, $a, $is_admin) {
  return _bad('Missing action kind')        unless ref $a eq 'HASH' && defined(my $kind = $a->{kind});
  return _bad("Unknown action kind: $kind") unless $BATCH_KINDS{$kind};
  return _forbidden('Permission denied') if $ADMIN_ONLY_KINDS{$kind} && !$is_admin;
  return _bad('Missing snippet id')
    unless $SNIPPETLESS_KINDS{$kind} || (defined $a->{snippetId} && $a->{snippetId} =~ /^\d+\z/);
  return _bad('Missing form data') unless ref(my $form = $a->{formData}) eq 'HASH';

  if ($kind eq 'create-pattern') {
    if (my $err = _check_form_keys($form, qw(license pattern risk))) { return _bad($err) }
    return _bad('Risk must be numeric') unless $form->{risk} =~ /^\d+\z/;
  }
  elsif ($kind eq 'propose-pattern') {
    if (my $err = _check_form_keys($form, qw(license pattern risk))) { return _bad($err) }
    return _bad('Risk must be numeric') unless $form->{risk} =~ /^\d+\z/;

    my $snippet = $self->snippets->find($a->{snippetId});
    return _bad('Snippet not found') unless $snippet;
    return _bad('License pattern does not match the original snippet')
      unless pattern_matches($form->{pattern}, $snippet->{text});
    return _bad('License pattern contains redundant $SKIP at beginning or end')
      if pattern_contains_redundant_skip($form->{pattern});
  }
  elsif ($kind eq 'propose-missing') {
    if (my $err = _check_form_keys($form, qw(hash from pattern))) { return _bad($err) }
    return _bad('Invalid hash format') unless $form->{hash} =~ $CHECKSUM_RE;
    my $edited = $form->{edited} // '0';
    return _bad('Only unedited snippets can be reported as missing license') if $edited && $edited ne '0';
  }
  elsif ($kind eq 'create-ignore') {
    if (my $err = _check_form_keys($form, qw(hash from))) { return _bad($err) }
    return _bad('Invalid hash format') unless $form->{hash} =~ $CHECKSUM_RE;
  }
  elsif ($kind eq 'mark-non-license') {
    if (my $err = _check_form_keys($form, qw(hash))) { return _bad($err) }
    return _bad('Invalid hash format')        unless $form->{hash} =~ $CHECKSUM_RE;
    return _bad('Snippet not found for hash') unless $self->snippets->id_for_checksum($form->{hash});
  }
  elsif ($kind eq 'propose-ignore') {
    if (my $err = _check_form_keys($form, qw(hash from pattern))) { return _bad($err) }
    return _bad('Invalid hash format') unless $form->{hash} =~ $CHECKSUM_RE;
    my $edited = $form->{edited} // '0';
    return _bad('Only unedited snippets can be ignored') if $edited && $edited ne '0';
  }
  elsif ($kind eq 'propose-glob' || $kind eq 'create-glob') {
    if (my $err = _check_form_keys($form, qw(glob))) { return _bad($err) }

    # A glob only helps if it actually covers files in this package's report. Check it at propose
    # time (the cheap, bounded matched_files set) so a typo or wrong prefix is caught before it
    # ever reaches the Change Proposals page. Skipped for create-glob: by acceptance time the
    # proposal already passed this gate, and a reindex could legitimately have changed the files.
    my $package = $form->{package};
    if ($kind eq 'propose-glob' && defined $package && $package =~ /^\d+\z/) {
      return _bad('Glob does not match any files in the package report')
        unless $self->packages->glob_matches_report_files($package, $form->{glob});
    }
  }

  return undef;
}

sub _apply_action ($self, $a, $packages_to_reindex) {
  my $kind = $a->{kind};
  my $form = $a->{formData};
  my $id   = $a->{snippetId};

  my $patterns = $self->patterns;
  my $snippets = $self->snippets;
  my $packages = $self->packages;
  my $users    = $self->users;
  my $owner_id = $users->id_for_login($self->current_user);

  my $every = sub ($key) {
    my $v = $form->{$key};
    return [] unless defined $v;
    return $v if ref $v eq 'ARRAY';
    return [split /,/, $v];
  };

  if ($kind eq 'create-pattern') {
    my $contributor_id = $form->{contributor} ? $users->id_for_login($form->{contributor}) : undef;
    my $pattern        = $patterns->create(
      license           => $form->{license},
      pattern           => $form->{pattern},
      risk              => $form->{risk},
      patent            => $form->{patent},
      trademark         => $form->{trademark},
      export_restricted => $form->{export_restricted},
      cla               => $form->{cla},
      eula              => $form->{eula},
      owner             => $owner_id,
      contributor       => $contributor_id
    );
    return {kind => $kind, error => 'Conflicting license pattern already exists'} if $pattern->{conflict};

    if (my $checksum = $form->{checksum}) { $patterns->remove_proposal($checksum) }
    my $pkgs = $snippets->packages_for_snippet($id);
    $packages_to_reindex->{$_} = 1 for @$pkgs;
    return {kind => 'pattern', id => $pattern->{id}, packages => $pkgs};
  }

  if ($kind eq 'create-ignore') {
    my $contributor_id = $form->{contributor} ? $users->id_for_login($form->{contributor}) : undef;
    $packages->ignore_line(
      {package => $form->{from}, hash => $form->{hash}, owner => $owner_id, contributor => $contributor_id});
    $patterns->remove_proposal($form->{hash});
    return {kind => 'ignore'};
  }

  if ($kind eq 'mark-non-license') {
    my $sid = $snippets->id_for_checksum($form->{hash});
    return {kind => $kind, error => 'Snippet not found for hash'} unless $sid;
    $patterns->remove_proposal($form->{hash});
    $snippets->mark_non_license($sid);
    my $pkgs = $snippets->packages_for_snippet($sid);
    $packages_to_reindex->{$_} = 1 for @$pkgs;
    return {kind => 'non-license', packages => $pkgs};
  }

  if ($kind eq 'propose-pattern') {
    my $result = $patterns->propose_create(
      snippet              => $id,
      pattern              => $form->{pattern},
      highlighted_keywords => $every->('highlighted-keywords'),
      highlighted_licenses => $every->('highlighted-licenses'),
      edited               => $form->{edited},
      license              => $form->{license},
      risk                 => $form->{risk},
      package              => $form->{package},
      patent               => $form->{patent},
      trademark            => $form->{trademark},
      export_restricted    => $form->{export_restricted},
      cla                  => $form->{cla},
      eula                 => $form->{eula},
      owner                => $owner_id
    );
    return {
      kind   => $kind,
      status => 400,
      error  => 'This license and risk combination is not allowed, only use pre-existing licenses'
      }
      if $result->{license_conflict};
    return {kind => $kind, error => 'Conflicting license pattern already exists'} if $result->{conflict};
    return {kind => $kind, error => 'Conflicting license pattern proposal already exists'}
      if $result->{proposal_conflict};
    return {kind => 'proposal'};
  }

  if ($kind eq 'propose-ignore') {
    my $result = $patterns->propose_ignore(
      snippet              => $id,
      hash                 => $form->{hash},
      from                 => $form->{from},
      pattern              => $form->{pattern},
      highlighted_keywords => $every->('highlighted-keywords'),
      highlighted_licenses => $every->('highlighted-licenses'),
      edited               => $form->{edited},
      package              => $form->{package},
      owner                => $owner_id
    );
    return {kind => $kind, error => 'Conflicting ignore pattern already exists'} if $result->{conflict};
    return {kind => $kind, error => 'Conflicting ignore pattern proposal already exists'}
      if $result->{proposal_conflict};
    return {kind => 'proposal'};
  }

  if ($kind eq 'propose-glob') {
    my $result = $patterns->propose_glob(
      glob        => $form->{glob},
      from        => $form->{from},
      package     => $form->{package},
      reason      => $form->{reason},
      ai_assisted => $form->{ai_assisted},
      owner       => $owner_id
    );
    return {kind => $kind, error => 'Conflicting ignore glob already exists'}          if $result->{conflict};
    return {kind => $kind, error => 'Conflicting ignore glob proposal already exists'} if $result->{proposal_conflict};
    return {kind => 'proposal'};
  }

  if ($kind eq 'create-glob') {

    # Pre-check so a concurrent accept of the same glob fails cleanly instead of hitting the
    # unique index on ignored_files.glob with a database exception.
    return {kind => $kind, error => 'Conflicting ignore glob already exists'}
      if $self->ignored_files->find_glob($form->{glob});

    $self->ignored_files->add($form->{glob}, $self->current_user, $form->{contributor});
    $patterns->remove_proposal($form->{checksum}) if $form->{checksum};

    # Globs are global but apply lazily; reindex the originating package so its report updates now.
    $packages_to_reindex->{$form->{package}} = 1 if $form->{package};
    return {kind => 'glob'};
  }

  if ($kind eq 'propose-missing') {
    my $result = $patterns->propose_missing(
      snippet              => $id,
      hash                 => $form->{hash},
      from                 => $form->{from},
      pattern              => $form->{pattern},
      highlighted_keywords => $every->('highlighted-keywords'),
      highlighted_licenses => $every->('highlighted-licenses'),
      edited               => $form->{edited},
      package              => $form->{package},
      owner                => $owner_id
    );
    return {kind => $kind, error => 'Conflicting license pattern already exists'}  if $result->{conflict};
    return {kind => $kind, error => 'Conflicting pattern proposal already exists'} if $result->{proposal_conflict};
    return {kind => 'missing'};
  }

  return {kind => $kind, error => "Unknown action kind: $kind"};
}

1;
