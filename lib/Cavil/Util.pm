# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

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

our @EXPORT_OK = (
  qw(buckets file_and_checksum slurp_and_decode load_ignored_files lines_context normalize_license_expr),
  qw(extract_spdx_identifiers normalize_license_text obs_ssh_auth paginate parse_exclude_file parse_service_file pattern_checksum),
  qw(pattern_matches pattern_contains_redundant_skip read_lines request_id_from_external_link run_cmd),
  qw(external_link_data snippet_checksum spdx_link ssh_sign text_shingles validate_tags weighted_containment),
  qw(license_is_catch_all SNIPPET_SCORE_VERSION),
  qw(@SPDX_LICENSES @SPDX_EXCEPTIONS @SCANCODE_LICENSES)
);

# Bumped whenever the snippet similarity scorer's semantics change. snippets carry the version they
# were scored with; fold-in only trusts rows scored by the *current* version, so a scorer change (or
# rows scored before a full rescore) can never silently fold on stale scoring.
use constant SNIPPET_SCORE_VERSION => 2;    # v2: markup normalization (C/line-number/groff stripping)

my $MAX_FILE_SIZE = 30000;
use constant MAX_TAG_LENGTH => 32;
use constant MAX_TAGS       => 16;

# Service modes that guarantee checkouts are complete and not amended by the OBS server
my $SAFE_OBS_SRVICE_MODES = {buildtime => 1, localonly => 1, manual => 1, disabled => 1};

# According to Adrian, this is the only exception currently
my $SAFE_OBS_SRVICE_NAMES = {product_converter => 1};

# Licenses and exceptions are updated with "perl tools/update_licenses.pl"
our @SPDX_LICENSES     = split "\n", path(__FILE__)->dirname->child('resources', 'license_list.txt')->slurp;
our @SPDX_EXCEPTIONS   = split "\n", path(__FILE__)->dirname->child('resources', 'license_exceptions.txt')->slurp;
our @SCANCODE_LICENSES = split "\n", path(__FILE__)->dirname->child('resources', 'license_list_scancode.txt')->slurp;

my %SPDX_IDENTIFIER_CANONICAL = map { lc($_) => $_ } @SPDX_LICENSES;
my $SPDX_IDENTIFIER_RE        = do {
  my $identifiers = join '|', map {quotemeta} sort { length $b <=> length $a || $a cmp $b } @SPDX_LICENSES;
  qr/(?<![\w.+-])($identifiers)(?![\w.+-])/i;
};

# A "catch-all" license is a grab-bag / marker pseudo-license rather than a concrete, identifiable
# one: the "Any ..." vocabulary (Any Permissive, Any reference local, ...), the version-less
# "*-Unspecified" families (GPL-Unspecified, "LGPL Unspecified"), and the "All Rights Reserved" /
# "Public-Domain" markers. This is the seed rule for the license_patterns.catch_all flag; it mirrors
# the SQL backfill in migrations/cavil.sql. Composite expressions ending in "Unspecified" (e.g.
# "MIT OR BSD-Unspecified") are swept in too, which is the safe direction for the "covered" gate
# (they simply do not count as coverage), and can be hand-corrected on the license afterwards.
sub license_is_catch_all ($license) {
  return 0 unless defined $license && length $license;
  return 1 if $license =~ /^Any /;
  return 1 if $license =~ /Unspecified$/;
  return 1 if $license eq 'All Rights Reserved' || $license eq 'Public-Domain';
  return 0;
}

sub extract_spdx_identifiers ($string) {
  return [] unless defined $string;

  my @identifiers;
  while ($string =~ /$SPDX_IDENTIFIER_RE/g) {
    push @identifiers, $SPDX_IDENTIFIER_CANONICAL{lc $1} // $1;
  }

  return \@identifiers;
}

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

# Normalize license-ish text for *similarity* comparison (not for storing as a pattern). Removes
# the noise that parse_tokens would otherwise keep as tokens (markup, comment leaders, and
# copyright/author/url/email lines), following the spirit of the SPDX matching guidelines. Case
# folding and punctuation stripping are left to parse_tokens, which already does them.
sub normalize_license_text ($text) {
  $text =~ s/<[^>]+>/ /g;                                      # html tags
  $text =~ s/&[a-zA-Z][a-zA-Z0-9]*;|&#\d+;/ /g;                # html entities
  $text =~ s{/\*+|\*+/}{ }g;                                   # C/C++ block comment delimiters
  $text =~ s/\b0\d{4,}\b/ /g;                                  # doxygen-style zero-padded line numbers
  $text =~ s{^[ \t]*\d{1,6}(?![.)])[ \t]+}{}gm;                # source-listing line numbers (keep "4." clauses)
  $text =~ s{^[ \t]*(?:[*#;>|=-]+|//+|dnl|rem)[ \t]?}{}gim;    # comment / markup leaders (now-exposed marker)
  $text =~ s/\\f[A-Z]|\\f\([A-Za-z]{2}|\\&//g;                 # groff/man font escapes
  $text =~ s{^[ \t]*\.\\"[ \t]?}{}gm;    # groff/man comment leader (keep the text; man licenses live in .\" comments)

  my @keep;
  for my $line (split /\n/, $text) {

    # Drop variable noise that does not identify a license
    next if $line =~ /copyright|\(c\)|\x{00a9}|all rights reserved/i;
    next if $line =~ /[\w.+-]+@[\w.-]+\.\w+/;                           # emails
    next if $line =~ m{https?://};                                      # urls
    push @keep, $line;
  }

  $text = join "\n", @keep;
  $text =~ s/\s+/ /g;
  $text =~ s/^\s+|\s+$//g;
  return $text;
}

# Set of token-shingles (k consecutive normalized tokens) for similarity scoring. Returns a hashref
# keyed by shingle so callers can do set overlap / containment. Reuses the Spooky tokenizer so the
# vocabulary matches the bag-of-patterns engine. Very short texts fall back to unigrams so that
# one-line declarations still compare.
sub text_shingles ($text, $k = 3) {
  Spooky::Patterns::XS::init_matcher();
  my $toks = Spooky::Patterns::XS::parse_tokens(normalize_license_text($text));

  my %shingles;
  if (@$toks < $k) {
    $shingles{$_} = 1 for @$toks;
    return \%shingles;
  }
  for my $i (0 .. @$toks - $k) {
    $shingles{join ',', @{$toks}[$i .. $i + $k - 1]} = 1;
  }
  return \%shingles;
}

# IDF-weighted containment of $snippet within $reference (both shingle sets from text_shingles).
# Containment (asymmetric) because a snippet is usually a *fragment* of a license. $idf maps a
# shingle to its weight (rare, license-specific shingles weigh more); missing shingles default to 1.
sub weighted_containment ($snippet, $reference, $idf = {}) {
  my ($hit, $total) = (0, 0);
  for my $shingle (keys %$snippet) {
    my $w = $idf->{$shingle} // 1;
    $total += $w;
    $hit   += $w if $reference->{$shingle};
  }
  return $total > 0 ? $hit / $total : 0;
}

sub slurp_and_decode ($path) {

  open my $file, '<', $path or croak qq{Can't open file "$path": $!};
  croak qq{Can't read from file "$path": $!} unless defined(my $ret = $file->sysread(my $content, $MAX_FILE_SIZE, 0));

  return $content if -s $path > $MAX_FILE_SIZE;
  return Mojo::Util::decode('UTF-8', $content) // $content;
}

sub _spdx_link ($match) {
  return qq{<a class="spdx-link" target="_blank" href="https://spdx.org/licenses/$match.html">$match</a>};
}

sub spdx_link ($text) {
  state $spdx_re = join '|', map {quotemeta} sort { length($b) <=> length($a) } (@SPDX_LICENSES, @SPDX_EXCEPTIONS);

  # Wrap recognised SPDX identifiers in links, but HTML-escape everything else. The input can be a
  # license string harvested from an imported component's metadata, and the result is rendered with
  # v-html, so any non-link text must be escaped or it becomes a stored XSS vector. Only the matched
  # tokens (known SPDX ids) are emitted as trusted markup.
  my @parts    = split /($spdx_re)/o, $text;
  my $is_token = 0;
  my $out      = '';
  for my $part (@parts) {
    $out .= $is_token ? _spdx_link($part) : Mojo::Util::xml_escape($part);
    $is_token = !$is_token;
  }
  return $out;
}

sub _expand_external_link_url ($template, @captures) {
  $template =~ s/\$(\d+)/defined $captures[$1 - 1] ? $captures[$1 - 1] : ''/ge;
  return $template;
}

sub external_link_data ($link, $sources = undef) {
  return undef unless defined $link;

  $sources = [] unless ref $sources eq 'ARRAY';
  for my $source (@$sources) {
    next unless my $pattern = $source->{pattern};
    my @captures = $link =~ /$pattern/;
    next unless @captures;

    my $data     = {text => $link};
    my $template = $source->{url};
    if (defined $template && length $template) {
      $data->{url}   = _expand_external_link_url($template, @captures);
      $data->{title} = $source->{title} // 'External link';
    }
    $data->{label} = $source->{label} if defined($source->{label}) && length $source->{label};
    return $data;
  }

  return {text => $link};
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
  local $Text::Glob::strict_wildcard_slash = 0;
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

sub validate_tags ($tags) {
  return ([],    undef)                              unless defined $tags;
  return (undef, 'tags must be an array of strings') unless ref $tags eq 'ARRAY';

  my (@clean, %seen);
  for my $tag (@$tags) {
    return (undef, 'tags must be an array of strings') if ref $tag || !defined $tag;
    my $trimmed = $tag;
    $trimmed =~ s/^\s+|\s+$//g;
    next                                                            if $trimmed eq '';
    return (undef, 'tag exceeds ' . MAX_TAG_LENGTH . ' characters') if length($trimmed) > MAX_TAG_LENGTH;
    next                                                            if $seen{$trimmed}++;
    push @clean, $trimmed;
  }
  return (undef,   'too many tags, maximum is ' . MAX_TAGS) if @clean > MAX_TAGS;
  return (\@clean, undef);
}

sub paginate ($results, $options) {
  my $total = @$results ? $results->[0]{total} : 0;
  delete $_->{total} for @$results;
  return {total => $total, start => $options->{offset} + 1, end => $options->{offset} + @$results, page => $results};
}

sub parse_exclude_file ($path, $name) {
  my $content = path($path)->slurp;
  my $exclude = [];

  local $Text::Glob::strict_wildcard_slash = 0;
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
    my $safe = $SAFE_OBS_SRVICE_MODES->{$mode} || $SAFE_OBS_SRVICE_NAMES->{$name} ? 1 : 0;
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

sub pattern_contains_redundant_skip ($pattern) {
  return $pattern =~ /^\s*\$SKIP/ || $pattern =~ /\$SKIP\d*\s*$/;
}

# Normalize a license expression for matching: lower-case, collapse whitespace, drop "LicenseRef-"
# prefixes, treat a trailing "+" as the SPDX "-or-later", and sort the operands of a flat "OR" list
# (which is commutative, unlike "AND"/"WITH" or anything with parentheses)
sub normalize_license_expr ($expr) {
  my $norm = lc $expr;
  $norm =~ s/^\s+|\s+$//g;
  $norm =~ s/\s+/ /g;
  return '' if $norm eq '';
  $norm =~ s/licenseref-//g;
  $norm =~ s/\+(?=\s|$)/-or-later/g;
  if ($norm !~ /[()]/ && $norm !~ /\band\b/ && $norm !~ /\bwith\b/ && $norm =~ /\bor\b/) {
    $norm = join ' or ', sort split / or /, $norm;
  }
  return $norm;
}

sub read_lines ($path, $start_line, $end_line, $with_line_numbers = 0) {
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

    # Prefix the absolute line number for reference (display-only, must not leak into patterns/snippets)
    $text .= $with_line_numbers ? sprintf("%6d  %s\n", $index, $line) : "$line\n";
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
