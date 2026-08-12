# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package Cavil::Model::Reports;
use Mojo::Base -base, -signatures;

use Encode qw(from_to decode);
use Mojo::File 'path';
use Mojo::JSON qw(from_json);
use Cavil::PatternEngine;
use Cavil::Checkout;
use Cavil::Licenses   qw(lic);
use Cavil::ReportUtil qw(estimated_risk license_compatibility license_document_candidates unexplained_lines);
use Cavil::Util       qw(lines_context to_json_fast);

has [qw(acceptable_packages acceptable_risk checkout_dir max_expanded_files pg snippet_fold)];

# we need a HUGE number because Spooky uses unsigned integers
use constant PATTERN_DELTA => 10000000000;

sub cached_dig_report {
  my ($self, $id) = @_;
  return undef unless my $hash = $self->pg->db->select('bot_reports', 'ldig_report', {package => $id})->hash;
  return $hash->{ldig_report};
}

# The generation selects which report to build from: 0 is the live one every reader wants, a non-zero
# value is a reindex building alongside it (only Cavil::Task::Analyze passes one, to build the report it
# is about to promote)
sub dig_report {
  my ($self, $id, $limit_to_file, $generation) = @_;
  $generation //= 0;

  my $db            = $self->pg->db;
  my $pkg           = $db->select('bot_packages',  '*',            {id       => $id})->hash;
  my $ignored       = $db->select('ignored_lines', ['id', 'hash'], {packname => $pkg->{name}});
  my %ignored_lines = map { $_->{hash} => $_->{id} } $ignored->hashes->each;

  my $report = $self->_dig_report($db, {}, $pkg, \%ignored_lines, $limit_to_file, $generation);

  $report->{license_compatibility} = license_compatibility($report);

  delete $report->{matches};
  delete $report->{file_confidence};
  return $report;
}

# Annotations share the report transaction so derived metadata cannot drift.
sub annotations ($self, $id) {
  return undef unless my $hash = $self->pg->db->select('bot_reports', 'annotations', {package => $id})->hash;
  return undef unless defined $hash->{annotations};
  return from_json($hash->{annotations});
}

sub build_annotations ($self, $id, $dig_report) {
  return {legal_documents => $self->_legal_documents($id, $dig_report)};
}

# Keep document kind in the row shape so adding detectors needs no schema change.
sub _legal_documents ($self, $id, $dig_report) {
  my $found  = license_document_candidates($dig_report);
  my $result = {documents => [], dropped => $found->{dropped}};
  my $docs   = $found->{documents};
  return $result unless @$docs;

  my $db = $self->pg->db;
  return $result unless my $pkg = $db->select('bot_packages', ['name', 'checkout_dir'], {id => $id})->hash;

  # Every candidate's licensed line spans in one query. The question is whether Cavil recognised the text
  # at all, so catch_all markers count - excluding them (as the cover guard does, where the question is
  # whether a license may be asserted) leaves a NOTICE of matched attribution boilerplate reading as
  # almost entirely unexplained. Keyword patterns stay out: they are trigger words, and a stray
  # "copyright notice" would mark a line of novel terms as explained. The file ids pin one generation.
  my %spans;
  my $matches = $db->query(
    "SELECT pm.file, pm.sline, pm.eline FROM pattern_matches pm JOIN license_patterns lp ON lp.id = pm.pattern
      WHERE pm.file = ANY(?) AND pm.ignored = false AND lp.license <> ''", [map { $_->{id} } @$docs]
  );
  push @{$spans{$_->[0]}}, [$_->[1], $_->[2]] for $matches->arrays->each;

  # Blankness and line numbering do not require decoding.
  my $base = path($self->checkout_dir, $pkg->{name}, $pkg->{checkout_dir}, '.unpacked');
  for my $doc (@$docs) {
    my $file = $base->child($doc->{path});
    next unless -r $file;
    my @lines = split /\n/, $file->slurp, -1;
    my $total = grep {/\S/} @lines;
    next unless $total;
    push @{$result->{documents}},
      {
      kind        => 'license',
      path        => $doc->{path},
      lines       => $total,
      unexplained => unexplained_lines($spans{$doc->{id}}, \@lines)
      };
  }

  return $result;
}

sub risk_is_acceptable {
  my ($self, $shortname) = @_;
  return undef unless $shortname =~ /^(.+)-(\d):[^:]+$/;
  return undef if $2 > $self->acceptable_risk;
  return $2;
}

sub sanitized_dig_report {
  my ($self, $id) = @_;
  return undef unless my $report = $self->cached_dig_report($id);

  $report = from_json($report);
  _sanitize_report($report);

  return $report;
}

sub shortname ($self, $chksum) {
  my $db = $self->pg->db;
  if (my $lentry = $db->select('report_checksums', 'shortname', {checksum => $chksum})->hash) {
    return $lentry->{shortname};
  }

  my $chars = ['a' .. 'z', 'A' .. 'Z', '0' .. '9'];
  for (1 .. 100) {
    my $shortname = join('', map { $chars->[rand @$chars] } 1 .. 6);
    my $inserted  = $db->query(
      'insert into report_checksums (checksum, shortname)
       values (?,?) on conflict do nothing returning shortname', $chksum, $shortname
    )->hash;
    return $inserted->{shortname} if $inserted;

    # Resolve races on checksum separately from random-name collisions.
    if (my $existing = $db->select('report_checksums', 'shortname', {checksum => $chksum})->hash) {
      return $existing->{shortname};
    }
  }
  die "Could not allocate a shortname for checksum $chksum after 100 attempts";
}

sub source_for {
  my ($self, $fileid, $start, $end) = @_;

  # The file id comes straight from a request, so pin it to the live report: a build running alongside
  # has its own matched_files rows and must never be rendered
  my $db   = $self->pg->db;
  my $file = $db->select('matched_files', '*', {id => $fileid, generation => 0})->hash;
  return undef unless $file;

  my $pkg = $db->select('bot_packages', '*', {id => $file->{package}})->hash;

  my $report = $self->dig_report($file->{package}, $fileid);
  my $lines  = $report->{lines}{$fileid};

  # The report lives in the database but its source lines are read from the checkout on every request, and
  # a re-unpack tears that tree down and rebuilds it. Rather than answering with a silently empty file,
  # say the source is temporarily unavailable and let the caller show that instead.
  my $fn = path($self->checkout_dir, $pkg->{name}, $pkg->{checkout_dir}, '.unpacked', $file->{filename});
  return {lines => [], name => $pkg->{name}, filename => $file->{filename}, unavailable => 1} unless -e $fn;

  if ($start > 0 && $end > 0) {
    my %pid_info;    # cache
    my %needed;
    my %folded_meta;
    for my $line (@$lines) {
      my ($nr, $pid, $text) = @$line;
      $needed{$nr} = 0;
      $needed{$nr} = $pid->{pid} if $pid->{pid};

      # Preserve the correction handle without repainting a fold as unresolved.
      if ($pid->{folded}) {
        $folded_meta{$nr} = {snippet => $pid->{snippet}, hash => $pid->{hash}};
      }
      elsif ($pid->{snippet}) {
        $needed{$nr} = PATTERN_DELTA + $pid->{snippet};
      }
    }
    my $nr = $start;
    while ($nr <= $end) {

      $needed{$nr++} = PATTERN_DELTA;
    }
    for my $c (1 .. 3) {
      $needed{$start - $c} //= 0 if $start > $c;
      $needed{$end + $c}   //= 0;
    }

    $lines = $self->_lines($db, \%pid_info, $fn, \%needed, \%folded_meta);
  }

  return {lines => $lines, name => $pkg->{name}, filename => $file->{filename}};
}

sub specfile_report {
  my ($self, $id) = @_;

  my $db   = $self->pg->db;
  my $hash = $db->select('bot_reports', '*', {package => $id})->hash;

  unless ($hash) {
    return undef unless defined(my $specfile = $self->build_specfile_report($id));

    return {} unless %$specfile;

    my $report = {package => $id, specfile_report => to_json_fast($specfile)};
    $hash = $db->insert('bot_reports', $report, {returning => '*'})->hash;
  }

  return from_json($hash->{specfile_report});
}

# Read the spec file report straight from the checkout, ignoring the cached copy. A rebuild that follows a
# re-unpack has entirely new sources, so the cache describes the previous ones - Cavil::Task::Analyze takes
# a fresh report from here and stores it with the promote, not before, so the spec file license and the
# file report always change over together. Returns undef for a package that is gone and an empty report
# while the sources are not unpacked.
sub build_specfile_report ($self, $id) {
  return undef unless my $pkg = $self->pg->db->select('bot_packages', '*', {id => $id})->hash;

  my $checkout = Cavil::Checkout->new(path($self->checkout_dir, $pkg->{name}, $pkg->{checkout_dir}));
  return {} unless $checkout->is_unpacked;

  return $checkout->specfile_report({upload => (($pkg->{external_link} // '') eq 'upload')});
}

sub summary ($self, $id) {
  my %summary  = (id => $id);
  my $specfile = $self->specfile_report($id);
  $summary{specfile} = lic($specfile->{main}{license})->canonicalize->to_string || 'Unknown';

  # Analyze has already cached this expensive match walk when available.
  my $cached = $self->cached_dig_report($id);
  my $report = $cached ? from_json($cached) : $self->dig_report($id);

  my $min_risklevel = 1;

  $min_risklevel = 2 if $report->{risks}{3};
  $summary{licenses} = {};
  for my $license (sort { $a cmp $b } keys %{$report->{licenses}}) {
    next if $report->{licenses}{$license}{risk} < $min_risklevel;
    my $text = "$license";
    for my $flag (@{$report->{licenses}{$license}{flags}}) {
      $text .= ":$flag";
    }
    $summary{licenses}{$text} = $report->{licenses}{$license}{risk};
  }

  # Renderer expansion limits must not make content-equivalent summaries differ.
  my $files = {};
  for my $file_id (keys %{$report->{missed_snippets}}) {
    my $filename = $report->{files}{$file_id};
    for my $snip_row (@{$report->{missed_snippets}{$file_id}}) {
      push @{$files->{$filename}}, $snip_row->[3];
    }
  }
  $summary{missed_snippets} = $files;

  return \%summary;
}

sub _check_ignores {
  my ($self, $report, $file, $ignored_lines, $matches_to_ignore, $snippets_to_remove) = @_;

  my $lastline = '';
  my @clines   = @{$report->{lines}{$file}};
  my $line     = shift @clines;
  my $freport  = $report->{matches}{$file};

  while ($line || @clines) {
    if ($line->[1]{risk} == 9) {
      my $hex;
      my @marks;
      push(@marks, $line);
      if ($line->[1]->{snippet}) {
        $hex = $report->{snippets}{$file}{$line->[1]->{snippet}};
        if (defined $ignored_lines->{$hex}) {
          $snippets_to_remove->{$line->[1]->{snippet}} = 1;
        }
        while ($line = shift @clines) {
          $lastline = $line->[2];
          last if $line->[1]{risk} != 9;
          push(@marks, $line);
        }
      }
      else {
        my $ctx = Cavil::PatternEngine::init_hash(0, 0);
        $ctx->add("$lastline\n");
        $ctx->add("$line->[2]\n");
        while ($line = shift @clines) {
          $lastline = $line->[2];
          $ctx->add("$lastline\n");
          last if $line->[1]{risk} != 9;
          push(@marks, $line);
        }
        $hex = $ctx->hex;
      }
      if (defined $ignored_lines->{$hex}) {
        for my $m (@marks) {
          $m->[1]->{risk} = 0;
          next unless $freport->{$m->[0]};
          $matches_to_ignore->{$freport->{$m->[0]}} = $ignored_lines->{$hex};
        }
      }
      else {
        for my $m (@marks) {
          my %deepcopy = %{$m->[1]};
          $m->[1] = \%deepcopy;
          $m->[1]{hash} = $hex;
        }
      }
    }
    $lastline = $line->[2];
    $line     = shift @clines;
  }
}

sub _add_to_snippet_hash {
  my ($file_snippets, $snip_row) = @_;

  $file_snippets->{$snip_row->{file}} ||= [];
  push(
    @{$file_snippets->{$snip_row->{file}}},
    [
      $snip_row->{sline}, $snip_row->{eline},      $snip_row->{id},
      $snip_row->{hash},  $snip_row->{likelyness}, $snip_row->{like_pattern}
    ]
  );
}

sub _dig_report {
  my ($self, $db, $pid_info, $pkg, $ignored_lines, $limit_to_file, $generation) = @_;
  $generation //= 0;

  my $ignored_file_res = Cavil::Util::load_ignored_files($db);
  my $report           = {};
  my $query            = {package => $pkg->{id}, generation => $generation};
  if ($limit_to_file) {
    $query->{id} = $limit_to_file;
  }

  my @ignore_globs  = keys %$ignored_file_res;
  my $matching_glob = sub ($filename) {
    for my $ifname (@ignore_globs) { return $ifname if $filename =~ $ignored_file_res->{$ifname} }
    return undef;
  };

  # Avoid per-row hashes for packages with tens of thousands of files.
  my %globs_matched;
  for my $file ($db->select('matched_files', [qw(id filename)], $query)->arrays->each) {
    my ($id, $filename) = @$file;
    if (my $glob = $matching_glob->($filename)) { $globs_matched{$glob} = 1 }
    else                                        { $report->{files}{$id} = $filename }
  }

  # The file join already pins matches to its generation.
  my $query_string = 'select distinct filename from
                      matched_files mf join pattern_matches pm
                      on pm.file=mf.id where mf.package=? and mf.generation=?
                      and pm.ignored=true';

  my $filenames;
  if ($limit_to_file) {
    $filenames = $db->query("$query_string and mf.id=?", $pkg->{id}, $generation, $limit_to_file);
  }
  else {
    $filenames = $db->query($query_string, $pkg->{id}, $generation);
  }

  for my $file ($filenames->hashes->each) {
    if (my $glob = $matching_glob->($file->{filename})) { $globs_matched{$glob} = 1 }
  }
  $filenames->finish;

  $report->{matching_globs} = [keys %globs_matched];

  $query = {package => $pkg->{id}, ignored => 0, generation => $generation};
  if ($limit_to_file) {
    $query->{file} = $limit_to_file;
  }
  my $matches = $db->select('pattern_matches', [qw(id file pattern sline eline)], $query);

  $query = {'file_snippets.package' => $pkg->{id}, 'file_snippets.generation' => $generation};
  if ($limit_to_file) {
    $query->{file} = $limit_to_file;
  }
  my $snippets = $db->select(
    ['snippets', ['file_snippets', snippet => 'id']],
    [
      'snippets.id', 'snippets.hash', 'snippets.likelyness', 'snippets.like_pattern',
      'file',        'sline',         'eline',               'classified',
      'license',     'resolution'
    ],
    $query
  );

  # Stable content keys make deduplication reproducible across packages.
  my @snip_rows = sort {
         ($report->{files}{$a->{file}} // '') cmp ($report->{files}{$b->{file}} // '')
      || $a->{id}                             <=> $b->{id}
      || $a->{sline}                          <=> $b->{sline}
  } $snippets->hashes->each;

  my %file_snippets_to_show;
  my %file_snippets_to_fold;
  my %snippets_shown;

  # Snippet resolution never suppresses independent licensed matches.
  for my $snip_row (@snip_rows) {
    my $resolution = $snip_row->{resolution} // '';

    if (!defined $report->{files}{$snip_row->{file}} || (!$snip_row->{license} && $snip_row->{classified})) {
      next;
    }

    elsif ($resolution eq 'fold') {
      _add_to_snippet_hash(\%file_snippets_to_fold, $snip_row);
    }
    elsif ($resolution eq 'clear' || $resolution eq 'overlap' || $resolution eq 'covered') {
      $report->{cleared}{$snip_row->{file}} = 1;
    }

    elsif ($snippets_shown{$snip_row->{id}}) {
      next;
    }
    else {
      $snippets_shown{$snip_row->{id}} = 1;
      _add_to_snippet_hash(\%file_snippets_to_show, $snip_row);
    }
  }

  $report->{missed_snippets} = \%file_snippets_to_show;

  my $expanded_limit = $self->max_expanded_files;
  my $num_expanded   = 0;

  my %matches_to_ignore;
  my %snippets_to_remove;

  for my $file (sort { $report->{files}{$a} cmp $report->{files}{$b} } keys %file_snippets_to_show) {
    last if $num_expanded++ > $expanded_limit;

    $report->{expanded}{$file} = 1;
    for my $snip_row (@{$file_snippets_to_show{$file}}) {
      my ($sline, $eline, $id, $hash, $dummy1, $dummy2) = @$snip_row;
      for (my $i = $sline - 3; $i <= $eline + 3; $i++) {
        next if $i < 1;
        if ($i >= $sline && $i <= $eline) {
          $report->{needed_lines}{$file}{$i} = PATTERN_DELTA + $id;
          $report->{snippets}{$file}{$id}    = $hash;
        }
        else {
          $report->{needed_lines}{$file}{$i} = 0;
        }
      }
    }
  }

  $self->_register_matches($db, $report, $pid_info, $matches, \%matches_to_ignore);
  $self->_register_folds($db, $report, $pid_info, \%file_snippets_to_fold);

  $report->{flags} = [keys %{$report->{flags}}] if $report->{flags};

  for my $license (values %{$report->{licenses}}) {
    my @flags = sort keys %{$license->{flaghash}};
    $license->{flags} = [grep { $license->{flaghash}{$_} } @flags];
    delete $license->{flaghash};
  }

  for my $file (keys %{$report->{files}}) {
    next unless $report->{expanded}{$file} || $limit_to_file;
    my $fn = path($self->checkout_dir, $pkg->{name}, $pkg->{checkout_dir}, '.unpacked', $report->{files}{$file});
    $report->{lines}{$file}
      = $self->_lines($db, $pid_info, $fn, $report->{needed_lines}{$file}, $report->{folded_meta}{$file});
    $self->_check_ignores($report, $file, $ignored_lines, \%matches_to_ignore, \%snippets_to_remove);
  }

  # in case ignored lines found unignored matches (i.e. first load), update them
  # and restart the report
  for my $mig (keys %matches_to_ignore) {
    $db->update('pattern_matches', {ignored => 1, ignored_line => $matches_to_ignore{$mig}}, {id => $mig});
  }

  if (%matches_to_ignore) {
    return $self->_dig_report($db, $pid_info, $pkg, $ignored_lines, $limit_to_file, $generation);
  }

  # we read the lines and that's enough
  delete $report->{needed_lines};
  delete $report->{folded_meta};

  if ($limit_to_file) {
    return $report;
  }

  # Scoped to the generation being built, or rendering the live report in the web process would delete
  # rows out from under a reindex that is running alongside it
  if (%snippets_to_remove) {
    for my $id (keys %snippets_to_remove) {
      $db->delete('file_snippets', {snippet => $id, package => $pkg->{id}, generation => $generation});
    }
    return $self->_dig_report($db, $pid_info, $pkg, $ignored_lines, undef, $generation);
  }

  my %missed_files;

  for my $file (keys %{$report->{missed_snippets}}) {
    my $max_risk = 0;
    my ($license_of_max, $spdx_of_max, $match_of_max);
    for my $snip_row (@{$report->{missed_snippets}{$file}}) {
      my ($dummy1, $dummy2, $dummy3, $dummy4, $match, $pattern) = @$snip_row;
      my $pinfo     = $self->_info_for_pattern($db, $pid_info, $pattern);
      my $stat_risk = estimated_risk($pinfo->{risk}, $match);
      if ($max_risk < $stat_risk || (($max_risk == $stat_risk) && $match_of_max < $match)) {
        $max_risk       = $stat_risk;
        $match_of_max   = $match;
        $license_of_max = $pinfo->{name};
        $spdx_of_max    = $pinfo->{spdx};
      }
    }
    $missed_files{$file} = [$max_risk, $match_of_max, $license_of_max, $spdx_of_max];
  }
  $report->{missed_files} = \%missed_files;

  my $emails = $db->select('emails', '*', {package => $pkg->{id}, generation => $generation});
  for my $email ($emails->hashes->each) {
    my $key = $email->{email};
    if ($email->{name}) {
      $key = "$email->{name} <$email->{email}>";
    }
    $report->{emails}{$key} = $email->{hits};
  }
  my $urls = $db->select('urls', '*', {package => $pkg->{id}, generation => $generation});
  for my $url ($urls->hashes->each) {
    $report->{urls}{$url->{url}} = $url->{hits};
  }

  my $components = $db->select(
    'package_components', '*',
    {package  => $pkg->{id}, generation => $generation},
    {order_by => ['name', 'version']}
  );
  $report->{components} = [
    map {
      {
        type    => $_->{type},
        name    => $_->{name},
        version => $_->{version},
        license => $_->{license},
        purl    => $_->{purl},
        source  => $_->{source}
      }
    } $components->hashes->each
  ];

  return $report;
}

sub _info_for_pattern {
  my ($self, $db, $pid_info, $pid) = @_;
  return {risk => 0} unless $pid;

  if (!defined $pid_info->{$pid}) {
    my $pattern = $self->_load_pattern_from_cache($db, $pid);
    $pid_info->{$pid} = {risk => $pattern->{risk}, name => $pattern->{license}, spdx => $pattern->{spdx}, pid => $pid};
  }
  return $pid_info->{$pid};
}

sub _lines {
  my ($self, $db, $pid_info, $fn, $needed_lines, $folded_meta) = @_;

  my @lines;
  my %snippet_info;

  # fill small gaps
  my $lastline;
  for my $line (sort { $a <=> $b } keys %$needed_lines) {
    if ($lastline && $line > $lastline + 1 && $line - $lastline < 6) {
      for my $nl ($lastline + 1 .. $line - 1) {
        $needed_lines->{$nl} = 0;
      }
    }
    $lastline = $line;
  }
  for my $row (@{Cavil::PatternEngine::read_lines($fn, $needed_lines)}) {
    my ($index, $pid, $line) = @$row;

    # Sanitize line - first try UTF-8 strict and then LATIN1
    eval { $line = decode 'UTF-8', $line, Encode::FB_CROAK; };
    if ($@) {
      from_to($line, 'ISO-LATIN-1', 'UTF-8', Encode::FB_DEFAULT);
      $line = decode 'UTF-8', $line, Encode::FB_DEFAULT;
    }
    if ($pid >= PATTERN_DELTA) {
      my $sid  = $pid - PATTERN_DELTA;
      my $info = $snippet_info{$sid} ||= $db->select('snippets', ['hash', 'like_pattern'], {id => $sid})->hash || {};
      my $line_info = {risk => 9, snippet => $sid, name => 'Snippet of missing keywords'};
      $line_info->{hash} = $info->{hash}           if $info->{hash};
      $line_info->{pids} = [$info->{like_pattern}] if $info->{like_pattern};
      push(@lines, [$index, $line_info, $line]);
    }
    else {
      # need to store a deep copy to modify it later adding context
      my %pinfo = %{$self->_info_for_pattern($db, $pid_info, $pid)};

      # A folded line looks like a pattern match but is derived from a snippet; carry the snippet
      # handle (id + hash) and the "folded" tag so the source view can mark it and offer a correction.
      if (my $meta = $folded_meta->{$index}) {
        @pinfo{qw(folded snippet hash)} = (1, $meta->{snippet}, $meta->{hash});
      }
      push(@lines, [$index, \%pinfo, $line]);
    }
  }

  return \@lines;
}

# Populate the pattern cache for a batch of pattern ids with one query, so the per-match lookups in
# _register_matches all hit instead of firing a single-row SELECT each. Only the license identity, risk
# and flag columns are ever read - never the (large) pattern text: this cache lives on the reports
# helper, a state singleton, so in a long-running web process it would otherwise accumulate the full
# pattern text of every pattern any report touches (tens of MB across the corpus, growing with it) for no
# benefit. Ids already cached are skipped, so a warm cache narrows the batch to just the new ids.
sub _prime_pattern_cache {
  my ($self, $db, $pids) = @_;

  my $cache = $self->{license_cache} //= {};
  my %needed;
  $needed{$_} = 1 for grep { $_ && !$cache->{"pattern-$_"} } @$pids;
  return unless %needed;

  my $found = $db->query(
    'SELECT id, license, spdx, risk, patent, trademark, export_restricted, cla, eula
       FROM license_patterns WHERE id = ANY(?)', [keys %needed]
  )->hashes;
  for my $pattern ($found->each) {
    my $id = delete $pattern->{id};
    $cache->{"pattern-$id"} = $pattern;
  }
}

sub _load_pattern_from_cache {
  my ($self, $db, $pid) = @_;
  $self->_prime_pattern_cache($db, [$pid]) unless $self->{license_cache}{"pattern-$pid"};
  return $self->{license_cache}{"pattern-$pid"};
}

# Record a license on the report (licenses + risks lists + flags). Shared by the real-match and the
# folded-snippet registration below so both contribute a license identically. $source ('match' | 'fold')
# records how confidently this (file, license) is established - a real pattern match outranks a folded
# snippet - so proximity can prefer the strongest evidence when it picks a pair's representative files
# (see file_confidence / _file_license_ids). One hash write per registration (per match/fold, not per line).
sub _register_license {
  my ($self, $report, $pid_info, $pattern, $pid, $file, $source) = @_;

  $report->{licenses}{$pattern->{license}}
    ||= {name => $pattern->{license}, spdx => $pattern->{spdx}, risk => $pattern->{risk}};
  $report->{licenses}{$pattern->{license}}{flaghash}{$_} ||= $pattern->{$_}
    for qw(patent trademark export_restricted cla eula);

  my $rl = $report->{risks}{$pattern->{risk}};
  push(@{$rl->{$pattern->{license}}{$pid}}, $file);
  $report->{risks}{$pattern->{risk}} = $rl;

  my $rank = ($source // 'match') eq 'fold' ? 2 : 3;
  my $seen = $report->{file_confidence}{$file}{$pattern->{license}};
  $report->{file_confidence}{$file}{$pattern->{license}} = $rank if !defined $seen || $rank > $seen;

  $pid_info->{$pid} = {risk => $pattern->{risk}, name => $pattern->{license}, pid => $pid};
}

# Register every real (non-ignored) license pattern match into the report: add its license and
# highlight its lines with the pattern id (without lowering an already-higher risk on a line). Matches
# fully inside an ignored/cleared snippet region are skipped, and matches in glob-hidden files are
# queued for ignoring.
sub _register_matches {
  my ($self, $db, $report, $pid_info, $matches, $matches_to_ignore) = @_;

  # Prime the pattern cache in one shot. Every match references a pattern, and the per-match
  # _load_pattern_from_cache below would otherwise fire one single-row SELECT per cache miss - hundreds
  # of round-trips on a large package, and the dominant cost of report generation. Bulk-load the distinct
  # ids that are not cached yet with a single ANY() query instead.
  my $rows = $matches->hashes->to_array;
  $self->_prime_pattern_cache($db, [map { $_->{pattern} } @$rows]);

  for my $match (@$rows) {
    my $pid = $match->{pattern};

    if (!defined $report->{files}{$match->{file}}) {

      # File is hidden by an ignored_files glob; there is no ignored_lines row backing this, so leave
      # the FK column NULL
      $matches_to_ignore->{$match->{id}} = undef;
      next;
    }

    # A licensed pattern match always reports its license - even when it falls inside a cleared or
    # overlap snippet region. Overlap-clear is premised on exactly this match carrying the license, so
    # suppressing it would drop the license from the file. Keyword (empty-license) matches carry no
    # license and contribute nothing here.
    my $pattern = $self->_load_pattern_from_cache($db, $pid);
    next if $pattern->{license} eq '';

    my ($file, $mid, $sline, $eline) = @{$match}{qw(file id sline eline)};
    $self->_register_license($report, $pid_info, $pattern, $pid, $file, 'match');
    my $risk = $pattern->{risk};

    # Hoist the two per-file line maps: the loop runs once per line of every match (its ±3 context lines
    # included), so re-descending these two-level hashes each iteration is the hot path on a big package.
    my $needed  = $report->{needed_lines}{$file} //= {};
    my $matched = $report->{matches}{$file}      //= {};

    for (my $i = $sline - 3; $i <= $eline + 3; $i++) {
      next if $i < 1;
      if ($i >= $sline && $i <= $eline) {
        my $opid = $needed->{$i} // 0;
        next if $opid > PATTERN_DELTA;

        # Set the line's pattern, but never lower an already-higher risk. An unmarked line (opid 0) has
        # risk 0 and can never out-rank this match, so skip the lookup for it.
        next if $opid && $risk < $self->_info_for_pattern($db, $pid_info, $opid)->{risk};
        $needed->{$i}  = $pid;
        $matched->{$i} = $mid;
      }
      else {
        # we want context but not highlight the context
        $needed->{$i} //= 0;
      }
    }
  }
  $matches->finish;
}

# Register snippets the stored resolution marked 'fold' as if they had matched their closest license's
# pattern: add the license and highlight the region exactly like a real match. The needed_lines map
# only holds one integer per line, so the originating snippet id/hash (the handle reviewers need to
# correct a wrong fold) is carried in a parallel folded_meta map.
sub _register_folds {
  my ($self, $db, $report, $pid_info, $file_snippets_to_fold) = @_;

  for my $file (keys %$file_snippets_to_fold) {
    for my $snip_row (@{$file_snippets_to_fold->{$file}}) {
      my ($sline, $eline, $sid, $hash, undef, $pid) = @$snip_row;
      next unless $pid;
      my $pattern = $self->_load_pattern_from_cache($db, $pid);
      next if $pattern->{license} eq '';

      $self->_register_license($report, $pid_info, $pattern, $pid, $file, 'fold');
      $report->{folded}{$file} = 1;

      # Do not auto-expand a file just because it folded: only files with unresolved matches are
      # expanded inline (the show loop above). A fully-folded file is still listed under its inferred
      # license and rendered on demand - opened from the report file link or in the file browser (both
      # go through the limit_to_file path, which builds its lines and the fold highlighting below).

      for (my $i = $sline - 3; $i <= $eline + 3; $i++) {
        next if $i < 1;
        if ($i >= $sline && $i <= $eline) {

          # A fold fills only lines without their own highlight: a real licensed pattern match
          # (1..PATTERN_DELTA) or an unresolved-snippet marker (> PATTERN_DELTA) already on the line is
          # authoritative, so a fold never repaints a line a curated match already explains.
          my $opid = $report->{needed_lines}{$file}{$i} // 0;
          next if $opid;
          $report->{needed_lines}{$file}{$i} = $pid;
          $report->{folded_meta}{$file}{$i}  = {snippet => $sid, hash => $hash};
        }
        else {
          $report->{needed_lines}{$file}{$i} ||= 0;
        }
      }
    }
  }
}

sub _sanitize_report {
  my $report = shift;

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
      $current->{spdx} = $license->{spdx};

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
  $report->{emails} = [map { [$_, $emails->{$_}] } sort { $emails->{$b} <=> $emails->{$a} || $a cmp $b } keys %$emails];
  my $urls = $report->{urls};
  $report->{urls} = [map { [$_, $urls->{$_}] } sort { $urls->{$b} <=> $urls->{$a} || $a cmp $b } keys %$urls];
}

1;
