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

  my $report = $self->_dig_report({}, $pkg, \%ignored_lines);

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
  my $lines        = $self->_lines({}, $fn, \%needed_lines);

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
  my ($self, $report, $file, $ignored_lines, $matches_to_ignore) = @_;

  my $lastline = '';
  my @clines   = @{$report->{lines}{$file}};
  my $line     = shift @clines;

  while ($line || @clines) {
    if ($line->[1]{risk} == 9) {
      my @marks;
      push(@marks, $line);
      my $ctx = Spooky::Patterns::XS::init_hash(0, 0);
      $ctx->add("$lastline\n");
      $ctx->add("$line->[2]\n");
      while ($line = shift @clines) {
        $lastline = $line->[2];
        $ctx->add("$lastline\n");
        last if $line->[1]{risk} != 9;
        push(@marks, $line);
      }
      my $hex = $ctx->hex;
      if (defined $ignored_lines->{$hex}) {
        map { $matches_to_ignore->{$report->{matches}{$file}{$_->[0]}} = 1 }
          @marks;
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

sub _dig_report {
  my ($self, $pid_info, $pkg, $ignored_lines) = @_;

  my $db = $self->pg->db;

  my $report = {};
  my $files
    = $db->select('matched_files', [qw(id filename)], {package => $pkg->{id}});

  while (my $file = $files->hash) {
    $report->{files}{$file->{id}} = $file->{filename};
  }

  my $matches = $db->select(
    'pattern_matches',
    [qw(id file pattern sline eline)],
    {package => $pkg->{id}, ignored => 0}
  );

  my $snippets = $db->select(
    ['snippets', ['file_snippets', snippet => 'id']],
    ['file', 'sline', 'eline'],
    {
      package               => $pkg->{id},
      'snippets.classified' => 1,
      'snippets.license'    => 0
    },
    {order_by => 'sline'}
  );
  my %file_snippets;
  for my $snip_row (@{$snippets->hashes}) {
    $file_snippets{$snip_row->{file}} ||= [];
    push(
      @{$file_snippets{$snip_row->{file}}},
      [$snip_row->{sline}, $snip_row->{eline}]
    );
  }

  my $expanded_limit = $self->max_expanded_files;
  my $num_expanded   = 0;

  my %matches_to_ignore;

  while (my $match = $matches->hash) {
    my $pid = $match->{pattern};

    my $part_of_snippet;
    for my $region (@{$file_snippets{$match->{file}}}) {
      my ($first_line, $last_line) = @$region;
      if ($match->{sline} >= $first_line && $match->{eline} <= $last_line) {
        $part_of_snippet = 1;
        $matches_to_ignore{$match->{id}} = 1;
        last;
      }
    }
    next if $part_of_snippet;
    my $pattern = $self->_load_pattern_from_cache($pid);
    my $license = $self->_load_license_from_cache($pattern->{license});

    $report->{licenses}{$license->{id}} ||= $license;
    $report->{licenses}{$license->{id}}{flaghash}{$_} ||= $pattern->{$_}
      for qw(patent trademark opinion);
    $report->{flags}{eula}    = 1 if $license->{eula};
    $report->{flags}{nonfree} = 1 if $license->{nonfree};

    my $rl = $report->{risks}{$license->{risk}};
    push(@{$rl->{$license->{id}}{$pid}}, $match->{file});
    $report->{risks}{$license->{risk}} = $rl;
    if ($license->{risk} == 9 && $num_expanded++ < $expanded_limit) {
      $report->{expanded}{$match->{file}} = 1;
    }

    $pid_info->{$pid}
      = {risk => $license->{risk}, name => $license->{name}, pid => $pid};

    my $risk = $license->{risk};

    for (my $i = $match->{sline} - 3; $i <= $match->{eline} + 3; $i++) {
      next if $i < 1;
      if ($i >= $match->{sline} && $i <= $match->{eline}) {

        my $opid = $report->{needed_lines}{$match->{file}}{$i} // 0;

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
      = $self->_lines($pid_info, $fn, $report->{needed_lines}{$file});
    $self->_check_ignores($report, $file, $ignored_lines, \%matches_to_ignore);
  }

  # in case ignored lines found unignored matches (i.e. first load), update them
  # and restart the report
  for my $mig (keys %matches_to_ignore) {
    $db->update('pattern_matches', {ignored => 1}, {id => $mig});
  }

  if (%matches_to_ignore) {
    return $self->_dig_report($pid_info, $pkg, $ignored_lines);
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
  my ($self, $pid_info, $pid) = @_;
  return {risk => 0} unless $pid;

  if (!defined $pid_info->{$pid}) {
    my $match   = $self->_load_pattern_from_cache($pid);
    my $license = $self->_load_license_from_cache($match->{license});
    $pid_info->{$pid}
      = {risk => $license->{risk}, name => $license->{name}, pid => $pid};
  }
  return $pid_info->{$pid};
}

sub _lines {
  my ($self, $pid_info, $fn, $needed_lines) = @_;

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
    push(@lines, [$index, $self->_info_for_pattern($pid_info, $pid), $line]);
  }

  return \@lines;
}

sub _load_license_from_cache {
  my ($self, $lid) = @_;
  $self->{license_cache}->{"license-$lid"}
    ||= $self->pg->db->select('licenses', '*', {id => $lid})->hash;
  return $self->{license_cache}->{"license-$lid"};
}

sub _load_pattern_from_cache {
  my ($self, $pid) = @_;
  $self->{license_cache}->{"pattern-$pid"}
    ||= $self->pg->db->select('license_patterns', '*', {id => $pid})->hash;
  return $self->{license_cache}->{"pattern-$pid"};
}

1;
