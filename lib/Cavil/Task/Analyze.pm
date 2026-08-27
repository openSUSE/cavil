# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package Cavil::Task::Analyze;
use Mojo::Base 'Mojolicious::Plugin', -signatures;

use Cavil::ReportUtil
  qw(new_license_names new_unresolved_files report_checksum report_shortname summary_delta summary_delta_score);
use Cavil::Util 'to_json_fast';

sub register ($self, $app, $config) {
  $app->minion->add_task(analyze  => \&_analyze);
  $app->minion->add_task(analyzed => \&_analyzed);
}

# A non-zero generation means this analyze finishes a reindex: it builds the report from the rows that
# job indexed alongside the live one, and promotes them in a single transaction at the end. Without a
# generation it is a plain re-analyze of the live report, which is what a snippet approval or an ignored
# line schedules.
sub _analyze ($job, $id, $generation = 0) {
  my $app    = $job->app;
  my $minion = $app->minion;
  my $pkgs   = $app->packages;
  my $log    = $app->log;

  # Protect from race conditions. A build inherits its claim on the package from its index job, because
  # the promote below needs the same protection the indexing did, and hands it back as part of that same
  # transaction. It also cannot require the package to be indexed: on a first import nothing is indexed
  # until this very job promotes.
  my $guard;
  if ($generation) {

    # The package has to still be building this exact generation, or there is nothing to promote. The
    # cleanup sweep discards the rows of a build whose worker died, and this job can come back afterwards
    # (retried by hand, or retried by Minion after a promote that committed and then failed to report
    # success). Swapping then would delete the live report and put nothing in its place.
    return $job->finish("Build $generation of package $id is gone, nothing to promote")
      unless $pkgs->is_building($id, $generation);
  }
  else {
    return $job->finish("Package $id is not indexed yet")         unless $pkgs->is_indexed($id);
    return $job->finish("Package $id is already being processed") unless $guard = $pkgs->claim_guard($id, $job->id);
  }

  $app->plugins->emit_hook('before_task_analyze');

  # The previous report is deliberately left in place. It keeps being served for as long as this takes,
  # and is replaced by the promote below - so a reviewer whose package is reindexed (often by somebody
  # else's new license pattern) keeps the report they were reading instead of watching it disappear.

  my $reports = $app->reports;
  my $pkg     = $pkgs->find($id);

  # Score any new or stale snippets first (cheap, local), then refresh the stored resolutions
  # (fold/clear/overlap) before building the report - so scores are always current when the report is
  # built and every consumer reads the same decision from file_snippets.resolution.
  $app->patterns->score_package_snippets($id, $generation);
  $app->snippets->resolve_snippets($id, $generation);

  # Backfill declared licenses for vendored components whose metadata carried none, from Cavil's own
  # detected licenses. This MUST happen before the report is built and cached below, otherwise the cached
  # report (UI/MCP) would show the pre-backfill licenses while the SPDX export (read from the DB later)
  # shows the backfilled ones.
  _backfill_component_licenses($app->pg->db, $id, $generation);

  # A rebuild can follow a re-unpack, which replaces the sources and with them the spec file. Take a fresh
  # spec file report for it and store it with the promote below, so a reader never sees the new spec file
  # license beside the old file report. A plain re-analyze cannot have new sources, so it uses the cache.
  my $specfile = ($generation ? $reports->build_specfile_report($id) : $reports->specfile_report($id)) // {};
  my $dig      = $reports->dig_report($id, undef, $generation);

  my $chksum    = report_checksum($specfile, $dig);
  my $shortname = report_shortname($reports->shortname($chksum), $specfile, $dig);
  my $flags     = $pkgs->flags($id, $generation);

  # Informational annotations derived from the finished report - today the package's legal documents and
  # how much of each no known license pattern explains. Deliberately computed after the checksum and
  # shortname above and never folded into them: an unexplained remainder is a fact readers need, not a
  # reason to re-review.
  my $annotations = $reports->build_annotations($id, $dig);

  # Free up memory, but first derive the declared (main) license so it can be stored alongside the spec file
  # report below, in lockstep with it.
  my $specfile_json    = $generation && %$specfile ? to_json_fast($specfile) : undef;
  my $declared_license = $reports->declared_license($specfile);
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
    my $tx = $db->begin;

    # The swap. Everything a reader can see changes at this one commit: before it they get the previous
    # report in full, after it the new one, and there is no moment in between where the package has no
    # report at all. If this transaction fails nothing has changed, the old report simply keeps being
    # served, and the build is retried or swept.
    if ($generation) {

      # Deleting matched_files cascades its matches and snippets. fp_files (snippet code search) is a plain
      # map that rides the same swap; it is a no-op when code search is off (no such rows were written).
      $db->delete($_, {package => $id, generation => 0})
        for qw(package_components urls emails copyrights matched_files fp_files);
      $db->update($_, {generation => 0}, {package => $id, generation => $generation})
        for qw(package_components urls emails copyrights pattern_matches file_snippets matched_files fp_files);
    }

    # The build hands the package back in the same commit that makes its report the live one, so there is
    # no moment where the new report is being served while the package still looks busy, and no way for a
    # crash to strand the claim of a build that has already succeeded.
    my %state = (checksum => $shortname, unresolved_matches => $unresolved, %$flags);
    %state = (%state, indexed => \'now()', processing_job => undef, index_stage => undef) if $generation;
    $db->update('bot_packages', \%state, {id => $id});

    # A first import has no cached report row yet.
    my %cached = (ldig_report => to_json_fast($dig), annotations => to_json_fast($annotations));

    # declared_license rides exactly the same condition as specfile_report, so the two never disagree: rewritten
    # on a rebuild (fresh sources), left untouched on a plain re-analyze (cached spec file report kept).
    if (defined $specfile_json) {
      $cached{specfile_report}  = $specfile_json;
      $cached{declared_license} = $declared_license;
    }
    if ($db->select('bot_reports', 'id', {package => $id})->hash) {
      $db->update('bot_reports', \%cached, {package => $id});
    }
    else {
      $db->insert('bot_reports', {package => $id, specfile_report => $specfile_json // '{}', %cached});
    }
    if ($pkg->{state} ne 'new') {

      # New patterns may unblock matching packages still marked new.
      $new_candidates = $db->select('bot_packages', 'id',
        {name => $pkg->{name}, indexed => {'!=' => undef}, id => {'!=' => $pkg->{id}}, state => 'new'})->hashes;
    }

    $tx->commit;
  }

  # This job stops counting as a rebuild of the package right here rather than when it finishes. What is
  # left below is bookkeeping that leaves the report alone, and the package no longer carries a stage - so
  # a reviewer polling in the meantime would be told a rebuild is running with nothing to show for it, and
  # watch the progress bar drop from "Analyzing" back to "Queued" just as the new report lands.
  $job->note("pkg_$id" => undef);

  # A build gave the package back with the promote above; a plain re-analyze gives it back here
  undef $guard;

  # Dropping the note above also took this job out of the package's failed-job count, and a failure down
  # here is still the package's problem - the follow-up work that hands the new report to the reviewer.
  # So it goes back on the way out, and only the successful path stays quiet.
  eval {
    my $prio = $job->info->{priority};
    $minion->enqueue(analyzed => [$id] => {parents => [$job->id], priority => $prio + 1, notes => {"pkg_$id" => 1}});

    # Each of these works on (and claims) the candidate, not this package, so it is noted as the
    # candidate's job - otherwise the cleanup sweep sees no job for a package that is being worked on and
    # takes its claim away underneath it.
    for my $candidate (@$new_candidates) {
      my $cid = $candidate->{id};
      $minion->enqueue(analyzed => [$cid] => {parents => [$job->id], priority => $prio, notes => {"pkg_$cid" => 1}});
    }

    # One fleet-wide classifier job drains any pending snippets.
    $pkgs->classify($id);
  };
  if (my $err = $@) {
    $job->note("pkg_$id" => 1);
    die $err;
  }

  $log->info("[$id] Analyzed $shortname");
}

# Fill each vendored component that has no metadata license with the license Cavil detected in the
# component's own directory. Deliberately conservative: only when the component's directory is
# unambiguous - it holds exactly one component (so a shared listing file like Go's vendor/modules.txt
# cannot cross-attribute one directory's license to many modules) and Cavil detected exactly one license
# there (so we never fabricate a misleading "A AND B" expression).
sub _backfill_component_licenses ($db, $id, $generation = 0) {
  my $all = $db->select('package_components', ['id', 'source', 'license'], {package => $id, generation => $generation})
    ->hashes->to_array;
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
      WHERE mf.package = ? AND mf.generation = ? AND pm.ignored = false AND lp.spdx <> ?', $id, $generation, ''
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
  my $app  = $job->app;
  my $pkgs = $app->packages;

  # Protect from race conditions
  return $job->finish("Package $id is not indexed yet")         unless $pkgs->is_indexed($id);
  return $job->finish("Package $id is already being processed") unless my $guard = $pkgs->claim_guard($id, $job->id);

  _auto_review($app, $id);

  # Code search fingerprints are not built here: a scheduled build (see Task::Cleanup) drains all pending
  # content at once, which keeps segments dense instead of one tiny segment per analyzed package.

  # End of the chain unless a document build follows, so the package is handed back here rather than left to
  # the guard, which would only release it and leave a reindex requested in the meantime waiting for the
  # nightly sweep. A failure skips this on purpose: the release is all the guard does, and the retry that
  # an admin starts from the Minion dashboard hands the package back properly.
  $pkgs->hand_back($id, $job->id);
}

# Everything the automatic review does once the package is claimed, with plenty of early returns for the
# states it leaves alone
sub _auto_review ($app, $id) {
  my $config  = $app->config;
  my $reports = $app->reports;
  my $pkgs    = $app->packages;

  # Only "new" and "acceptable" can be reviewed automatically. Every already
  # reviewed package still needs its notice refreshed on each reindex so it does
  # not display a stale diff from an older pattern set; states other than "new"
  # and "acceptable" are refreshed here, "acceptable" a bit further down (after
  # the incomplete-checkout guard, since it can also be upgraded by a lawyer).
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

  # Already accepted: the auto-accept machinery below is for 'new' packages only.
  # Refresh the notice/diff so a reindex with new patterns cannot leave a stale
  # diff, and still allow the upgrade to 'acceptable_by_lawyer' when a sibling
  # version with the same report was reviewed by a lawyer under the same license.
  if ($pkg->{state} eq 'acceptable') {
    my $siblings = $pkgs->history($pkg->{name}, $pkg_shortname, $id);

    # An "unacceptable" sibling with the same report vetoes the upgrade, exactly
    # as it did for these packages at the (former) unacceptable-history guard.
    unless (grep { $_->{state} eq 'unacceptable' } @$siblings) {
      my $lawyer;
      for my $p (@$siblings) {
        next               if $p->{obsolete};
        $lawyer = $p->{id} if $p->{state} eq 'acceptable_by_lawyer';
        last               if $lawyer;
      }
      if ($lawyer) {
        $pkg->{state}            = 'acceptable_by_lawyer';
        $pkg->{review_timestamp} = 1;
        $pkg->{reviewing_user}   = undef;
        $pkg->{ai_assisted}      = 0;
        $pkg->{result}           = "Accepted because reviewed by lawyer under the same license ($lawyer)";
        $pkgs->update($pkg);
      }
    }

    _refresh_notice($app, $pkg);
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

  $pkgs->update(
    {
      id          => $pkg->{id},
      result      => undef,
      notice      => summary_delta($best, $summary),
      diff_report => _diff_report($best, $summary)
    }
  );
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
    $notice      = summary_delta($best, $summary);
    $notice      = undef unless length $notice;
    $diff_report = _diff_report($best, $summary);
  }
  $app->packages->update({id => $pkg->{id}, notice => $notice, diff_report => $diff_report});
}

# Structured, machine-readable companion to the notice text, stored in the
# diff_report column and co-written/cleared at every notice write so the two
# never drift. Carries the full (uncapped) list of files with new unresolved
# matches, by filename, so the report UI can flag them as "new" (by name, since
# matched_files ids are not stable across reindex). Returns undef when there is
# no closest match or no new unresolved files (so the column is null unless
# there is something to flag).
sub _diff_report ($best, $summary) {
  return undef unless $best;

  my $files    = new_unresolved_files($best, $summary);
  my $licenses = new_license_names($best, $summary);
  return undef unless @$files || @$licenses;

  return to_json_fast({version => 1, closest => $best->{id}, new_unresolved => $files, new_licenses => $licenses});
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
