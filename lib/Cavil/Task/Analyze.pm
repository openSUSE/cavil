# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package Cavil::Task::Analyze;
use Mojo::Base 'Mojolicious::Plugin', -signatures;

use Cavil::ReportUtil qw(new_unresolved_files report_checksum report_shortname summary_delta summary_delta_score);
use Mojo::JSON        qw(from_json to_json);

sub register ($self, $app, $config) {
  $app->minion->add_task(analyze  => \&_analyze);
  $app->minion->add_task(analyzed => \&_analyzed);
}

sub _analyze ($job, $id) {
  my $app    = $job->app;
  my $minion = $app->minion;
  my $pkgs   = $app->packages;
  my $log    = $app->log;
  my $config = $app->config;

  # Protect from race conditions
  return $job->finish("Package $id is not indexed yet") unless $pkgs->is_indexed($id);
  return $job->finish("Package $id is already being processed")
    unless my $guard = $minion->guard("processing_pkg_$id", 172800);

  $app->plugins->emit_hook('before_task_analyze');
  $app->pg->db->update('bot_reports', {ldig_report => undef}, {package => $id});

  my $reports = $app->reports;
  my $pkg     = $pkgs->find($id);

  # Score any new or stale snippets first (cheap, local), then refresh the stored resolutions
  # (fold/clear/overlap) before building the report - so scores are always current when the report is
  # built and every consumer reads the same decision from file_snippets.resolution.
  $app->patterns->score_package_snippets($id);
  $app->snippets->resolve_snippets($id);

  # Backfill declared licenses for vendored components whose metadata carried none, from Cavil's own
  # detected licenses. This MUST happen before the report is built and cached below, otherwise the cached
  # report (UI/MCP) would show the pre-backfill licenses while the SPDX export (read from the DB later)
  # shows the backfilled ones.
  _backfill_component_licenses($app->pg->db, $id);

  my $specfile = $reports->specfile_report($id);
  my $dig      = $reports->dig_report($id);

  my $chksum    = report_checksum($specfile, $dig);
  my $shortname = report_shortname($reports->shortname($chksum), $specfile, $dig);
  my $flags     = $pkgs->flags($id);

  # Free up memory
  undef $specfile;

  my $new_candidates = [];

  # Unresolved keyword matches. Count the full set (missed_snippets), NOT the expansion-truncated
  # $dig->{snippets}: max_expanded_files only caps how many file previews the report renders, it must
  # never shrink the stored count. (Mirrors the full-set walk in Cavil::Model::Reports::summary.)
  my $unresolved = 0;
  if (my $missed = $dig->{missed_snippets}) {
    my %seen;
    for my $file (keys %$missed) {
      $seen{$_->[2]} = 1 for @{$missed->{$file}};
    }
    $unresolved = keys %seen;
  }

  # Do not leak Postgres connections
  {
    my $db = $app->pg->db;
    $db->update('bot_packages', {checksum => $shortname, unresolved_matches => $unresolved, %$flags}, {id => $id});
    $db->update('bot_reports', {ldig_report => to_json($dig)}, {package => $id});
    if ($pkg->{state} ne 'new') {

      # in case we reindexed an old pkg, check if 'new' packages now match.
      # new patterns might change the story
      $new_candidates = $db->select('bot_packages', 'id',
        {name => $pkg->{name}, indexed => {'!=' => undef}, id => {'!=' => $pkg->{id}}, state => 'new'})->hashes;
    }
  }

  undef $guard;
  my $prio = $job->info->{priority};
  my $analyzed_id
    = $minion->enqueue(analyzed => [$id] => {parents => [$job->id], priority => $prio, notes => {"pkg_$id" => 1}});
  $pkgs->generate_spdx_report($id, {parents => [$analyzed_id]}) if $config->{always_generate_spdx_reports};

  for my $candidate (@$new_candidates) {
    $minion->enqueue(
      analyzed => [$candidate->{id}] => {parents => [$job->id], priority => 9, notes => {"pkg_$id" => 1}});
  }
  $log->info("[$id] Analyzed $shortname");
}

# Fill each vendored component that has no metadata license with the license Cavil detected in the
# component's own directory. Deliberately conservative: only when the component's directory is
# unambiguous - it holds exactly one component (so a shared listing file like Go's vendor/modules.txt
# cannot cross-attribute one directory's license to many modules) and Cavil detected exactly one license
# there (so we never fabricate a misleading "A AND B" expression).
sub _backfill_component_licenses ($db, $id) {
  my $all  = $db->select('package_components', ['id', 'source', 'license'], {package => $id})->hashes->to_array;
  my @todo = grep { !defined $_->{license} && defined $_->{source} } @$all;
  return unless @todo;

  my $dir_of = sub ($path) { $path =~ m{/} ? $path =~ s{/[^/]*$}{}r : '' };

  # How many components (with or without a license) map to each directory. A directory shared by more
  # than one component is ambiguous - a license detected there cannot be attributed to a single component
  # - so it is left alone. Counting only the license-less ones would wrongly treat a directory that holds
  # one licensed and one unlicensed component as unambiguous and cross-attribute the license.
  my %components_in_dir;
  $components_in_dir{$dir_of->($_->{source})}++ for grep { defined $_->{source} } @$all;

  # Distinct SPDX licenses Cavil detected directly in each directory
  my %dir_licenses;
  my $matches = $db->query(
    'SELECT mf.filename AS filename, lp.spdx AS spdx
       FROM matched_files mf
       JOIN pattern_matches pm ON pm.file = mf.id
       JOIN license_patterns lp ON pm.pattern = lp.id
      WHERE mf.package = ? AND pm.ignored = false AND lp.spdx <> ?', $id, ''
  )->hashes;
  $dir_licenses{$dir_of->($_->{filename})}{$_->{spdx}} = 1 for $matches->each;

  for my $component (@todo) {
    my $dir = $dir_of->($component->{source});
    next if $components_in_dir{$dir} > 1;
    my $set = $dir_licenses{$dir} or next;
    next if keys %$set != 1;
    $db->update('package_components', {license => (keys %$set)[0]}, {id => $component->{id}});
  }
}

sub _analyzed ($job, $id) {
  my $app     = $job->app;
  my $config  = $app->config;
  my $minion  = $app->minion;
  my $reports = $app->reports;
  my $pkgs    = $app->packages;

  # Protect from race conditions
  return $job->finish("Package $id is not indexed yet") unless $pkgs->is_indexed($id);
  return $job->finish("Package $id is already being processed")
    unless my $guard = $minion->guard("processing_pkg_$id", 172800);

  # Only "new" and "acceptable" can be reviewed automatically. Already
  # reviewed packages still need their notice refreshed so it doesn't
  # display a stale diff from before the package was approved.
  my $pkg = $pkgs->find($id);
  return unless my $pkg_shortname = $pkg->{checksum};
  return unless $pkg->{indexed};
  if ($pkg->{state} ne 'new' && $pkg->{state} ne 'acceptable') {
    _refresh_notice($app, $pkg);
    return;
  }

  # Incomplete checkout
  my $specfile = $reports->specfile_report($id);
  if ($specfile->{incomplete_checkout}) {
    _look_for_smallest_delta($app, $pkg, 0, 0, 1) if $pkg->{state} eq 'new';
    return;
  }

  # Fast-track packages that are configured to always be acceptable
  my $name                = $pkg->{name};
  my $acceptable_packages = $config->{acceptable_packages} || [];
  if (grep { $name eq $_ } @$acceptable_packages) {
    $pkg->{state}            = 'acceptable';
    $pkg->{review_timestamp} = 1;
    $pkg->{reviewing_user}   = undef;
    $pkg->{result}           = "Accepted because of package name ($name)";
    $pkgs->update($pkg);
    return;
  }

  # Every package above threshold needs a human review before future versions can be auto-accepted
  if (!$pkgs->has_manual_review($pkg->{name})) {

    my $auto_accept_risk = $config->{auto_accept_risk};
    my $risk             = $reports->risk_is_acceptable($pkg_shortname);
    if (defined($risk) && $risk > 0 && $auto_accept_risk && $risk <= $auto_accept_risk) {
      $pkg->{state}            = 'acceptable';
      $pkg->{review_timestamp} = 1;
      $pkg->{reviewing_user}   = undef;
      $pkg->{result} = "Accepted because of low risk ($risk) and auto-accept risk threshold ($auto_accept_risk)";
      $pkgs->update($pkg);
      return;
    }

    _look_for_smallest_delta($app, $pkg, 0, 0, 0) if $pkg->{state} eq 'new';
    return;
  }

  # Exclude "unacceptable" reviews
  my $packages = $pkgs->history($name, $pkg_shortname, $id);
  return if grep { $_->{state} eq 'unacceptable' } @$packages;

  my ($found_acceptable_by_lawyer, $found_acceptable);
  for my $p (@$packages) {

    # ignore obsolete reviews - possibly harmful as we don't reindex those
    next                                   if $p->{obsolete};
    $found_acceptable_by_lawyer = $p->{id} if $p->{state} eq 'acceptable_by_lawyer';
    last                                   if $found_acceptable_by_lawyer;
    $found_acceptable = $p->{id}           if $p->{state} eq 'acceptable';
  }

  # Try to upgrade from "acceptable" to "acceptable_by_lawyer"
  if ($pkg->{state} eq 'acceptable') {
    if (my $c_id = $found_acceptable_by_lawyer) {
      $pkg->{state}            = 'acceptable_by_lawyer';
      $pkg->{review_timestamp} = 1;
      $pkg->{reviewing_user}   = undef;
      $pkg->{ai_assisted}      = 0;
      $pkg->{result}           = "Accepted because reviewed by lawyer under the same license ($c_id)";
      $pkgs->update($pkg);
    }
    return;    # the rest is for 'new'
  }

  # Previously reviewed and accepted
  if (my $f_id = $found_acceptable_by_lawyer || $found_acceptable) {
    $pkg->{state}            = $found_acceptable_by_lawyer ? 'acceptable_by_lawyer' : 'acceptable';
    $pkg->{review_timestamp} = 1;
    $pkg->{reviewing_user}   = undef;
    $pkg->{notice}           = undef;
    $pkg->{diff_report}      = undef;
    $pkg->{result}           = "Accepted because previously reviewed under the same license ($f_id)";
    $pkgs->update($pkg);
    return;
  }

  # Acceptable risk
  if (defined(my $risk = $reports->risk_is_acceptable($pkg_shortname))) {

    # risk 0 is spooky
    unless ($risk) {
      $pkg->{result}      = undef;
      $pkg->{notice}      = 'Manual review is required because of unusually low risk (0)';
      $pkg->{diff_report} = undef;
      $pkgs->update($pkg);
      return;
    }

    $pkg->{state}            = 'acceptable';
    $pkg->{review_timestamp} = 1;
    $pkg->{reviewing_user}   = undef;
    $pkg->{result}           = "Accepted because of low risk ($risk)";
    $pkgs->update($pkg);
  }

  _look_for_smallest_delta($app, $pkg, 1, 1, 0) if $pkg->{state} eq 'new';
}

sub _look_for_smallest_delta ($app, $pkg, $allow_accept, $has_manual_review, $incomplete_checkout) {
  my $pkgs = $app->packages;
  my ($matched_id, $best, $summary) = _smallest_delta($app, $pkg);

  if (defined $matched_id && !$best) {
    $pkg->{result} = undef;
    if ($allow_accept) {
      $pkg->{result}           = "Accepted because of no significant difference ($matched_id)";
      $pkg->{state}            = 'acceptable';
      $pkg->{review_timestamp} = 1;
      $pkg->{reviewing_user}   = undef;
    }

    $pkg->{notice} = "Not found any significant difference against $matched_id";
    if ($incomplete_checkout) {
      $pkg->{notice} .= ', manual review is required because the checkout might be incomplete';
    }
    elsif (!$has_manual_review) {
      $pkg->{notice} .= ', manual review is required because previous reports are missing a reviewing user';
    }

    $pkg->{diff_report} = undef;
    $pkgs->update($pkg);
    return;
  }

  unless ($best) {
    $pkg->{result}      = undef;
    $pkg->{notice}      = 'Manual review is required because no previous reports are available';
    $pkg->{diff_report} = undef;
    $pkgs->update($pkg);
    return;
  }

  $pkgs->update({
    id          => $pkg->{id},
    result      => undef,
    notice      => summary_delta($best, $summary),
    diff_report => _diff_report($app, $pkg->{id}, $best, $summary)
  });
}

# Refresh just the notice column for already-reviewed packages, so the text
# rendered in the report reflects the current dig-report state rather than
# whatever it was when the package was last in 'new' state. Leaves state,
# result, reviewing_user, and review_timestamp untouched.
sub _refresh_notice ($app, $pkg) {
  my ($matched_id, $best, $summary) = _smallest_delta($app, $pkg);

  my ($notice, $diff_report);
  if (defined $matched_id && !$best) {
    $notice = "Not found any significant difference against $matched_id";
  }
  elsif ($best) {
    $notice = summary_delta($best, $summary);
    $notice = undef unless length $notice;
    $diff_report = _diff_report($app, $pkg->{id}, $best, $summary);
  }
  $app->packages->update({id => $pkg->{id}, notice => $notice, diff_report => $diff_report});
}

# Structured, machine-readable companion to the notice text, stored in the
# diff_report column and co-written/cleared at every notice write so the two
# never drift. Currently carries the full (uncapped) list of files with new
# unresolved matches, with file ids, so the report UI can flag them as "new".
# Returns undef when there is no closest match or no new unresolved files (so
# the column is null unless there is something to flag).
sub _diff_report ($app, $id, $best, $summary) {
  return undef unless $best;

  my $cached = $app->reports->cached_dig_report($id);
  my $report = $cached ? from_json($cached) : $app->reports->dig_report($id);
  my $files  = new_unresolved_files($best, $summary, $report->{files});
  return undef unless @$files;

  return to_json({version => 1, closest => $best->{id}, new_unresolved => $files});
}

# Find the closest matching older review. Returns (matched_id, best_summary,
# new_summary). If a zero-delta match is found, best_summary is undef and
# matched_id is the zero-delta review id. Otherwise best_summary is the
# closest non-zero match (or undef when no older reviews exist).
sub _smallest_delta ($app, $pkg) {
  my $reports       = $app->reports;
  my $older_reviews = $app->packages->old_reviews($pkg);
  my $new_summary   = $reports->summary($pkg->{id});

  my ($best, $best_score);
  my %checked;
  for my $old (@$older_reviews) {
    next if $checked{$old->{checksum}};
    my $old_summary = $reports->summary($old->{id});
    my $score       = summary_delta_score($old_summary, $new_summary);
    return ($old->{id}, undef, $new_summary) unless $score;

    $checked{$old->{checksum}} = 1;
    if (!$best || $score < $best_score) {
      $best       = $old_summary;
      $best_score = $score;
    }
  }

  return (undef, $best, $new_summary);
}

1;
