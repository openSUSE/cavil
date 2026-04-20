# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later
package Cavil::Plugin::MCP;
use Mojo::Base 'Mojolicious::Plugin', -signatures;

use MCP::Server;
use Cavil::Util qw(pattern_matches pattern_contains_redundant_skip read_lines);
use File::Find  qw(find);
use Mojo::File  qw(path);
use Text::Glob  qw(glob_to_regex);
use Try::Tiny;

$Text::Glob::strict_wildcard_slash = 0;

my $WRITE_TOOL_ROLES = {
  cavil_accept_review           => {admin => 1, lawyer => 1, manager => 1},
  cavil_reject_review           => {admin => 1, lawyer => 1},
  cavil_propose_ignore_snippet  => {admin => 1, lawyer => 1, contributor => 1},
  cavil_propose_license_pattern => {admin => 1, lawyer => 1, contributor => 1}
};

sub register ($self, $app, $config) {
  my $mcp = MCP::Server->new;
  $mcp->name('Cavil');
  $mcp->version('1.0.0');

  $mcp->on(tools => \&_filter_tools);

  $mcp->tool(
    name         => 'cavil_get_open_reviews',
    description  => 'Get list of 20 highest priority open reviews, use "search" to limit results',
    input_schema => {
      type       => 'object',
      properties => {search => {type => 'string', description => 'Filter results by package name or external link'}},
      required   => []
    },
    code => \&tool_cavil_get_open_reviews
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
      'Get the content of a specific file in the package, no more than 1000 lines can be retrieved at once',
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
  my $c       = _get_controller($tool);
  my $reviews = $c->packages->paginate_open_reviews(
    {limit => 20, offset => 0, in_progress => 'false', not_embargoed => 'true', search => $args->{search} // ''});
  return
    return $c->render_to_string('mcp/open_reviews', format => 'txt', reviews => $reviews->{page},
    total => $reviews->{total});
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

  return $tool->text_result(read_lines($file, $start_line, $end_line));
}

sub tool_cavil_list_files ($tool, $args) {
  my $id   = $args->{package_id};
  my $glob = $args->{file_glob} // '*';
  my $c    = _get_controller($tool);
  return $tool->text_result('Package not found', 1) unless my $pkg = $c->packages->find($id);
  return $tool->text_result('Package is embargoed and may not be processed with AI', 1) if $pkg->{embargoed};

  my $regex = glob_to_regex($glob);
  my $root  = path($c->app->config->{checkout_dir}, $pkg->{name}, $pkg->{checkout_dir}, '.unpacked');
  return $tool->text_result('Package is not yet unpacked', 1) unless -d $root;

  my @files;
  my $file_limit_reached = "__CAVIL_MCP_LIST_FILES_LIMIT_REACHED__\n";
  try {
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
  }
  catch {
    return $tool->text_result('Maximum file list size exceeded', 1) if $_ eq $file_limit_reached;
    die $_;
  }

  return $tool->text_result(join("\n", sort @files));
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
    my $closest_list = join("\n", map {"* $_->{license}"} @$closest);
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
    owner                => $user_id,
    ai_assisted          => 1,
    reason               => "AI Assistant: $reason"
  );

  return $tool->text_result('Conflicting license pattern already exists',          1) if $result->{conflict};
  return $tool->text_result('Conflicting license pattern proposal already exists', 1) if $result->{proposal_conflict};

  return 'Proposal for new license pattern has been successfully submitted';
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
  my $c            = $context->{controller};
  my $write_access = $c->current_user_has_write_access;
  my $roles        = $c->current_user_roles;

  my $filtered = [];
  for my $tool (@$tools) {
    my $name = $tool->name;
    if (my $check = $WRITE_TOOL_ROLES->{$name}) {
      next unless $write_access;
      next unless grep { $check->{$_} } @$roles;
    }
    push @$filtered, $tool;
  }

  @$tools = @$filtered;
}

sub _get_controller ($tool) { $tool->context->{controller} }

1;
