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

package Cavil::Plugin::Helpers;
use Mojo::Base 'Mojolicious::Plugin', -signatures;

use Cavil::Licenses   qw(lic);
use Cavil::ReportUtil qw(minimal_snippet);
use Cavil::Util       qw(spdx_link);
use CommonMark        ();
use Mojo::File        qw(path);
use Mojo::JSON        qw(to_json);
use Mojo::Util        qw(decode humanize_bytes xml_escape);
use List::Util        qw(first uniq);

sub register ($self, $app, $config) {
  $app->helper('chart_data'                    => \&_chart_data);
  $app->helper('current_user'                  => \&_current_user);
  $app->helper('current_user_roles'            => \&_current_user_roles);
  $app->helper('current_user_has_role'         => \&_current_user_has_role);
  $app->helper('current_user_has_write_access' => \&_current_user_has_write_access);
  $app->helper('lic'                           => sub { shift; lic(@_) });
  $app->helper('maybe_utf8'                    => sub { decode('UTF-8', $_[1]) // $_[1] });
  $app->helper('mcp_report'                    => \&_mcp_report);
  $app->helper('package_summary'               => \&_package_summary);
  $app->helper('proposal_stats'                => sub { shift->patterns->proposal_stats });
  $app->helper('report_details'                => \&_report_details);
  $app->helper('reply.json_validation_error'   => \&_json_validation_error);
  $app->helper('format_file'                   => \&_format_file);
  $app->helper('markdown_to_safe_html'         => \&_markdown_to_safe_html);
}

sub _markdown_to_safe_html ($c, $text) {
  return '' unless defined $text && length $text;

  # OPT_SAFE strips raw HTML and dangerous URL schemes (javascript:, data:, vbscript:).
  return CommonMark->markdown_to_html($text, CommonMark::OPT_SAFE());
}

sub _chart_data ($c, $hash) {
  my (@licenses, @num_files, @colours);

  my @codes = ('#117864', '#85c1e9', '#9b59b6', '#ec7063', '#a3e4d7', '#c39bd3', '#c0392b');

  my @sorted_keys = sort { $hash->{$b} <=> $hash->{$a} } keys %$hash;
  while (@sorted_keys) {
    my $first = shift @sorted_keys;
    push(@licenses,  "$first: $hash->{$first} files");
    push(@num_files, $hash->{$first});
    push(@colours,   shift @codes);
    delete $hash->{$first};
    last unless @codes;
  }

  my $rest = 0;

  # TODO - we will count files multiple times
  for my $lic (@sorted_keys) {
    $rest += $hash->{$lic};
  }
  if ($rest) {
    push(@licenses,  "Misc: $rest files");
    push(@num_files, $rest);
    push(@colours,   'grey');
  }
  return {licenses => to_json(\@licenses), 'num-files' => to_json(\@num_files), colours => to_json(\@colours)};
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

  my $risks = $report->{risks} // {};
  my %risk_buckets;
  for my $risk (keys %$risks) {
    my @licenses;
    my $bucket = $risks->{$risk};
    for my $lic (sort keys %$bucket) {
      my $matches = $bucket->{$lic};
      my $display = $matches->{spdx} || $matches->{name};
      push @licenses,
        {
        name      => $matches->{name},
        spdx      => $matches->{spdx},
        name_html => spdx_link($display),
        flags     => $matches->{flags} // [],
        files     => $matches->{files}
        };
    }
    $risk_buckets{$risk} = \@licenses;
  }

  my @missed;
  for my $f (@{$report->{missed_files} // []}) {
    my %copy = %$f;
    $copy{license_html} = spdx_link($f->{spdx} || $f->{license});
    push @missed, \%copy;
  }

  return {
    package               => {id => $pkg->{id}, name => $pkg->{name}, unresolved_matches => $pkg->{unresolved_matches}},
    chart                 => $chart,
    incompatible_licenses => $report->{incompatible_licenses} // [],
    missed_files          => \@missed,
    risks                 => \%risk_buckets,
    max_files_per_license => $max,
    max_expanded_files    => $expand_limit,
    hidden_inline_previews => $hidden_inline,
    matching_globs         => $report->{matching_globs} // [],
    files                  => \@files,
    emails                 => $report->{emails} // [],
    urls                   => $report->{urls}   // []
  };
}

sub _current_user ($c) { $c->stash->{'cavil.api.user'} // $c->session('user') }

sub _current_user_has_role ($c, @roles) {
  return undef unless my $user = $c->helpers->current_user;
  return $c->users->has_role($user, @roles);
}

sub _current_user_has_write_access ($c) { $c->stash->{'cavil.api.write_access'} ? 1 : 0 }

sub _current_user_roles ($c) {
  return [] unless my $user = $c->helpers->current_user;
  return $c->users->roles($user);
}

sub _json_validation_error ($c) {
  my $failed = join ', ', @{$c->validation->failed};
  $c->render(json => {error => "Invalid request parameters ($failed)"}, status => 400);
}

sub _mcp_report ($c, $id) {
  return undef unless my $report = $c->reports->sanitized_dig_report($id);
  my $summary = $c->helpers->package_summary($id);
  return $c->render_to_string(
    'mcp/report',
    format             => 'txt',
    report             => $report,
    summary            => $summary,
    unmatched_keywords => _unmatched_keywords($c, $report)
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

  my $has_spdx_report = $pkgs->has_spdx_report($id);
  my $report          = $pkg->{checksum} // '';
  my ($risk, $shortname) = $report =~ /-(\d+):(\w+)$/;

  $risk = 9 if ($pkg->{unresolved_matches} || 0) > 0;

  my $requests = $pkgs->requests_for($id);
  my $products = $c->products->for_package($id);

  my $history = [];
  for my $prev (@{$pkgs->history($pkg->{name}, $pkg->{checksum}, $id)}) {
    my $entry = {
      created        => $prev->{created_epoch},
      external_link  => $prev->{external_link},
      id             => $prev->{id},
      result         => $prev->{result} // '',
      reviewing_user => $prev->{login}  // '',
      state          => $prev->{state}
    };
    push @$history, $entry;
  }

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
    has_spdx_report      => \!!$has_spdx_report,
    history              => $history,
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
    requests             => $requests,
    result               => $pkg->{result},
    reviewed             => $pkg->{reviewed_epoch},
    reviewing_user       => $pkg->{login},
    state                => $pkg->{state},
    unpacked_files       => $pkg->{unpacked_files},
    unpacked_size        => humanize_bytes($pkg->{unpacked_size} // 0),
    warnings             => $spec->{warnings} // []
  };
}

sub _unmatched_keywords ($c, $report) {
  my $snippets = $c->snippets;

  my $unmatched = {};
  for my $file (@{$report->{files}}) {
    next unless $file->{expand};
    my $path = $file->{path};

    for my $line (@{$file->{lines}}) {
      next unless $line->[1]->{risk} == 9;
      my $snippet = $line->[1]->{snippet};
      my $hash    = $line->[1]->{hash};

      my $minimal = minimal_snippet($snippets->with_context($snippet));
      $unmatched->{$snippet} ||= {path => $path, snippet => $snippet, hash => $hash, text => $minimal->{text},
        line => $minimal->{start_line}};
    }
  }

  return [sort { $a->{snippet} cmp $b->{snippet} } values %$unmatched];
}

1;
