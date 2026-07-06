# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later
package Cavil::Plugin::MCP;
use Mojo::Base 'Mojolicious::Plugin', -signatures;

use MCP::Server;
use Cavil::Util         qw(pattern_matches pattern_contains_redundant_skip read_lines validate_tags);
use Cavil::Model::Notes qw(NOTE_BODY_MAX_LENGTH);
use File::Find          qw(find);
use Mojo::File          qw(path);
use Text::Glob          qw(glob_to_regex);

my $WRITE_TOOL_ROLES = {
  cavil_accept_review           => {admin => 1, lawyer => 1, manager => 1},
  cavil_reject_review           => {admin => 1, lawyer => 1},
  cavil_propose_ignore_snippet  => {admin => 1, lawyer => 1, contributor => 1},
  cavil_propose_license_pattern => {admin => 1, lawyer => 1, contributor => 1},
  cavil_propose_ignore_glob     => {admin => 1, lawyer => 1, contributor => 1},
  cavil_create_snippet          => {admin => 1, lawyer => 1, contributor => 1},
  cavil_report_missing_license  => {admin => 1, lawyer => 1, contributor => 1}
};
my $WRITE_ACCESS_TOOLS = {cavil_create_note => 1};

my $FINALIZE_REVIEW_TOOLS = {cavil_accept_review => 1, cavil_reject_review => 1};

sub register ($self, $app, $config) {
  my $mcp = MCP::Server->new;
  $mcp->name('Cavil');
  $mcp->version('1.0.0');

  $mcp->on(tools => \&_filter_tools);

  $mcp->tool(
    name         => 'cavil_get_open_reviews',
    description  => 'Get a paginated list of highest priority open reviews, use "search" to limit results',
    input_schema => {
      type       => 'object',
      properties => {
        search       => {type => 'string',  description => 'Filter results by package name, checksum or external link'},
        limit        => {type => 'integer', minimum     => 1, maximum => 100, default => 20},
        offset       => {type => 'integer', minimum     => 0, default => 0},
        min_priority => {type => 'integer', minimum     => 1, maximum => 10, default => 1}
      },
      required => []
    },
    code => \&tool_cavil_get_open_reviews
  );
  $mcp->tool(
    name        => 'cavil_search_packages',
    description =>
      'Search all packages regardless of review state, by exact name or by a vendored component they ship. Unlike'
      . ' cavil_get_open_reviews (which only returns the open review queue), this searches the whole package set,'
      . ' including already reviewed packages. Use "component" for security and supply-chain triage, e.g. to find'
      . ' every package that bundles a vulnerable dependency; it is a case-insensitive substring matched against a'
      . ' component name and its purl, so "lodash" matches all versions and "pkg:npm/lodash@4.17.20" pins one. When'
      . ' searching by component, each result lists the matching components so you see the exact version shipped.'
      . ' Embargoed and obsolete packages are always excluded',
    input_schema => {
      type       => 'object',
      properties => {
        name      => {type => 'string',  description => 'Exact package name'},
        component => {type => 'string',  description => 'Vendored component name or purl (case-insensitive substring)'},
        limit     => {type => 'integer', minimum     => 1, maximum => 100, default => 25},
        offset    => {type => 'integer', minimum     => 0, default => 0}
      },
      required => []
    },
    code => \&tool_cavil_search_packages
  );
  $mcp->tool(
    name         => 'cavil_get_report',
    description  => 'Get legal report for a specific package',
    input_schema =>
      {type => 'object', properties => {package_id => {type => 'integer', minimum => 1}}, required => ['package_id']},
    code => \&tool_cavil_get_report
  );
  $mcp->tool(
    name        => 'cavil_get_file',
    description =>
      'Get the content of a specific file in the package, no more than 1000 lines can be retrieved at once. Each'
      . ' line is prefixed with its absolute line number for reference (e.g. when calling cavil_create_snippet);'
      . ' these prefixes are display-only and must never be included in license patterns or snippet text',
    input_schema => {
      type       => 'object',
      properties => {
        package_id => {type => 'integer', minimum => 1},
        file_path  => {type => 'string'},
        start_line => {type => 'integer', minimum => 1, default => 1},
        end_line   => {type => 'integer', minimum => 1, default => 100}
      },
      required => ['package_id', 'file_path']
    },
    code => \&tool_cavil_get_file
  );
  $mcp->tool(
    name         => 'cavil_list_files',
    description  => 'List files in the package (optionally filtered by glob), up to 1000 files',
    input_schema => {
      type       => 'object',
      properties => {package_id => {type => 'integer', minimum => 1}, file_glob => {type => 'string', default => '*'}},
      required   => ['package_id']
    },
    code => \&tool_cavil_list_files
  );
  $mcp->tool(
    name        => 'cavil_create_note',
    description => 'Create a public AI-assisted note for a specific package. Pass skip_if_existing_tag to make '
      . 'the call idempotent: if a note carrying that tag already applies to this report (it was written on this '
      . 'report, or on another review with an identical license report), no note is created and the existing one '
      . 'is reported instead.',
    input_schema => {
      type       => 'object',
      properties => {
        package_id           => {type => 'integer', minimum => 1},
        body                 => {type => 'string'},
        tags                 => {type => 'array', items => {type => 'string'}, default => []},
        skip_if_existing_tag => {type => 'string'}
      },
      required => ['package_id', 'body']
    },
    code => \&tool_cavil_create_note
  );
  $mcp->tool(
    name        => 'cavil_get_notes',
    description => 'Get a paginated list of notes for a specific package, optionally filtered by tags. Each note is '
      . 'marked by relevance to this package report: [this report] (written on it), [same report] (from another '
      . 'review with an identical license report), or [other report] (different licensing). Pass relevant_only=true '
      . 'to return only the first two.',
    input_schema => {
      type       => 'object',
      properties => {
        package_id    => {type => 'integer', minimum => 1},
        tags          => {type => 'array',   items   => {type => 'string'}, default => []},
        relevant_only => {type => 'boolean', default => \0},
        limit         => {type => 'integer', minimum => 1, maximum => 100, default => 20},
        offset        => {type => 'integer', minimum => 0, default => 0}
      },
      required => ['package_id']
    },
    code => \&tool_cavil_get_notes
  );
  $mcp->tool(
    name        => 'cavil_accept_review',
    description =>
      'Accept a legal review for a specific package, only give a reason if there are special circumstances',
    input_schema => {
      type       => 'object',
      properties =>
        {package_id => {type => 'integer', minimum => 1}, reason => {type => 'string', default => 'Reviewed ok'}},
      required => ['package_id']
    },
    code => \&tool_cavil_accept_review
  );
  $mcp->tool(
    name         => 'cavil_reject_review',
    description  => 'Reject a legal review for a specific package',
    input_schema => {
      type       => 'object',
      properties => {package_id => {type => 'integer', minimum => 1}, reason => {type => 'string'}},
      required   => ['package_id', 'reason']
    },
    code => \&tool_cavil_reject_review
  );
  $mcp->tool(
    name         => 'cavil_propose_ignore_snippet',
    description  => 'Propose to ignore a specific snippet in the legal review',
    input_schema => {
      type       => 'object',
      properties => {
        package_id => {type => 'integer', minimum => 1},
        snippet_id => {type => 'integer', minimum => 1},
        reason     => {type => 'string'}
      },
      required => ['package_id', 'snippet_id', 'reason']
    },
    code => \&tool_cavil_propose_ignore_snippet
  );
  $mcp->tool(
    name         => 'cavil_propose_license_pattern',
    description  => 'Propose a new license pattern to be added to the system',
    input_schema => {
      type       => 'object',
      properties => {
        package_id => {type => 'integer', minimum => 1},
        snippet_id => {type => 'integer', minimum => 1},
        pattern    => {type => 'string'},
        license    => {type => 'string'},
        reason     => {type => 'string'}
      },
      required => ['package_id', 'snippet_id', 'pattern', 'license', 'reason']
    },
    code => \&tool_cavil_propose_license_pattern
  );
  $mcp->tool(
    name        => 'cavil_propose_ignore_glob',
    description =>
      'Propose a file path glob to ignore during license scanning system-wide. Use this instead of proposing'
      . ' individual snippet ignores when an entire file or directory is obviously test fixtures, license-detection'
      . ' reference data or captured sample output (e.g. "pkgname-*/path/to/testdata/*.log"). Use a leading'
      . ' "pkgname-*/" prefix to match the versioned top-level directory and "*" for the version segment',
    input_schema => {
      type       => 'object',
      properties =>
        {package_id => {type => 'integer', minimum => 1}, glob => {type => 'string'}, reason => {type => 'string'}},
      required => ['package_id', 'glob', 'reason']
    },
    code => \&tool_cavil_propose_ignore_glob
  );
  $mcp->tool(
    name        => 'cavil_create_snippet',
    description =>
      'Create a new snippet from a line range in a matched file. Use this to capture a larger region than an existing'
      . ' snippet covers, e.g. when an unresolved match is only a fragment in the middle of a full license text. Use'
      . ' cavil_get_file to locate the exact start and end line numbers first. Returns the new snippet id, which can'
      . ' then be used with cavil_propose_license_pattern',
    input_schema => {
      type       => 'object',
      properties => {
        package_id => {type => 'integer', minimum => 1},
        file_path  => {type => 'string'},
        start_line => {type => 'integer', minimum => 1},
        end_line   => {type => 'integer', minimum => 1}
      },
      required => ['package_id', 'file_path', 'start_line', 'end_line']
    },
    code => \&tool_cavil_create_snippet
  );
  $mcp->tool(
    name        => 'cavil_report_missing_license',
    description =>
      'Report a snippet as a missing license: text that is clearly license-relevant but that you cannot confidently'
      . ' turn into a license pattern yourself, so that a human lawyer can author the real pattern. Use this instead'
      . ' of guessing a pattern when the license cannot be cleanly isolated (e.g. non-standard custom prose, or text'
      . ' whose identity stays unclear even with file context). The snippet is added to the Missing Licenses review'
      . ' queue. The "reason" should clearly explain in one or two sentences why this needs human judgement and,'
      . ' whenever possible, recommend the SPDX license identifier you believe applies (e.g. "Looks like a custom'
      . ' variant of BSD-3-Clause; recommend a lawyer confirm BSD-3-Clause"). Do not use this for text that is'
      . ' definitely not a license (use cavil_propose_ignore_snippet) or for clear declarations you can pattern'
      . ' (use cavil_propose_license_pattern)',
    input_schema => {
      type       => 'object',
      properties => {
        package_id => {type => 'integer', minimum => 1},
        snippet_id => {type => 'integer', minimum => 1},
        reason     => {type => 'string'}
      },
      required => ['package_id', 'snippet_id', 'reason']
    },
    code => \&tool_cavil_report_missing_license
  );

  return $mcp->to_action;
}

sub tool_cavil_accept_review ($tool, $args) {
  my $id   = $args->{package_id};
  my $c    = _get_controller($tool);
  my $pkgs = $c->packages;
  return $tool->text_result('Package not found', 1) unless my $pkg = $pkgs->find($id);
  return $tool->text_result('Package is embargoed and may not be processed with AI', 1) if $pkg->{embargoed};
  return $tool->text_result('Package has already been reviewed',                     1) if $pkg->{state} ne 'new';

  my $reason = $args->{reason};
  $pkg->{result} = $reason ? "AI Assistant: $reason" : 'Reviewed ok';
  my $user = $c->current_user;
  $pkg->{reviewing_user}   = $c->users->id_for_login($user);
  $pkg->{state}            = $c->current_user_has_role('lawyer') ? 'acceptable_by_lawyer' : 'acceptable';
  $pkg->{review_timestamp} = 1;
  $pkg->{ai_assisted}      = 1;

  $pkgs->update($pkg);

  return 'Review has been successfully accepted';
}

sub tool_cavil_get_open_reviews ($tool, $args) {
  my $c = _get_controller($tool);
  my ($limit, $limit_error) = _bounded_int_arg($args->{limit}, 20, 1, 100, 'limit');
  return $tool->text_result($limit_error, 1) if $limit_error;
  my ($offset, $offset_error) = _bounded_int_arg($args->{offset}, 0, 0, undef, 'offset');
  return $tool->text_result($offset_error, 1) if $offset_error;
  my ($min_priority, $priority_error) = _bounded_int_arg($args->{min_priority}, 1, 1, 10, 'min_priority');
  return $tool->text_result($priority_error, 1) if $priority_error;
  my $reviews = $c->packages->paginate_open_reviews(
    {
      limit         => $limit,
      offset        => $offset,
      priority      => $min_priority,
      in_progress   => 'false',
      not_embargoed => 'true',
      search        => $args->{search} // ''
    }
  );
  my $next_offset = $reviews->{end} < $reviews->{total} ? $offset + $limit : undef;
  return $c->render_to_string(
    'mcp/open_reviews',
    format       => 'txt',
    reviews      => $reviews->{page},
    total        => $reviews->{total},
    start        => $reviews->{start},
    end          => $reviews->{end},
    limit        => $limit,
    offset       => $offset,
    next_offset  => $next_offset,
    min_priority => $min_priority
  );
}

sub tool_cavil_search_packages ($tool, $args) {
  my $c = _get_controller($tool);
  my ($limit, $limit_error) = _bounded_int_arg($args->{limit}, 25, 1, 100, 'limit');
  return $tool->text_result($limit_error, 1) if $limit_error;
  my ($offset, $offset_error) = _bounded_int_arg($args->{offset}, 0, 0, undef, 'offset');
  return $tool->text_result($offset_error, 1) if $offset_error;

  # Same package search as the web UI and the search API, but never exposes embargoed or obsolete packages
  my $name      = $args->{name};
  my $component = $args->{component};
  my $page      = $c->packages->paginate_review_search(
    $name,
    {
      search        => '',
      component     => $component,
      limit         => $limit,
      offset        => $offset,
      not_obsolete  => 'true',
      not_embargoed => 'true'
    }
  );

  # When searching by component, attach the matching components so a caller sees the exact version shipped
  my @ids        = map { $_->{id} } @{$page->{page}};
  my $components = length($component // '') ? $c->packages->matching_components(\@ids, $component) : {};

  my $next_offset = $page->{end} < $page->{total} ? $offset + $limit : undef;
  return $c->render_to_string(
    'mcp/packages',
    format      => 'txt',
    packages    => $page->{page},
    components  => $components,
    total       => $page->{total},
    start       => $page->{start},
    end         => $page->{end},
    limit       => $limit,
    offset      => $offset,
    next_offset => $next_offset,
    name        => $name,
    component   => $component
  );
}

sub tool_cavil_get_report ($tool, $args) {
  my $id = $args->{package_id};
  my $c  = _get_controller($tool);
  return $tool->text_result('Package not found', 1) unless my $pkg = $c->packages->find($id);
  return $tool->text_result('Package is embargoed and may not be processed with AI', 1) if $pkg->{embargoed};

  return $tool->text_result('Package is being processed, please try again later', 1)
    if $c->app->minion->jobs({states => ['inactive', 'active'], notes => ["pkg_$id"]})->total;

  return $tool->text_result('Package is not yet indexed, please try again later', 1) unless $pkg->{indexed};

  return $tool->text_result('No report available', 1) unless defined((my $report = $c->helpers->mcp_report($id)));
  return $tool->text_result($report);
}

sub tool_cavil_get_file ($tool, $args) {
  my $id         = $args->{package_id};
  my $path       = $args->{file_path};
  my $start_line = $args->{start_line} // 1;
  my $end_line   = $args->{end_line}   // 100;
  my $c          = _get_controller($tool);
  return $tool->text_result('Package not found', 1) unless my $pkg = $c->packages->find($id);
  return $tool->text_result('Package is embargoed and may not be processed with AI', 1) if $pkg->{embargoed};

  $path =~ s,/$,,;
  return $tool->text_result('Invalid file path', 1) if $path =~ qr/\.\./;
  my $file = path($c->app->config->{checkout_dir}, $pkg->{name}, $pkg->{checkout_dir}, '.unpacked', $path);
  return $tool->text_result('Maximum line range exceeded',     1) if ($end_line - $start_line) > 1000;
  return $tool->text_result('Invalid line range',              1) if $start_line > $end_line;
  return $tool->text_result('File not found',                  1) unless -e $file;
  return $tool->text_result('Path is a directory, not a file', 1) if -d $file;

  return $tool->text_result(read_lines($file, $start_line, $end_line, 1));
}

sub tool_cavil_list_files ($tool, $args) {
  my $id   = $args->{package_id};
  my $glob = $args->{file_glob} // '*';
  my $c    = _get_controller($tool);
  return $tool->text_result('Package not found', 1) unless my $pkg = $c->packages->find($id);
  return $tool->text_result('Package is embargoed and may not be processed with AI', 1) if $pkg->{embargoed};

  local $Text::Glob::strict_wildcard_slash = 0;
  my $regex = glob_to_regex($glob);
  my $root  = path($c->app->config->{checkout_dir}, $pkg->{name}, $pkg->{checkout_dir}, '.unpacked');
  return $tool->text_result('Package is not yet unpacked', 1) unless -d $root;

  my @files;
  my $file_limit_reached = "__CAVIL_MCP_LIST_FILES_LIMIT_REACHED__\n";
  eval {
    find(
      {
        wanted => sub {
          return if -d $File::Find::name;
          my $relative = path($File::Find::name)->to_rel($root)->to_string;
          return unless $relative =~ $regex;
          push @files, $relative;
          die $file_limit_reached if @files > 1000;
        },
        no_chdir => 1
      },
      $root->to_string
    );
  };
  if ($@) {
    return $tool->text_result('Maximum file list size exceeded', 1) if $@ eq $file_limit_reached;
    die $@;
  }

  return $tool->text_result('No files found', 1) unless @files;
  return $tool->text_result(join("\n", sort @files));
}

sub tool_cavil_create_note ($tool, $args) {
  my $id   = $args->{package_id};
  my $body = $args->{body};
  my $c    = _get_controller($tool);
  return $tool->text_result('Package not found', 1) unless my $pkg = $c->packages->find($id);
  return $tool->text_result('Package is embargoed and may not be processed with AI', 1) if $pkg->{embargoed};
  return $tool->text_result('Note body is required', 1) unless defined $body && length $body;
  return $tool->text_result('Note body is too long', 1) if length($body) > NOTE_BODY_MAX_LENGTH;

  my ($tags, $tag_error) = validate_tags($args->{tags});
  return $tool->text_result($tag_error, 1) if $tag_error;

  # Server-enforced idempotency guard: if a note carrying skip_if_existing_tag
  # already applies to this report (written on it, or on another review with an
  # identical license report), skip the write. Returned as a non-error so the
  # caller treats it as "already done" rather than retrying into a duplicate.
  my $include_lawyer_only = $c->current_user_has_role('admin', 'lawyer') ? 1 : 0;
  my $gate                = $args->{skip_if_existing_tag};
  if (defined $gate && length $gate) {
    my $existing = $c->notes->relevant_tagged_note($pkg->{name}, $id, $pkg->{checksum}, $gate,
      include_lawyer_only => $include_lawyer_only);
    return $tool->text_result(
      "Skipped: package already has an up-to-date '$gate' note (#$existing) for this report's current license findings."
        . ' No new note was created.')
      if $existing;
  }

  my $author = $c->users->find(login => $c->current_user);
  return $tool->text_result('Unknown user', 1) unless $author;

  my $note = $c->notes->add($id, $pkg->{name}, $author->{id}, $body, 0, 1, $tags);
  return $tool->text_result("Note #$note->{id} has been successfully created");
}

sub tool_cavil_get_notes ($tool, $args) {
  my $id = $args->{package_id};
  my $c  = _get_controller($tool);
  return $tool->text_result('Package not found', 1) unless my $pkg = $c->packages->find($id);
  return $tool->text_result('Package is embargoed and may not be processed with AI', 1) if $pkg->{embargoed};

  my ($limit, $limit_error) = _bounded_int_arg($args->{limit}, 20, 1, 100, 'limit');
  return $tool->text_result($limit_error, 1) if $limit_error;
  my ($offset, $offset_error) = _bounded_int_arg($args->{offset}, 0, 0, undef, 'offset');
  return $tool->text_result($offset_error, 1) if $offset_error;
  my ($tags, $tag_error) = validate_tags($args->{tags});
  return $tool->text_result($tag_error, 1) if $tag_error;
  my $relevant_only = $args->{relevant_only} ? 1 : 0;

  my $include_lawyer_only = $c->current_user_has_role('admin', 'lawyer') ? 1 : 0;
  my $page                = $c->notes->paginate_for_package(
    $pkg->{name},
    limit               => $limit,
    offset              => $offset,
    tags                => $tags,
    include_lawyer_only => $include_lawyer_only,
    relevant_only       => $relevant_only,
    package_id          => $id,
    checksum            => $pkg->{checksum}
  );
  my $next_offset = $page->{end} < $page->{total} ? $offset + $limit : undef;

  return $c->render_to_string(
    'mcp/notes',
    format             => 'txt',
    notes              => $page->{page},
    total              => $page->{total},
    start              => $page->{start},
    end                => $page->{end},
    limit              => $limit,
    offset             => $offset,
    next_offset        => $next_offset,
    tags               => $tags,
    relevant_only      => $relevant_only,
    current_package_id => $id,
    current_checksum   => $pkg->{checksum}
  );
}

sub tool_cavil_propose_ignore_snippet ($tool, $args) {
  my $package_id = $args->{package_id};
  my $snippet_id = $args->{snippet_id};
  my $reason     = $args->{reason};
  my $c          = _get_controller($tool);
  return $tool->text_result('Package not found', 1) unless my $pkg = $c->packages->find($package_id);
  return $tool->text_result('Package is embargoed and may not be processed with AI', 1) if $pkg->{embargoed};
  return $tool->text_result('Snippet not found', 1) unless my $snippet = $c->snippets->with_context($snippet_id);

  my $user_id = $c->users->id_for_login($c->current_user);
  my $result  = $c->patterns->propose_ignore(
    snippet              => $snippet_id,
    hash                 => $snippet->{hash},
    from                 => $pkg->{name},
    pattern              => $snippet->{text},
    highlighted_keywords => [sort keys %{$snippet->{keywords}}],
    highlighted_licenses => [sort keys %{$snippet->{matches}}],
    package              => $pkg->{id},
    owner                => $user_id,
    ai_assisted          => 1,
    reason               => "AI Assistant: $reason"
  );

  return $tool->text_result('Conflicting ignore pattern already exists',          1) if $result->{conflict};
  return $tool->text_result('Conflicting ignore pattern proposal already exists', 1) if $result->{proposal_conflict};

  return 'Proposal to ignore snippet has been successfully submitted';
}

sub tool_cavil_report_missing_license ($tool, $args) {
  my $package_id = $args->{package_id};
  my $snippet_id = $args->{snippet_id};
  my $reason     = $args->{reason};
  my $c          = _get_controller($tool);
  return $tool->text_result('Package not found', 1) unless my $pkg = $c->packages->find($package_id);
  return $tool->text_result('Package is embargoed and may not be processed with AI', 1) if $pkg->{embargoed};
  return $tool->text_result('Snippet not found', 1) unless my $snippet = $c->snippets->with_context($snippet_id);

  my $user_id = $c->users->id_for_login($c->current_user);
  my $result  = $c->patterns->propose_missing(
    snippet              => $snippet_id,
    hash                 => $snippet->{hash},
    from                 => $pkg->{name},
    pattern              => $snippet->{text},
    highlighted_keywords => [sort keys %{$snippet->{keywords}}],
    highlighted_licenses => [sort keys %{$snippet->{matches}}],
    package              => $pkg->{id},
    owner                => $user_id,
    ai_assisted          => 1,
    reason               => "AI Assistant: $reason"
  );

  return $tool->text_result('Conflicting license pattern already exists', 1) if $result->{conflict};
  return $tool->text_result('A missing license report already exists',    1) if $result->{proposal_conflict};

  return 'Missing license has been successfully reported';
}

sub tool_cavil_propose_license_pattern ($tool, $args) {
  my $package_id = $args->{package_id};
  my $snippet_id = $args->{snippet_id};
  my $pattern    = $args->{pattern};
  my $license    = $args->{license};
  my $reason     = $args->{reason};
  my $c          = _get_controller($tool);
  return $tool->text_result('Package not found', 1) unless my $pkg = $c->packages->find($package_id);
  return $tool->text_result('Package is embargoed and may not be processed with AI', 1) if $pkg->{embargoed};
  return $tool->text_result('Snippet not found', 1) unless my $snippet = $c->snippets->with_context($snippet_id);

  return $tool->text_result('License pattern does not match the original snippet', 1)
    unless pattern_matches($pattern, $snippet->{text});
  return $tool->text_result('License pattern contains redundant $SKIP at beginning or end', 1)
    if pattern_contains_redundant_skip($pattern);

  my $matches = $c->patterns->closest_licenses($license);
  my $match   = $matches->{exact};
  unless ($match) {
    my $closest = $matches->{closest};
    return $tool->text_result('License expression is not in the list of known licenses', 1) unless @$closest;
    my $closest_list
      = join("\n", map { sprintf('* %s (%d%% match)', $_->{license}, int($_->{score} * 100 + 0.5)) } @$closest);
    return $tool->text_result(
      "License expression is not in the list of known licenses, closest matches are:\n$closest_list", 1);
  }

  my $user_id = $c->users->id_for_login($c->current_user);
  my $result  = $c->patterns->propose_create(
    snippet              => $snippet_id,
    pattern              => $pattern,
    highlighted_keywords => [],
    highlighted_licenses => [],
    edited               => 1,
    license              => $match->{license},
    risk                 => $match->{risk},
    package              => $package_id,
    patent               => $match->{patent},
    trademark            => $match->{trademark},
    export_restricted    => $match->{export_restricted},
    cla                  => $match->{cla},
    eula                 => $match->{eula},
    owner                => $user_id,
    ai_assisted          => 1,
    reason               => "AI Assistant: $reason"
  );

  return $tool->text_result('Conflicting license pattern already exists',          1) if $result->{conflict};
  return $tool->text_result('Conflicting license pattern proposal already exists', 1) if $result->{proposal_conflict};

  return 'Proposal for new license pattern has been successfully submitted';
}

sub tool_cavil_propose_ignore_glob ($tool, $args) {
  my $package_id = $args->{package_id};
  my $glob       = $args->{glob};
  my $reason     = $args->{reason};
  my $c          = _get_controller($tool);
  return $tool->text_result('Package not found', 1) unless my $pkg = $c->packages->find($package_id);
  return $tool->text_result('Package is embargoed and may not be processed with AI', 1) if $pkg->{embargoed};
  return $tool->text_result('Glob is required', 1) unless defined $glob && length $glob;
  return $tool->text_result('Glob does not match any files in the package report', 1)
    unless $c->packages->glob_matches_report_files($pkg->{id}, $glob);

  my $user_id = $c->users->id_for_login($c->current_user);
  my $result  = $c->patterns->propose_glob(
    glob        => $glob,
    from        => $pkg->{name},
    package     => $pkg->{id},
    owner       => $user_id,
    ai_assisted => 1,
    reason      => "AI Assistant: $reason"
  );

  return $tool->text_result('Conflicting ignore glob already exists',          1) if $result->{conflict};
  return $tool->text_result('Conflicting ignore glob proposal already exists', 1) if $result->{proposal_conflict};

  return 'Proposal to ignore glob has been successfully submitted';
}

sub tool_cavil_create_snippet ($tool, $args) {
  my $id         = $args->{package_id};
  my $path       = $args->{file_path};
  my $start_line = $args->{start_line};
  my $end_line   = $args->{end_line};
  my $c          = _get_controller($tool);
  return $tool->text_result('Package not found', 1) unless my $pkg = $c->packages->find($id);
  return $tool->text_result('Package is embargoed and may not be processed with AI', 1) if $pkg->{embargoed};

  return $tool->text_result('Invalid line range',          1) if $start_line > $end_line;
  return $tool->text_result('Maximum line range exceeded', 1) if ($end_line - $start_line) > 1000;

  # A matched file is required (it also guarantees the file was unpacked and indexed)
  return $tool->text_result('File not found in matched files', 1)
    unless defined(my $snippet_id = $c->snippets->from_file_path($id, $path, $start_line, $end_line));

  my $snippet = $c->snippets->find($snippet_id);
  return "Snippet $snippet_id created:\n\n$snippet->{text}";
}

sub tool_cavil_reject_review ($tool, $args) {
  my $id   = $args->{package_id};
  my $c    = _get_controller($tool);
  my $pkgs = $c->packages;
  return $tool->text_result('Package not found', 1) unless my $pkg = $pkgs->find($id);
  return $tool->text_result('Package is embargoed and may not be processed with AI', 1) if $pkg->{embargoed};
  return $tool->text_result('Package has already been reviewed',                     1) if $pkg->{state} ne 'new';

  my $reason = $args->{reason};
  $pkg->{result} = "AI Assistant: $reason";
  my $user = $c->current_user;
  $pkg->{reviewing_user}   = $c->users->id_for_login($user);
  $pkg->{state}            = 'unacceptable';
  $pkg->{review_timestamp} = 1;
  $pkg->{ai_assisted}      = 1;

  $pkgs->update($pkg);

  return 'Review has been successfully rejected';
}

sub _filter_tools ($server, $tools, $context) {
  my $c      = $context->{controller};
  my %scopes = map { $_ => 1 } @{$c->current_user_scopes};
  my $roles  = $c->current_user_roles;

  my $filtered = [];
  for my $tool (@$tools) {
    my $name = $tool->name;
    if ($WRITE_ACCESS_TOOLS->{$name}) {
      next unless $scopes{'cavil:write'};
    }
    if (my $check = $WRITE_TOOL_ROLES->{$name}) {
      next unless $scopes{'cavil:write'};
      next unless grep { $check->{$_} } @$roles;
    }
    if ($FINALIZE_REVIEW_TOOLS->{$name}) {
      next unless $scopes{'cavil:reviews.finalize'};
    }
    push @$filtered, $tool;
  }

  @$tools = @$filtered;
}

sub _bounded_int_arg ($value, $default, $min, $max, $name) {
  return ($default, undef) unless defined $value;
  my $range = defined $max ? "between $min and $max" : "greater than or equal to $min";
  return (undef, "$name must be an integer $range") unless "$value" =~ /^\d+$/;
  my $int = int $value;
  return (undef, "$name must be an integer $range") if $int < $min || (defined $max && $int > $max);
  return ($int,  undef);
}

sub _get_controller ($tool) { $tool->context->{controller} }

1;
