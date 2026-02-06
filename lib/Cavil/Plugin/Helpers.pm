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

use Cavil::Licenses 'lic';
use Mojo::File 'path';
use Mojo::JSON 'to_json';
use Mojo::Util qw(decode humanize_bytes xml_escape);
use List::Util qw(first uniq);

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
  $app->helper('reply.json_validation_error'   => \&_json_validation_error);
  $app->helper('format_file'                   => \&_format_file);
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
    unmatched_keywords => _unmatched_keywords($report)
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
  my ($shortname)     = $report =~ /:(\w+)$/;

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

  my (%docs, %lics, @package_files);
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
  }

  return {
    actions           => $actions,
    copied_files      => {'%doc' => [sort keys %docs], '%license' => [sort keys %lics]},
    created           => $pkg->{created_epoch},
    embargoed         => \!!$pkg->{embargoed},
    ai_assisted       => \!!$pkg->{ai_assisted},
    errors            => $spec->{errors} // [],
    external_link     => $pkg->{external_link},
    has_spdx_report   => \!!$has_spdx_report,
    history           => $history,
    id                => $pkg->{id},
    notice            => $pkg->{notice},
    package_checksum  => $pkg->{checkout_dir},
    package_files     => \@package_files,
    package_group     => $group,
    package_license   => {name => $package_license, spdx => \!!$normalized_license},
    package_name      => $pkg->{name},
    package_priority  => $pkg->{priority},
    package_shortname => $shortname,
    package_summary   => $summary,
    package_type      => $type,
    package_url       => $url,
    package_version   => $version,
    products          => $products,
    requests          => $requests,
    result            => $pkg->{result},
    reviewed          => $pkg->{reviewed_epoch},
    reviewing_user    => $pkg->{login},
    state             => $pkg->{state},
    unpacked_files    => $pkg->{unpacked_files},
    unpacked_size     => humanize_bytes($pkg->{unpacked_size} // 0),
    warnings          => $spec->{warnings} // []
  };
}

sub _unmatched_keywords ($report) {
  my $unmatched = {};
  for my $file (@{$report->{files}}) {
    next unless $file->{expand};
    my $path = $file->{path};

    for my $line (@{$file->{lines}}) {
      next unless $line->[1]->{risk} == 9;
      my $snippet = $line->[1]->{snippet};
      my $hash    = $line->[1]->{hash};

      $unmatched->{$snippet} //= {path => $path, snippet => $snippet, hash => $hash, lines => []};
      push @{$unmatched->{$snippet}->{lines}}, [$line->[0], $line->[2]];
    }
  }

  return [sort { $a->{snippet} cmp $b->{snippet} } values %$unmatched];
}

1;
