# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package Cavil::Dossier;
use Mojo::Base -base, -signatures;

use Cavil::Checkout;
use Cavil::ReportUtil qw(is_catalog_entry is_license_filename is_vendored_path license_terms_kind peripheral_scope),
  qw(incompatibility_location ranked_incompatibilities unexplained_line_numbers);
use Cavil::Util qw(checkout_path document_writer extract_spdx_identifiers md5_file original_filename read_lines);
use List::Util  qw(max min);
use Mojo::File  qw(path);
use Mojo::JSON  qw(from_json);
use Mojo::Util  qw(encode);

# Every file of evidence goes through one pipeline: collected with the reasons it matters and the lines that do, merged
# so it appears once, rendered as its head and windows around those lines, and charged to the budget of the first
# section that needs it. The budgets add up to well under DOSSIER_MAX, so the final cut is a last resort.
use constant {
  DOSSIER_MAX     => 1_000_000,
  NOTES_BYTES     => 150_000,
  HEAD_LINES      => 400,
  SCAN_LINES      => 5000,
  CONTEXT         => 15,
  WINDOW_LINES    => 300,
  SPEC_MAX        => 150_000,
  CHANGES_LINES   => 40,
  BUILD_FILES_MAX => 10,
  SNIPPETS_FETCH  => 100,
  PAIRS_MAX       => 100
};

use constant CATEGORIES => [
  [license  => 'License Documents',              180_000],
  [shipping => 'Build and Shipping Evidence',    220_000],
  [snippet  => 'Unresolved Snippets',            100_000],
  [risk     => 'High Risk and Flagged Licenses', 90_000],
  [pair     => 'Incompatible License Pairs',     90_000]
];

my $MANIFEST   = qr{^(?:package\.json|pyproject\.toml|setup\.py|setup\.cfg|Cargo\.toml|go\.mod)$};
my $BUILD_FILE = qr{^(?:Makefile\.am|meson\.build|CMakeLists\.txt)$};
my $LOCKFILE   = qr{(?:^|/)(?:package-lock[^/]*\.json|[^/]*\.lock)$}i;

has 'app';

# Everything the cavil-review-note agent reads over MCP, for an AI that cannot reach Cavil
sub generate_to_file ($self, $id, $file, $stamp = undef) {
  my $app  = $self->app;
  my $pkg  = $app->packages->find($id);
  my $c    = $app->build_controller;
  my $base = checkout_path($app->config->{checkout_dir}, $pkg->{name}, $pkg->{checkout_dir}, '.unpacked');
  my $ctx  = {
    app    => $app,
    pkg    => $pkg,
    base   => $base,
    db     => $app->pg->db,
    report => $app->reports->sanitized_dig_report($id) // {},
    extras => {map { $_->[0] => [] } @{CATEGORIES()}}
  };

  my @evidence
    = (_license_documents($ctx, $c), _shipping($ctx), _snippets($ctx), _high_risk($ctx), _incompatible_pairs($ctx));
  my $text = $c->render_to_string(
    'dossier/dossier',
    format   => 'md',
    pkg      => $pkg,
    report   => $c->helpers->mcp_report($id, {url_limit => 0, email_limit => 0}) // '',
    notes    => _notes($c, $pkg),
    sections => _sections($ctx, _merge($ctx, \@evidence))
  );
  $text = substr($text, 0, DOSSIER_MAX) . "\n\n[Dossier truncated at its size limit]\n" if length $text > DOSSIER_MAX;

  my ($handle, $tmp) = document_writer($file, $stamp);
  $handle->print(encode('UTF-8', $text));
  $handle->close;
  $tmp->move_to($file);
}

sub _evidence ($path, $category, $reason, %args) {
  return {path => $path, category => $category, reasons => [[$category, $reason]], head => 0, lines => [], %args};
}

sub _file_ids ($ctx, $names) {
  return {} unless @$names;
  my $rows
    = $ctx->{db}
    ->query('SELECT filename, id FROM matched_files WHERE package = ? AND generation = 0 AND filename = ANY(?)',
    $ctx->{pkg}{id}, $names);
  return {map { $_->[0] => $_->[1] } $rows->arrays->each};
}

# The first line each license is matched on. Pattern SPDX expressions can be compound ("MIT OR GPL-2.0-only"), so
# the identifiers are looked for inside them.
sub _first_match_lines ($ctx, $file_id, $licenses) {
  return {} unless $file_id;
  my %first;
  my $rows = $ctx->{db}->query(
    'SELECT pm.sline, lp.spdx, lp.license FROM pattern_matches pm JOIN license_patterns lp ON lp.id = pm.pattern
      WHERE pm.file = ? AND pm.ignored = false ORDER BY pm.sline', $file_id
  );
  for my $row ($rows->hashes->each) {
    my %found = map { $_ => 1 } $row->{license}, @{extract_spdx_identifiers($row->{spdx})};
    $first{$_} //= $row->{sline} for grep { $found{$_} } @$licenses;
  }
  return \%first;
}

# One file per license at risk 5 or above or with a blocking flag, a license-named one if there is any
sub _high_risk ($ctx) {
  my $risks = $ctx->{report}{risks} // {};

  my @evidence;
  for my $risk (sort { $b <=> $a } keys %$risks) {
    for my $license (sort keys %{$risks->{$risk}}) {
      my $matches = $risks->{$risk}{$license};
      next unless $risk >= 5 || grep {/^(?:eula|patent|export_restricted)$/} @{$matches->{flags} // []};

      my @paths = grep { _ships($_) } map { $_->[1] } @{$matches->{files}};
      next unless defined(my $pick = (grep({ is_license_filename($_) } @paths), @paths)[0]);
      my $name  = $matches->{spdx} || $matches->{name};
      my $first = _first_match_lines($ctx, _file_ids($ctx, [$pick])->{$pick}, [grep {defined} $license, $name]);
      my $line  = min(values %$first);
      my $files = @{$matches->{files}};
      push @evidence,
        _evidence(
        $pick, 'risk',
        "risk $risk: $name, matched in $files file"
          . ($files == 1             ? ''                            : 's')
          . (is_vendored_path($pick) ? ', vendored'                  : '')
          . (defined $line           ? ", first match at line $line" : ''),
        head  => is_license_filename($pick) ? HEAD_LINES : 0,
        lines => [$line // 1]
        );
    }
  }

  return @evidence;
}

# The pairs the report lists as co-located or vendored, in its proximity order, with evidence for both licenses in
# every file and OSADL's verdict per direction, which is not always a plain No
sub _incompatible_pairs ($ctx) {
  my $compat = $ctx->{report}{license_compatibility} // {};
  my $matrix = $compat->{matrix}                     // {};

  # Only pairs that meet in one file or directory, so a pair that meets nowhere but the package root never displaces
  # one that does. Within that, one file before one directory and a mutual No first, the conflicts a lawyer looks at
  # first, otherwise in the report's order. The byte budget decides how many fit, the cap only bounds the queries.
  my @located = grep { $_->{confidence} >= 2 && $_->{tier} < 2 && incompatibility_location($_) }
    @{ranked_incompatibilities($compat)};
  my %order = map { $located[$_] => $_ } 0 .. $#located;
  my @pairs = sort {
         (incompatibility_location($b) =~ /^same file/) <=> (incompatibility_location($a) =~ /^same file/)
      || $b->{mutual}                                   <=> $a->{mutual}
      || $order{$a}                                     <=> $order{$b}
  } @located;
  push @{$ctx->{extras}{pair}}, @pairs - PAIRS_MAX . ' more pairs not considered.' if @pairs > PAIRS_MAX;
  splice @pairs, PAIRS_MAX;

  my @evidence;
  for my $pair (@pairs) {
    my ($x, $y) = @$pair{qw(a b)};
    my @verdicts = map {"$_->[0] -> $_->[1]: $matrix->{$_->[0]}{$_->[1]}{compatibility}"}
      grep { $matrix->{$_->[0]}{$_->[1]} } [$x, $y], [$y, $x];
    my %seen;
    my @files = grep { !$seen{$_}++ && !/$LOCKFILE/ && !is_catalog_entry($_) } @{$pair->{files}};
    my $ids   = _file_ids($ctx, \@files);

    for my $name (@files) {
      my $first = _first_match_lines($ctx, $ids->{$name}, [$x, $y]);
      push @evidence,
        _evidence(
        $name,
        'pair',
        "incompatible pair $x + $y ("
          . ($pair->{mutual} ? 'mutual' : 'one-way')
          . '; OSADL: '
          . join('; ', @verdicts) . ')'
          . join('',   map {", $_ first matched at line $first->{$_}"} grep { $first->{$_} } $x, $y),
        lines => [sort { $a <=> $b } values %$first]
        );
    }
  }

  return @evidence;
}

# The package's own license documents, whole with the lines no known license pattern explains marked, since that is
# where an added restriction hides. A document Cavil matched completely is only named.
sub _license_documents ($ctx, $c) {
  my $app = $ctx->{app};
  my $id  = $ctx->{pkg}{id};

  # Reports analyzed before legal documents were annotated have none stored, so they are found here instead
  my $legal = $c->helpers->legal_documents($id)
    // $app->reports->build_annotations($id, from_json($app->reports->cached_dig_report($id) // '{}'))
    ->{legal_documents};

  my @documents = @{($legal // {})->{documents} // []};
  my @named     = map {"`$_->{path}`"} grep { !$_->{unexplained} } @documents;
  push @{$ctx->{extras}{license}},
    'Fully matched by known license patterns, so not reproduced: ' . join(', ', @named) . '.'
    if @named;
  push @{$ctx->{extras}{license}}, "$legal->{dropped} more license documents not considered." if $legal->{dropped};

  my @unexplained = grep { $_->{unexplained} } @documents;
  my $ids         = _file_ids($ctx, [map { $_->{path} } @unexplained]);
  my $spans       = $app->reports->licensed_spans([values %$ids]);
  my @evidence;
  for my $doc (@unexplained) {
    my $file = $ctx->{base}->child($doc->{path});
    next unless -f $file;
    my @lines = split /\n/, read_lines($file, 1, SCAN_LINES), -1;
    my $marks = unexplained_line_numbers($spans->{$ids->{$doc->{path}} // 0}, \@lines);
    push @evidence,
      _evidence(
      $doc->{path}, 'license',
      "license document, $doc->{unexplained} unknown lines"
        . (@lines >= SCAN_LINES ? ' (marked up to line ' . SCAN_LINES . ')' : ''),
      head  => HEAD_LINES,
      lines => $marks,
      marks => $marks
      );
  }

  return @evidence;
}

# Streamed, a generated file of hundreds of megabytes must not be loaded to excerpt forty lines of it
sub _line_count ($file) {
  open my $fh, '<:raw', $file or return 0;
  my ($count, $last) = (0, "\n");
  while (read $fh, my $buffer, 1 << 20) {
    $count += $buffer =~ tr/\n//;
    $last = substr $buffer, -1;
  }
  return $count + ($last eq "\n" ? 0 : 1);
}

# How many lines start in the first $bytes of a file, so the spec is bounded before it is read
sub _lines_within ($file, $bytes) {
  open my $fh, '<:raw', $file or return 1;
  read($fh, my $buffer, $bytes);
  return ($buffer =~ tr/\n//) + 1;
}

sub _mentions_install ($ctx, $name) {
  open my $fh, '<:raw', $ctx->{base}->child($name) or return 0;
  while (my $line = <$fh>) { return 1 if $line =~ /install/i }
  return 0;
}

# One entry per file in the order the sections need them, so a file appears once with every reason it matters, and
# an identical copy is named on the file it duplicates rather than repeated
sub _merge ($ctx, $evidence) {
  my (%by_path, @order);
  for my $item (@$evidence) {
    push @order, $item->{path} unless $by_path{$item->{path}};
    my $entry = $by_path{$item->{path}} //= {%$item, reasons => [], lines => [], marks => [], seen => {}};
    push @{$entry->{reasons}}, grep { !$entry->{seen}{"@$_"}++ } @{$item->{reasons}};
    push @{$entry->{lines}},   @{$item->{lines}};
    push @{$entry->{marks}},   @{$item->{marks} // []};
    $entry->{head} = max($entry->{head}, $item->{head});
  }

  my (%by_md5, @entries);
  for my $path (@order) {
    my $entry = $by_path{$path};
    my $file  = $ctx->{base}->child($path);
    unless (-f $file && -r _ && !-B _) {
      push @{$ctx->{extras}{$entry->{category}}}, "`$path` is not a readable text file, not reproduced.";
      next;
    }
    my $md5 = md5_file($file);
    if (my $original = $by_md5{$md5}) {
      push @{$original->{reasons}}, map { [$_->[0], "identical copy `$path`: $_->[1]"] } @{$entry->{reasons}};
      push @{$original->{lines}},   @{$entry->{lines}};
      push @{$original->{marks}},   @{$entry->{marks}};
      next;
    }
    push @entries, $by_md5{$md5} = $entry;
  }

  return \@entries;
}

sub _notes ($c, $pkg) {
  my $page = $c->notes->paginate_for_package($pkg->{name}, limit => 100, package_id => $pkg->{id},
    checksum => $pkg->{checksum});

  # Limitations and pinned notes sort first, so the budget only ever drops the oldest notes
  my ($used, @notes) = (0);
  for my $note (@{$page->{page}}) {
    last if ($used += length $note->{body}) > NOTES_BYTES && @notes;
    push @notes, $note;
  }

  return $c->render_to_string(
    'mcp/notes',
    format             => 'txt',
    notes              => \@notes,
    total              => $page->{total},
    start              => @notes ? 1 : 0,
    end                => scalar @notes,
    limit              => 100,
    offset             => 0,
    next_offset        => @notes < $page->{total} ? scalar @notes : undef,
    tags               => [],
    relevant_only      => 0,
    current_package_id => $pkg->{id},
    current_checksum   => $pkg->{checksum},
    body_limit         => 0
  );
}

# The head of a file and a window around every line that matters, overlapping windows merged. Windows past the cap
# are counted, never dropped silently.
sub _render ($ctx, $entry) {
  my $file  = $ctx->{base}->child($entry->{path});
  my $total = _line_count($file);
  my $head  = min($entry->{head}, $total);
  my %marks = map { $_ => 1 } @{$entry->{marks}};

  my @ranges = $head ? ([1, $head]) : ();
  my ($window_lines, %left_out) = (0);
  for my $line (sort { $a <=> $b } grep { $_ > $head && $_ <= $total } @{$entry->{lines}}) {
    next if @ranges && $line <= $ranges[-1][1];
    my ($start, $end) = (max($line - CONTEXT, 1), min($line + CONTEXT, $total));
    $start = $ranges[-1][1] + 1 if @ranges && $start <= $ranges[-1][1];
    if   (($window_lines += $end - $start + 1) > WINDOW_LINES) { $left_out{$line} = 1; next }
    if   (@ranges && $start == $ranges[-1][1] + 1)             { $ranges[-1][1] = $end }
    else                                                       { push @ranges, [$start, $end] }
  }

  my ($text, $shown) = ('', 0);
  for my $range (@ranges) {
    $text .= '  ... lines ' . ($shown + 1) . '-' . ($range->[0] - 1) . " not shown\n" if $range->[0] > $shown + 1;
    my $n = $range->[0];
    $text .= ($marks{$n++} && /^\s*\d+  .*\S/ ? '>>' : '  ') . "$_\n" for split /\n/, read_lines($file, @$range, 1);
    $shown = $range->[1];
  }
  $text .= '  ... lines ' . ($shown + 1) . "-$total not shown\n" if $total > $shown;

  my @reasons = map { $_->[1] } @{$entry->{reasons}};
  if (my @left = sort { $a <=> $b } keys %left_out) {
    push @reasons, @left . " more lines of interest between lines $left[0] and $left[-1] not shown";
  }
  return {path => $entry->{path}, reasons => \@reasons, text => $text};
}

# Each entry rendered under the first section that needs it and charged to its budget, a file that does not fit
# named with its reasons, and every later section pointing back to the files it shares with an earlier one
sub _sections ($ctx, $entries) {
  my (@sections, %index);
  for my $category (@{CATEGORIES()}) {
    my ($key, $title, $budget) = @$category;
    push @sections,
      $index{$key} = {
      key     => $key,
      title   => $title,
      budget  => $budget,
      blocks  => [],
      also    => [],
      omitted => [],
      extras  => $ctx->{extras}{$key}
      };
  }

  for my $entry (@$entries) {
    my $section = $index{$entry->{category}};
    my $block   = _render($ctx, $entry);
    my $where   = "shown under $section->{title}";
    if (length $block->{text} > $section->{budget}) {
      push @{$section->{omitted}}, "`$entry->{path}`: " . join('; ', @{$block->{reasons}});
      $where = "not reproduced, $section->{title} reached its size limit";
    }
    else {
      $section->{budget} -= length $block->{text};
      push @{$section->{blocks}}, $block;
    }

    my %seen = ($entry->{category} => 1);
    push @{$index{$_->[0]}{also}}, "`$entry->{path}`, $where" for grep { !$seen{$_->[0]}++ } @{$entry->{reasons}};
  }

  return \@sections;
}

sub _shipping ($ctx) {
  my $pkg = $ctx->{pkg};

  # Build files are read as the packager wrote them, the copies Cavil processed for matching are reflowed. Only names
  # that can be build evidence go on, a large package has more than a million files.
  my %files;
  for my $name (map { $_->[0] } @{Cavil::Checkout->new($ctx->{base}->dirname)->unpacked_files}) {
    my $original   = original_filename($name);
    my $depth      = $original =~ tr{/}{};
    my ($basename) = $original =~ m{([^/]+)$};
    next
      unless $depth == 0 && $basename =~ /\.(?:spec|changes)$/
      || $depth <= 1     && $basename =~ $MANIFEST
      || $depth <= 3     && $basename =~ $BUILD_FILE;
    $files{$original ne $name && -f $ctx->{base}->child($original) ? $original : $name} = 1;
  }
  my @files = sort { ($a =~ tr{/}{}) <=> ($b =~ tr{/}{}) || $a cmp $b } keys %files;

  my (@specs, @evidence, $build);
  for my $name (grep { !peripheral_scope([$_]) } @files) {
    my $depth = $name =~ tr{/}{};
    my ($basename) = $name =~ m{([^/]+)$};
    if    ($depth == 0 && $basename =~ /\.spec$/) { push @specs, $name }
    elsif ($depth <= 1 && $basename =~ $MANIFEST) {
      push @evidence, _evidence($name, 'shipping', 'project manifest', head => HEAD_LINES);
    }
    elsif ($depth <= 3 && $basename =~ $BUILD_FILE && _mentions_install($ctx, $name)) {
      next if ++$build > BUILD_FILES_MAX;
      push @evidence, _evidence($name, 'shipping', 'build file with install rules', head => HEAD_LINES);
    }
  }
  push @{$ctx->{extras}{shipping}}, $build - BUILD_FILES_MAX . ' more build files with install rules not reproduced.'
    if ($build // 0) > BUILD_FILES_MAX;

  # The spec named after the package carries %prep, %build and %files; a chromium keeplibs list sits a thousand
  # lines in, so it is capped by size alone. Sibling specs are named only, kernel ships sixteen of them.
  my ($main) = grep { $_ eq "$pkg->{name}.spec" } @specs;
  $main //= $specs[0];
  if (defined $main) {
    unshift @evidence,
      _evidence($main, 'shipping', 'spec file', head => _lines_within($ctx->{base}->child($main), SPEC_MAX));
  }
  else { push @{$ctx->{extras}{shipping}}, 'No spec file at the package root.' }
  my @others = map {"`$_`"} grep { !defined $main || $_ ne $main } @specs;
  push @{$ctx->{extras}{shipping}}, 'Other spec files, not reproduced: ' . join(', ', @others) . '.' if @others;

  if (($pkg->{notice} // '') =~ /Declared license .+ -> / && (my ($changes) = grep {/^[^\/]+\.changes$/} @files)) {
    push @evidence, _evidence($changes, 'shipping', 'changelog, the declared license changed', head => CHANGES_LINES);
  }

  return @evidence;
}

# Shipped source or vendored code, which can be linked in, but not tests, docs, examples or license catalogs
sub _ships ($path) {
  return 0 if is_catalog_entry($path);
  my $kind = license_terms_kind($path);
  return !$kind || $kind eq 'vendored';
}

sub _snippets ($ctx) {
  my $found = $ctx->{app}->snippets->snippet_search(
    {package_id => $ctx->{pkg}{id}, own_package => 1, skip_detail => 1, group => 'none', limit => SNIPPETS_FETCH});
  push @{$ctx->{extras}{snippet}}, 'More unresolved snippets exist than were considered.' if $found->{has_more};

  return map {
    my $range = $_->{line} == $_->{eline} ? "line $_->{line}" : "lines $_->{line}-$_->{eline}";
    _evidence(
      $_->{file}, 'snippet',
      "unresolved snippet $_->{snippet_id} at $range, closest license " . ($_->{closest_license} // 'unknown'),
      lines => [$_->{line} .. $_->{eline}],
      marks => [$_->{line} .. $_->{eline}]
    )
  } @{$found->{snippets}};
}

1;
