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

package Cavil::Util;
use Mojo::Base -strict, -signatures;

use Carp 'croak';
use Exporter 'import';
use Encode   qw(from_to decode);
use IPC::Run ();
use Mojo::Util;
use Mojo::DOM;
use Mojo::File qw(path tempfile);
use POSIX 'ceil';
use Spooky::Patterns::XS;
use Text::Glob 'glob_to_regex';
use Try::Tiny;

$Text::Glob::strict_wildcard_slash = 0;

our @EXPORT_OK = (
  qw(buckets file_and_checksum slurp_and_decode load_ignored_files lines_context obs_ssh_auth paginate),
  qw(parse_exclude_file parse_service_file pattern_checksum pattern_matches read_lines request_id_from_external_link),
  qw(run_cmd snippet_checksum ssh_sign)
);

my $MAX_FILE_SIZE = 30000;

# Service modes that guarantee checkouts are complete and not amended by the OBS server
my $SAFE_OBS_SRVICE_MODES = {buildtime => 1, localonly => 1, manual => 1, disabled => 1};

sub buckets ($things, $size) {

  my $buckets    = int(@$things / $size) || 1;
  my $per_bucket = ceil @$things / $buckets;
  my @buckets;
  for my $thing (@$things) {
    push @buckets,        [] unless @buckets;
    push @buckets,        [] if @{$buckets[-1]} >= $per_bucket;
    push @{$buckets[-1]}, $thing;
  }

  return \@buckets;
}

sub file_and_checksum ($path, $first_line, $last_line) {
  my %lines;
  for (my $line = $first_line; $line <= $last_line; $line += 1) {
    $lines{$line} = 1;
  }

  my $ctx = Spooky::Patterns::XS::init_hash(0, 0);

  my $text = '';
  for my $row (@{Spooky::Patterns::XS::read_lines($path, \%lines)}) {
    my $line = $row->[2] . "\n";
    $text .= $line;
    $ctx->add($line);
  }

  # note that the hash is accounting with the newline included
  chop $text;

  my $hash = $ctx->hex;

  return ($text, $hash);
}

sub pattern_checksum ($text) {
  Spooky::Patterns::XS::init_matcher();
  my $a   = Spooky::Patterns::XS::parse_tokens($text);
  my $ctx = Spooky::Patterns::XS::init_hash(0, 0);
  for my $n (@$a) {

    # map the skips to each other
    $n = 99 if $n < 99;
    my $s = pack('q', $n);
    $ctx->add($s);
  }

  return $ctx->hex;
}

sub run_cmd ($dir, $cmd) {
  my $cwd = path;
  chdir $dir;
  my $guard = Mojo::Util::scope_guard sub { chdir $cwd };

  try {
    my ($stdin, $stdout, $stderr) = ('', '', '');
    my $success = IPC::Run::run($cmd, \$stdin, \$stdout, \$stderr);
    my $status  = $?;
    return {status => $success, exit_code => $status >> 8, stdout => $stdout, stderr => $stderr};
  }
  catch {
    return {status => 0, exit_code => undef, stdout => '', stderr => $_ // 'Unknown error'};
  }
  finally {
    undef $guard;
  };
}

sub snippet_checksum ($text) {
  my $ctx = Spooky::Patterns::XS::init_hash(0, 0);
  $ctx->add($text);
  return $ctx->hex;
}

sub slurp_and_decode ($path) {

  open my $file, '<', $path or croak qq{Can't open file "$path": $!};
  croak qq{Can't read from file "$path": $!} unless defined(my $ret = $file->sysread(my $content, $MAX_FILE_SIZE, 0));

  return $content if -s $path > $MAX_FILE_SIZE;
  return Mojo::Util::decode('UTF-8', $content) // $content;
}

sub _line_tag ($line) {
  return $line->[1]->{pid} if defined $line->[1]->{pid};

  # the actual value does not matter - as long as it differs between snippets
  return -1 - $line->[1]->{snippet} if defined $line->[1]->{snippet};
  return 0;
}

# small helper to simplifying the view code
# this adds to the line infos where the matches end and
# what's next
sub lines_context ($lines) {
  my $last;
  my $currentstart;
  my @starts;
  for my $line (@$lines) {
    if ($last && ($line->[0] - $last->[0]) > 1) {
      $line->[1]->{withgap} = 1;
    }
    my $linetag = _line_tag($line);
    if (_line_tag($last) != $linetag) {
      $currentstart->[1]->{end} = $last->[0] if $currentstart;
      if ($linetag) {
        push(@starts, $line);
        $currentstart = $line;
      }
      else {
        $currentstart = undef;
      }
    }
    $last = $line;
  }
  $currentstart->[1]->{end} = $last->[0] if $currentstart && $last;
  my $prevstart;
  for my $start (@starts) {
    if ($prevstart) {
      $prevstart->[1]->{nextend} = $start->[1]->{end};
      $start->[1]->{prevstart}   = $prevstart->[0];
    }
    $prevstart = $start;
  }

  return $lines;
}

sub load_ignored_files ($db) {
  my %ignored_file_res = map { $_->[0] => glob_to_regex($_->[0]) } @{$db->select('ignored_files', 'glob')->arrays};
  return \%ignored_file_res;
}

sub obs_ssh_auth ($challenge, $user, $key) {
  die "Unexpected OBS challenge: $challenge" unless $challenge =~ /realm="([\w ]+)".*headers="\(created\)"/;
  my $realm = $1;

  my $now       = time;
  my $signature = ssh_sign($key, $realm, "(created): $now");

  return qq{Signature keyId="$user",algorithm="ssh",signature="$signature",headers="(created)",created="$now"};
}

sub paginate ($results, $options) {
  my $total = @$results ? $results->[0]{total} : 0;
  delete $_->{total} for @$results;
  return {total => $total, start => $options->{offset} + 1, end => $options->{offset} + @$results, page => $results};
}

sub parse_exclude_file ($path, $name) {
  my $content = path($path)->slurp;
  my $exclude = [];

  for my $line (split "\n", $content) {
    next unless $line =~ /^\s*([^\s\#]\S+)\s*:\s*(\S+)(?:\s.*)?$/;
    my ($pattern, $file) = ($1, $2);

    next unless $name =~ glob_to_regex($pattern);

    push @$exclude, $file;
  }

  return $exclude;
}

sub parse_service_file ($file) {
  my $dom = Mojo::DOM->new($file);

  my $services = [];
  for my $node ($dom->find('services service[name]')->each) {
    my $name = $node->attr('name');
    my $mode = $node->attr('mode') // 'Default';
    my $safe = $SAFE_OBS_SRVICE_MODES->{$mode} ? 1 : 0;
    push @$services, {name => $name, mode => $mode, safe => $safe};
  }

  return $services;
}

sub pattern_matches ($pattern, $text) {
  my $matcher = Spooky::Patterns::XS::init_matcher();
  my $parsed  = Spooky::Patterns::XS::parse_tokens($pattern);
  $matcher->add_pattern(1, $parsed);

  my $file    = tempfile->spew("ABC\n$text\nABC\n", 'UTF-8');
  my $matches = !!@{$matcher->find_matches($file)};
  undef $file;

  return $matches;
}

sub read_lines ($path, $start_line, $end_line) {
  my %needed_lines;
  for (my $line = $start_line; $line <= $end_line; $line += 1) {
    $needed_lines{$line} = 1;
  }

  my $text = '';
  for my $row (@{Spooky::Patterns::XS::read_lines($path, \%needed_lines)}) {
    my ($index, $pid, $line) = @$row;

    # Sanitize line - first try UTF-8 strict and then LATIN1
    eval { $line = decode 'UTF-8', $line, Encode::FB_CROAK; };
    if ($@) {
      from_to($line, 'ISO-LATIN-1', 'UTF-8', Encode::FB_DEFAULT);
      $line = decode 'UTF-8', $line, Encode::FB_DEFAULT;
    }
    $text .= "$line\n";
  }
  return $text;
}

sub request_id_from_external_link ($link) {
  return $1 if $link =~ /^(?:obs|ibs)#(\d+)$/;
  return undef;
}

# Based on https://www.suse.com/c/multi-factor-authentication-on-suses-build-service/
sub ssh_sign ($key, $realm, $value) {

  # This needs to be a bit portable for CI testing
  my $tmp   = tempfile->spew($value);
  my @lines = split "\n", qx/ssh-keygen -Y sign -f "$key" -q -n "$realm" < $tmp/;
  shift @lines;
  pop @lines;
  return join '', @lines;
}

1;
