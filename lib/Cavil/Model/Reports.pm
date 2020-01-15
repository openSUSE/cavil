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

package Cavil::Model::Reports;
use Mojo::Base -base;

use Encode qw(from_to decode);
use Mojo::File 'path';
use Mojo::JSON qw(from_json to_json);
use Spooky::Patterns::XS;
use Cavil::Checkout;

has [qw(acceptable_risk checkout_dir max_expanded_files pg)];

# we need a HUGE number because Spooky uses unsigned integers
my $pattern_delta = 10000000000;

sub cached_dig_report {
  my ($self, $id) = @_;
  return $self->pg->db->select('bot_reports', 'ldig_report', {package => $id})
    ->hash->{ldig_report};
}

sub dig_report {
  my ($self, $id) = @_;

  my $db  = $self->pg->db;
  my $pkg = $db->select('bot_packages', '*', {id => $id})->hash;
  my $ignored
    = $db->select('ignored_lines', 'hash', {packname => $pkg->{name}});
  my %ignored_lines = map { $_->{hash} => 1 } $ignored->hashes->each;

  my $report = $self->_dig_report($db, {}, $pkg, \%ignored_lines);

  # prune match caches
  delete $report->{matches};
  return $report;
}

sub risk_is_acceptable {
  my ($self, $shortname) = @_;
  return undef unless $shortname =~ /^(.+)-(\d):[^:]+$/;
  return undef if $2 > $self->acceptable_risk;
  return $2;
}

sub source_for {
  my ($self, $id, $needed) = @_;

  my $db   = $self->pg->db;
  my $file = $db->select('matched_files', '*', {id => $id})->hash;
  return undef unless $file;

  my $pkg = $db->select('bot_packages', '*', {id => $file->{package}})->hash;

  my $fn = path(
    $self->{checkout_dir}, $pkg->{name}, $pkg->{checkout_dir},
    '.unpacked',           $file->{filename}
  );
  my %needed_lines = map { $_->[0] => $_->[1] } @$needed;
  my $lines        = $self->_lines($db, {}, $fn, \%needed_lines);

  return {lines => $lines, name => $pkg->{name}};
}

sub specfile_report {
  my ($self, $id) = @_;

  my $db   = $self->pg->db;
  my $hash = $db->select('bot_reports', '*', {package => $id})->hash;

  unless ($hash) {
    return undef
      unless my $pkg = $db->select('bot_packages', '*', {id => $id})->hash;

    my $dir = path($self->checkout_dir, $pkg->{name}, $pkg->{checkout_dir});
    my $checkout = Cavil::Checkout->new($dir);
    my $specfile = $checkout->specfile_report;

    my $report = {package => $id, specfile_report => to_json($specfile)};
    $hash = $db->insert('bot_reports', $report, {returning => '*'})->hash;
  }

  return from_json($hash->{specfile_report});
}

sub _check_ignores {
  my ($self, $report, $file, $ignored_lines, $matches_to_ignore,
    $snippets_to_remove)
    = @_;

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
        my $ctx = Spooky::Patterns::XS::init_hash(0, 0);
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
          $matches_to_ignore->{$freport->{$m->[0]}} = 1;
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
      $snip_row->{sline}, $snip_row->{eline}, $snip_row->{id}, $snip_row->{hash}
    ]
  );
}

sub _dig_report {
  my ($self, $db, $pid_info, $pkg, $ignored_lines) = @_;

  my $ignored_file_res = Cavil::Util::load_ignored_files($db);
  my $report           = {};
  my $files
    = $db->select('matched_files', [qw(id filename)], {package => $pkg->{id}});
  my %globs_matched;

  while (my $file = $files->hash) {
    my $ignored;
    for my $ifre (keys %$ignored_file_res) {
      next unless $file->{filename} =~ $ifre;
      $globs_matched{$ignored_file_res->{$ifre}} = 1;
      $ignored = 1;
      last;
    }
    $report->{files}{$file->{id}} = $file->{filename} unless $ignored;
  }

  # now check the files that were already ignored during indexing
  my $filenames = $db->query(
    'select distinct filename from
                      matched_files mf join pattern_matches pm
                      on pm.file=mf.id where mf.package=?
                      and pm.ignored=true', $pkg->{id}
  );

  while (my $file = $filenames->hash) {
    for my $ifre (keys %$ignored_file_res) {
      next unless $file->{filename} =~ $ifre;
      $globs_matched{$ignored_file_res->{$ifre}} = 1;
      last;
    }
  }
  $filenames->finish;

  $report->{matching_globs} = [keys %globs_matched];

  my $matches = $db->select(
    'pattern_matches',
    [qw(id file pattern sline eline)],
    {package => $pkg->{id}, ignored => 0}
  );

  my $snippets = $db->select(
    ['snippets', ['file_snippets', snippet => 'id']],
    [
      'snippets.id', 'snippets.hash', 'file', 'sline',
      'eline',       'classified',    'license'
    ],
    {package  => $pkg->{id},},
    {order_by => 'sline'}
  );
  my %file_snippets_to_ignore;
  my %file_snippets_to_show;
  my %snippets_shown;

  for my $snip_row (@{$snippets->hashes}) {
    if (!defined $report->{files}{$snip_row->{file}}
      || $snippets_shown{$snip_row->{id}}
      || (!$snip_row->{license} && $snip_row->{classified}))
    {
      _add_to_snippet_hash(\%file_snippets_to_ignore, $snip_row);
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

  for my $file (keys %file_snippets_to_show) {
    last if $num_expanded++ > $expanded_limit;

    $report->{expanded}{$file} = 1;
    for my $snip_row (@{$file_snippets_to_show{$file}}) {
      my ($sline, $eline, $id, $hash) = @$snip_row;
      for (my $i = $sline - 3; $i <= $eline + 3; $i++) {
        next if $i < 1;
        if ($i >= $sline && $i <= $eline) {
          $report->{needed_lines}{$file}{$i} = $pattern_delta + $id;
          $report->{snippets}{$file}{$id}    = $hash;
        }
        else {
          $report->{needed_lines}{$file}{$i} = 0;
        }
      }
    }
  }

  while (my $match = $matches->hash) {
    my $pid = $match->{pattern};

    if (!defined $report->{files}{$match->{file}}) {
      $matches_to_ignore{$match->{id}} = 1;
      next;
    }

    my $part_of_snippet;
    for my $region (@{$file_snippets_to_ignore{$match->{file}}}) {
      my ($first_line, $last_line, $id, $hash) = @$region;
      if ($match->{sline} >= $first_line && $match->{eline} <= $last_line) {
        $part_of_snippet = 1;
        last;
      }
    }
    next if $part_of_snippet;
    my $pattern = $self->_load_pattern_from_cache($db, $pid);
    next if $pattern->{license} eq '';

    $report->{licenses}{$pattern->{license}}
      ||= {name => $pattern->{license}, risk => $pattern->{risk}};
    $report->{licenses}{$pattern->{license}}{flaghash}{$_} ||= $pattern->{$_}
      for qw(patent trademark opinion);
    $report->{flags}{eula}    = 1 if $pattern->{eula};
    $report->{flags}{nonfree} = 1 if $pattern->{nonfree};

    my $rl = $report->{risks}{$pattern->{risk}};
    push(@{$rl->{$pattern->{license}}{$pid}}, $match->{file});
    $report->{risks}{$pattern->{risk}} = $rl;

    $pid_info->{$pid}
      = {risk => $pattern->{risk}, name => $pattern->{license}, pid => $pid};

    my $risk = $pattern->{risk};

    for (my $i = $match->{sline} - 3; $i <= $match->{eline} + 3; $i++) {
      next if $i < 1;
      if ($i >= $match->{sline} && $i <= $match->{eline}) {

        my $opid = $report->{needed_lines}{$match->{file}}{$i} // 0;
        next if $opid > $pattern_delta;

        # set the risk of the line
        # but make sure we do not lower the risk
        next if $risk < $self->_info_for_pattern($pid_info, $opid)->{risk};
        $report->{needed_lines}{$match->{file}}{$i} = $pid;
        $report->{matches}{$match->{file}}{$i}      = $match->{id};
      }
      else {
        # we want context but not highlight the context
        $report->{needed_lines}{$match->{file}}{$i} ||= 0;
      }
    }
  }
  $matches->finish;
  $report->{flags} = [keys %{$report->{flags}}] if $report->{flags};

  for my $license (values %{$report->{licenses}}) {
    my @flags = sort keys %{$license->{flaghash}};
    $license->{flags} = [grep { $license->{flaghash}{$_} } @flags];
    delete $license->{flaghash};
  }

  for my $file (keys %{$report->{files}}) {
    next unless $report->{expanded}{$file};
    my $fn = path(
      $self->checkout_dir, $pkg->{name}, $pkg->{checkout_dir},
      '.unpacked',         $report->{files}{$file}
    );
    $report->{lines}{$file}
      = $self->_lines($db, $pid_info, $fn, $report->{needed_lines}{$file});
    $self->_check_ignores($report, $file, $ignored_lines, \%matches_to_ignore,
      \%snippets_to_remove);
  }

  # in case ignored lines found unignored matches (i.e. first load), update them
  # and restart the report
  for my $mig (keys %matches_to_ignore) {
    $db->update('pattern_matches', {ignored => 1}, {id => $mig});
  }

  if (%matches_to_ignore) {
    return $self->_dig_report($db, $pid_info, $pkg, $ignored_lines);
  }

  if (%snippets_to_remove) {
    for my $id (keys %snippets_to_remove) {
      $db->delete('file_snippets', {snippet => $id, package => $pkg->{id}});
    }
    return $self->_dig_report($db, $pid_info, $pkg, $ignored_lines);
  }
  my $emails = $db->select('emails', '*', {package => $pkg->{id}});
  while (my $email = $emails->hash) {
    my $key = $email->{email};
    if ($email->{name}) {
      $key = "$email->{name} <$email->{email}>";
    }
    $report->{emails}{$key} = $email->{hits};
  }
  my $urls = $db->select('urls', '*', {package => $pkg->{id}});
  while (my $url = $urls->hash) {
    $report->{urls}{$url->{url}} = $url->{hits};
  }

  return $report;
}

sub _info_for_pattern {
  my ($self, $db, $pid_info, $pid) = @_;
  return {risk => 0} unless $pid;

  if (!defined $pid_info->{$pid}) {
    my $pattern = $self->_load_pattern_from_cache($db, $pid);
    $pid_info->{$pid}
      = {risk => $pattern->{risk}, name => $pattern->{license}, pid => $pid};
  }
  return $pid_info->{$pid};
}

sub _lines {
  my ($self, $db, $pid_info, $fn, $needed_lines) = @_;

  my @lines;

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
  for my $row (@{Spooky::Patterns::XS::read_lines($fn, $needed_lines)}) {
    my ($index, $pid, $line) = @$row;

    # Sanitize line - first try UTF-8 strict and then LATIN1
    eval { $line = decode 'UTF-8', $line, Encode::FB_CROAK; };
    if ($@) {
      from_to($line, 'ISO-LATIN-1', 'UTF-8', Encode::FB_DEFAULT);
      $line = decode 'UTF-8', $line, Encode::FB_DEFAULT;
    }
    if ($pid > $pattern_delta) {
      push(
        @lines,
        [
          $index,
          {
            risk    => 9,
            snippet => $pid - $pattern_delta,
            name    => 'Snippet of missing keywords'
          },
          $line
        ]
      );
    }
    else {
      push(@lines,
        [$index, $self->_info_for_pattern($db, $pid_info, $pid), $line]);
    }
  }

  return \@lines;
}

sub _load_pattern_from_cache {
  my ($self, $db, $pid) = @_;
  $self->{license_cache}->{"pattern-$pid"}
    ||= $db->select('license_patterns', '*', {id => $pid})->hash;
  return $self->{license_cache}->{"pattern-$pid"};
}

1;
