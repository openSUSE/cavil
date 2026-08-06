# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package Cavil::Plugin::Helpers;
use Mojo::Base 'Mojolicious::Plugin', -signatures;

use Cavil::Licenses   qw(lic);
use Cavil::ReportUtil qw(license_classification new_license_ids);
use Cavil::Role       qw(roles_with_capability);
use Cavil::Util       qw(external_link_data spdx_link);
use CommonMark        ();
use Mojo::File        qw(path);
use Mojo::JSON        qw(false from_json true);
use Mojo::Util        qw(decode humanize_bytes xml_escape);
use List::Util        qw(first uniq);

sub register ($self, $app, $config) {
  $app->helper('chart_data'                    => \&_chart_data);
  $app->helper('current_user'                  => \&_current_user);
  $app->helper('current_user_roles'            => \&_current_user_roles);
  $app->helper('current_user_has_role'         => \&_current_user_has_role);
  $app->helper('current_user_can'              => \&_current_user_can);
  $app->helper('current_user_has_write_access' => \&_current_user_has_write_access);
  $app->helper('current_user_scopes'           => \&_current_user_scopes);
  $app->helper('lic'                           => sub { shift; lic(@_) });
  $app->helper('maybe_utf8'                    => sub { decode('UTF-8', $_[1]) // $_[1] });
  $app->helper('mcp_report'                    => \&_mcp_report);
  $app->helper('package_summary'               => \&_package_summary);
  $app->helper('proposal_stats'                => sub { shift->patterns->proposal_stats });
  $app->helper('reindex_state'                 => \&_reindex_state);
  $app->helper('report_details'                => \&_report_details);
  $app->helper('reply.json_validation_error'   => \&_json_validation_error);
  $app->helper('spdx_state'                    => \&_spdx_state);
  $app->helper('format_file'                   => \&_format_file);
  $app->helper('markdown_to_safe_html'         => \&_markdown_to_safe_html);
}

sub _markdown_to_safe_html ($c, $text) {
  return '' unless defined $text && length $text;

  # OPT_SAFE strips raw HTML and dangerous URL schemes (javascript:, data:, vbscript:).
  return CommonMark->markdown_to_html($text, CommonMark::OPT_SAFE());
}

sub _chart_data ($c, $hash) {
  my (@licenses, @licenses_html, @num_files, @colours);

  my @codes = ('#117864', '#85c1e9', '#9b59b6', '#ec7063', '#a3e4d7', '#c39bd3', '#c0392b');

  my @sorted_keys = sort { $hash->{$b} <=> $hash->{$a} } keys %$hash;
  while (@sorted_keys) {
    my $first = shift @sorted_keys;
    push(@licenses,      "$first: $hash->{$first} files");
    push(@licenses_html, spdx_link($first));
    push(@num_files,     $hash->{$first});
    push(@colours,       shift @codes);
    delete $hash->{$first};
    last unless @codes;
  }

  my $rest = 0;

  # TODO - we will count files multiple times
  for my $lic (@sorted_keys) {
    $rest += $hash->{$lic};
  }
  if ($rest) {
    push(@licenses,      "Misc: $rest files");
    push(@licenses_html, 'Misc');
    push(@num_files,     $rest);
    push(@colours,       'grey');
  }
  return {licenses => \@licenses, licenses_html => \@licenses_html, 'num-files' => \@num_files, colours => \@colours};
}

# The stages a rebuild passes through, in the order the compact progress bar shows them. A reindex that
# needs no fresh sources skips straight past "Unpacking", which simply advances the bar by two.
my %REBUILD_STAGES = (unpacking => 2, indexing => 3, analyzing => 4);

# The queued jobs that lead to a new report. Deliberately not every job tagged for the package: generating
# an SPDX report leaves the report itself alone, and locking the page for it would be a lie. "analyzed"
# is left out for the same reason and because it runs *after* the promote - counting it would make the
# progress bar drop back to "Queued" for one tick just as the new report goes live. Should it decide a
# follow-up build is needed, that shows up as "reindex_requested" below before it clears it.
my @REBUILD_TASKS = qw(obs_import git_import unpack index index_batch indexed analyze);

# Everything the report page needs to know about a rebuild, cheap enough to poll on a timer. "reindexing"
# spans the whole window, from a report-modifying job being queued to the new report being promoted, and is
# what puts the page into read-only mode: the report on screen no longer matches the patterns that now
# exist, so the file previews no longer mark what the reviewer has already covered and creating more
# patterns against them would be guesswork. "rebuild_stage" follows the build itself, and "checksum"
# changes exactly when a new report is promoted.
sub _reindex_state ($c, $pkg) {
  my $id    = $pkg->{id};
  my $stage = $REBUILD_STAGES{$pkg->{index_stage} // ''};

  # The queue is the common signal, but a package can also be mid-build with its job already gone (a worker
  # that died), which is what the stage still shows, or carry a coalesced request that has not been turned
  # into a job yet. Any of them means the report is not settled, so none of them may look idle. Owning the
  # package deliberately does not count: an spdx report claims it too and leaves the report alone.
  my $reindexing
    = $stage
    || defined $pkg->{reindex_requested}
    || $c->minion->jobs({states => ['inactive', 'active'], notes => ["pkg_$id"], tasks => \@REBUILD_TASKS})->total
    ? 1
    : 0;

  return {
    checksum      => $pkg->{checksum},
    reindexing    => $reindexing ? true          : false,
    rebuild_stage => $reindexing ? ($stage // 1) : undef,
    spdx          => $c->spdx_state($pkg)
  };
}

# Where the package stands with its SPDX report, for the download button on the report page. Reports are
# generated on demand, so the button has to be able to say "there is one", "one is on its way", "the last
# attempt failed" and "ask for one" - and it polls, so this has to stay cheap: a stat, and a queue lookup
# only in the uncommon case that there is no report to hand out.
#
# Only the newest job for the package is consulted. Looking for a failed one instead would leave a single
# bad attempt stuck to the row for as long as the job table keeps it, long after a later attempt succeeded
# and the report was collected.
sub _spdx_state ($c, $pkg) {
  my $id = $pkg->{id};
  return {state => 'unavailable'} if $pkg->{obsolete} || !$pkg->{indexed};

  my $pkgs = $c->packages;
  if ($pkgs->has_spdx_report($id)) {
    my $size = $pkgs->spdx_report_size($id);
    return {state => 'ready', size => defined $size ? humanize_bytes($size) : undef};
  }

  my $job = $c->minion->jobs({tasks => ['spdx_report'], notes => ["pkg_$id"]})->next;
  return {state => 'none'} unless $job;
  return {state => 'building'} if $job->{state} eq 'inactive' || $job->{state} eq 'active';
  return {state => 'failed'}   if $job->{state} eq 'failed';
  return {state => 'none'};
}

sub _report_details ($c, $pkg, $report) {
  my $config       = $c->app->config;
  my $max          = $config->{min_files_short_report};
  my $expand_limit = $config->{max_expanded_files};

  my %linked;
  $linked{$_->{id}} = 1 for @{$report->{missed_files} // []};
  for my $bucket (values %{$report->{risks} // {}}) {
    for my $lic (values %$bucket) {
      my $count = 0;
      for my $file (@{$lic->{files} // []}) {
        $linked{$file->[0]} = 1;
        last if ++$count > $max;
      }
    }
  }

  my $num_expanded  = 0;
  my $hidden_inline = 0;
  my @files;
  for my $file (@{$report->{files} // []}) {
    next unless $linked{$file->{id}};
    my $wants_expand = $file->{expand}                                ? 1 : 0;
    my $expand       = $wants_expand && $num_expanded < $expand_limit ? 1 : 0;
    $num_expanded++  if $expand;
    $hidden_inline++ if $wants_expand && !$expand;
    push @files,
      {
      id       => $file->{id},
      path     => $file->{path},
      expand   => $expand ? \1 : \0,
      file_url => $c->url_for('file_view', id => $pkg->{id}, file => $file->{path})->to_string
      };
  }

  # _chart_data() mutates its input hash, so pass a shallow copy
  my %chart_copy = %{$report->{chart} // {}};
  my $chart      = keys(%chart_copy) ? $c->helpers->chart_data(\%chart_copy) : undef;

  # New files and licenses (vs the closest previous review) from the structured
  # diff report, so the UI can badge them "new". Files are matched by name, not
  # id: matched_files rows (and their ids) are deleted and recreated on every
  # reindex, so a stored id cannot be joined against the live report, but the
  # filename is stable. Degrades to no flags when the column is absent (report
  # not reindexed yet) or unparseable.
  my (%new_unresolved, %new_license);
  if (my $diff = $pkg->{diff_report}) {
    my $decoded = eval { from_json($diff) } // {};
    $new_unresolved{$_->{name}} = 1 for @{$decoded->{new_unresolved} // []};
    $new_license{$_} = 1 for @{$decoded->{new_licenses} // []};
  }

  my $risks = $report->{risks} // {};
  my %risk_buckets;
  for my $risk (keys %$risks) {
    my @licenses;
    my $bucket = $risks->{$risk};
    for my $lic (sort keys %$bucket) {
      my $matches = $bucket->{$lic};
      my $display = $matches->{spdx} || $matches->{name};
      push @licenses, {
        name      => $matches->{name},
        spdx      => $matches->{spdx},
        name_html => spdx_link($display),
        flags     => $matches->{flags} // [],
        files     => $matches->{files},

        # What the external datasets (OSADL obligation checklists, SPDX classification flags) say about
        # each SPDX identifier named in this entry, verbatim and per constituent for expressions like
        # "MIT OR BSD-3-Clause". Empty when no source knows any of them, so the frontend simply omits
        # the panel. Derived per request from the bundled datasets, not persisted.
        classification => license_classification($display),
        ($new_license{$matches->{name}} ? (new => \1) : ())
      };
    }
    $risk_buckets{$risk} = \@licenses;
  }

  my @missed;
  for my $f (@{$report->{missed_files} // []}) {
    my %copy = %$f;
    $copy{license_html} = spdx_link($f->{spdx} || $f->{license});
    $copy{new}          = \1 if $new_unresolved{$f->{name}};
    push @missed, \%copy;
  }

  # Vendored components: render licenses as clickable SPDX links (like every other license in the
  # report) and link the name to the component's metadata file in the file browser
  my @components;
  for my $comp (@{$report->{components} // []}) {
    push @components, {
      type         => $comp->{type},
      name         => $comp->{name},
      version      => $comp->{version},
      purl         => $comp->{purl},
      license      => $comp->{license},
      license_html => (length($comp->{license} // '') ? spdx_link($comp->{license}) : undef),
      file_url     => (
        length($comp->{source} // '')
        ? $c->url_for('file_view', id => $pkg->{id}, file => $comp->{source})->to_string
        : undef
      ),

      # "Find every package that ships this component" (security/vulnerability triage), by exact purl
      search_url =>
        (length($comp->{purl} // '') ? $c->url_for('search')->query(component => $comp->{purl})->to_string : undef)
    };
  }

  return {
    package               => {id => $pkg->{id}, name => $pkg->{name}, unresolved_matches => $pkg->{unresolved_matches}},
    chart                 => $chart,
    license_compatibility => $report->{license_compatibility} // {licenses => [], matrix => {}, proximity => {}},

    # SPDX ids new since the closest previous review, so the compatibility matrix can mark a flagged pair
    # "new" (a freshly-introduced incompatibility) - the same novelty signal the file badges use above.
    new_license_ids        => [sort keys %{new_license_ids($pkg->{diff_report})}],
    missed_files           => \@missed,
    risks                  => \%risk_buckets,
    max_files_per_license  => $max,
    max_expanded_files     => $expand_limit,
    hidden_inline_previews => $hidden_inline,
    matching_globs         => $report->{matching_globs} // [],
    files                  => \@files,
    emails                 => $report->{emails} // [],
    urls                   => $report->{urls}   // [],
    components             => \@components
  };
}

sub _current_user ($c) { $c->stash->{'cavil.api.user'} // $c->session('user') }

sub _current_user_has_role ($c, @roles) {
  return undef unless my $user = $c->helpers->current_user;
  return $c->users->has_role($user, @roles);
}

# Capability-based check: true when the current user holds any role that grants the capability. This is
# the check controllers and templates should use, so authorization is expressed as "can curate" rather
# than "is admin". Route gates use roles_with_capability() with the same map (see Cavil::Role).
sub _current_user_can ($c, $capability) {
  return undef unless my $user = $c->helpers->current_user;
  return $c->users->has_role($user, @{roles_with_capability($capability)});
}

sub _current_user_has_write_access ($c) { $c->stash->{'cavil.api.write_access'} ? 1 : 0 }

sub _current_user_scopes ($c) { $c->stash->{'cavil.api.scopes'} // [] }

sub _current_user_roles ($c) {
  return [] unless my $user = $c->helpers->current_user;
  return $c->users->roles($user);
}

sub _json_validation_error ($c) {
  my $failed = join ', ', @{$c->validation->failed};
  $c->render(json => {error => "Invalid request parameters ($failed)"}, status => 400);
}

sub _mcp_report ($c, $id, $opts = {}) {
  return undef unless my $report = $c->reports->sanitized_dig_report($id);
  my $summary = $c->helpers->package_summary($id);
  my $pkg     = $c->packages->find($id);

  # 0 = omit the section entirely; otherwise cap the (already occurrence-ordered) lists.
  my $url_limit   = $opts->{url_limit}   // 10;
  my $email_limit = $opts->{email_limit} // 10;

  return $c->render_to_string(
    'mcp/report',
    format      => 'txt',
    report      => $report,
    package     => $pkg,
    summary     => $summary,
    unmatched   => _unmatched_rollup($c, $id),
    url_limit   => $url_limit,
    email_limit => $email_limit
  );
}

sub _package_summary ($c, $id) {
  my $pkgs = $c->packages;
  return undef unless my $pkg = $pkgs->find($id);

  my $spec = $c->reports->specfile_report($id);
  my $type = first { length $_ } map { $_->{type} } @{$spec->{sub} // []};

  my $main               = $spec->{main};
  my $main_license       = $main->{license};
  my $normalized_license = lic($main_license)->to_string;
  my $package_license    = $normalized_license || $main_license;

  my $version = $main->{version};
  my $summary = $main->{summary};
  my $group   = $main->{group};
  my $url     = $main->{url};

  my $report = $pkg->{checksum} // '';
  my ($risk, $shortname) = $report =~ /-(\d+):(\w+)$/;

  $risk = 9 if ($pkg->{unresolved_matches} || 0) > 0;

  my $requests = $pkgs->requests_for($id);

  # Collapse the raw codestream names into their curated product name (falling back to the codestream name
  # when unannotated) and dedupe, so a package spread across a dozen codestreams of one deliverable shows a
  # single product name instead of a dozen cryptic paths
  my %seen;
  my $products
    = [sort grep { !$seen{$_}++ } map { $_->{product} // $_->{name} } @{$c->products->for_package_products($id)}];

  # Whether the Reindex button has anything to offer changes without the page being reloaded: a rebuild
  # (this reviewer's or somebody else's) bumps the package past every pattern that made the button light
  # up, and a pattern created while the page is open makes it light up again
  my $state = $c->reindex_state($pkg);

  my $config = $c->app->config;

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

  my (%docs, %lics, @package_files, @legal_review_notices);
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
    push @legal_review_notices, @{$sub->{'legal_review_notices'} // []};
  }

  return {
    actions              => $actions,
    copied_files         => {'%doc' => [sort keys %docs], '%license' => [sort keys %lics]},
    created              => $pkg->{created_epoch},
    embargoed            => \!!$pkg->{embargoed},
    ai_assisted          => \!!$pkg->{ai_assisted},
    errors               => $spec->{errors} // [],
    external_link        => $pkg->{external_link},
    external_link_data   => external_link_data($pkg->{external_link}, $config->{external_link_sources}),
    id                   => $pkg->{id},
    legal_review_notices => \@legal_review_notices,
    notice               => $pkg->{notice},
    package_checksum     => $pkg->{checkout_dir},
    package_files        => \@package_files,
    package_group        => $group,
    package_license      => {name => $package_license, spdx => \!!$normalized_license},
    package_name         => $pkg->{name},
    package_priority     => $pkg->{priority},
    package_risk         => $risk,
    package_shortname    => $shortname,
    package_summary      => $summary,
    package_type         => $type,
    package_url          => $url,
    package_version      => $version,
    products             => $products,
    reindexing           => $state->{reindexing},
    requests             => $requests,
    requests_data        => [map { external_link_data($_, $config->{external_link_sources}) } @$requests],
    result               => $pkg->{result},
    reviewed             => $pkg->{reviewed_epoch},
    reviewing_user       => $pkg->{login},
    should_reindex       => \!!$c->patterns->has_new_patterns($pkg->{name}, $pkg->{indexed}),
    spdx                 => $state->{spdx},
    state                => $pkg->{state},
    unpacked_files       => $pkg->{unpacked_files},
    unpacked_size        => humanize_bytes($pkg->{unpacked_size} // 0),
    warnings             => $spec->{warnings} // []
  };
}

# A compact, impact-ranked rollup of this package's unresolved snippets for the report: the full
# per-snippet previews are enormous on large packages, so we surface only the top few (one pattern or
# glob clears many identical occurrences) plus a total, and point at cavil_search_snippets for the rest.
sub _unmatched_rollup ($c, $id, $top = 10) {
  my $result = $c->snippets->snippet_search(
    {resolution => 'unresolved', group => 'text', order => 'occurrences', package_id => $id, limit => $top});

  # Same rule as snippet_search / the missed_snippets partition: exclude classifier-rejected snippets
  # (classified AND NOT license) so the total matches what the tool lists and what the report shows.
  my $total = $c->pg->db->query(
    'SELECT count(DISTINCT fs.snippet) FROM file_snippets fs JOIN snippets s ON s.id = fs.snippet
      WHERE fs.package = ? AND fs.generation = 0 AND fs.resolution IS NULL
        AND (s.license OR NOT s.classified)', $id
  )->array->[0];
  return {rows => $result->{snippets}, total => $total};
}

1;
