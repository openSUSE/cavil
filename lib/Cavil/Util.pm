# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package Cavil::Util;
use Mojo::Base -strict, -signatures;

use Carp 'croak';
use Cpanel::JSON::XS ();
use Digest::MD5      ();
use Exporter 'import';
use Encode   qw(from_to decode);
use IPC::Run ();
use Mojo::Util;
use Mojo::DOM;
use Mojo::File qw(path tempfile);
use POSIX 'ceil';
use Cavil::PatternEngine;
use Text::Glob 'glob_to_regex';
use Try::Tiny;

our @EXPORT_OK = (
  qw(buckets checkout_path expand_spec_macros file_and_checksum fs_bytes md5_file slurp_and_decode load_ignored_files),
  qw(lines_context normalize_license_expr),
  qw(extract_copyrights extract_spdx_identifiers extract_urls_and_emails legal_review_notices),
  qw(normalize_license_text obs_ssh_auth paginate parse_exclude_file),
  qw(parse_service_file pattern_checksum pattern_matches pattern_contains_redundant_skip pattern_contains_skip),
  qw(read_lines run_cmd),
  qw(request_id_from_external_link),
  qw(external_link_data license_link snippet_checksum spdx_identifiers spdx_link spdx_only_expression),
  qw(ssh_sign text_shingles),
  qw(text_shingle_ids),
  qw(validate_tags),
  qw(license_is_catch_all license_text SNIPPET_SCORE_VERSION $COPYRIGHT_LEADER $COPYRIGHT_TOKEN),
  qw(decode_json_fast encode_json_fast to_json_fast),
  qw(incoming_priority PRIORITY_WAITING PRIORITY_INCOMING PRIORITY_UPKEEP PRIORITY_SWEEP),
  qw(@SPDX_LICENSES @SPDX_EXCEPTIONS @SCANCODE_LICENSES @LICENSE_FLAGS @PATTERN_FLAGS)
);

# Legal properties a curator sets on a pattern. The first group states facts about the license and becomes
# SBOM annotations; full_license_text is about one row's text and must stay out of it.
our @LICENSE_FLAGS = qw(patent trademark export_restricted cla eula);
our @PATTERN_FLAGS = (@LICENSE_FLAGS, 'full_license_text');

# What a copyright notice looks like, shared so the harvester and the snippet redactor cannot drift apart
# about which forms count as one. Case sensitive on purpose: a line opening "copyright" or "COPYRIGHT" is
# wrapped license text, never a notice. The leader is one flat character class rather than a nested
# quantifier, which over every line of every package is the classic way to hang a scanner.
our $COPYRIGHT_LEADER = qr{[\s\#*/;!|<>+-]*};
our $COPYRIGHT_TOKEN  = qr{
    SPDX-(?:File|Snippet)CopyrightText:
  | Copyright (?: \s* (?: \(c\) | \(C\) | \x{00a9} ) )?
  | \x{00a9} (?: \s* Copyright )?
  | (?: \(c\) | \(C\) ) \s* Copyright

  # A bare "(c)" is also how a license enumerates its clauses, and Apache-2.0 section 4(c) opens
  # "(c) You must retain, in the Source form ..." in every package that ships the license. A year is
  # what tells the copyright sign from the list marker; the cost is dropping a yearless "(c) Some Name".
  | (?: \(c\) | \(C\) ) (?= \s* \d{4} )
}x;

# Priority gaps keep an entire build within its band as each job increments priority.
use constant {

  # Somebody is sitting in front of the report: the Reindex button, or the package a batch of new
  # patterns was just submitted from
  PRIORITY_WAITING => 80,

  # A new package coming in, shifted up or down by the review priority the request carries
  PRIORITY_INCOMING => 60,

  # Keeping existing reports honest with nobody waiting on the result: the other packages a new pattern
  # touches, a removed pattern or ignored line, a build the cleanup sweep found abandoned
  PRIORITY_UPKEEP => 40,

  # Sweeps over the whole archive: the weekly reindex, the bulk commands
  PRIORITY_SWEEP => 20
};

# Review priority affects only position within the incoming queue band.
sub incoming_priority ($review_priority) {
  my $prio = $review_priority // 5;
  $prio = 1  if $prio < 1;
  $prio = 10 if $prio > 10;
  return PRIORITY_INCOMING + $prio - 5;
}

# Bumped whenever the snippet similarity scorer's semantics change. snippets carry the version they
# were scored with; fold-in only trusts rows scored by the *current* version, so a scorer change (or
# rows scored before a full rescore) can never silently fold on stale scoring.
use constant SNIPPET_SCORE_VERSION => 2;    # v2: markup normalization (C/line-number/groff stripping)

my $MAX_FILE_SIZE = 30000;
use constant MAX_TAG_LENGTH => 32;
use constant MAX_TAGS       => 16;

# Bounds for the copyright harvester, which runs over every file of every package including hostile ones
use constant {
  MAX_COPYRIGHTS       => 100,       # notices kept per file
  MAX_COPYRIGHT_SCAN   => 20_000,    # lines examined per file, whatever the read window allowed
  MAX_COPYRIGHT_FOLLOW => 4,         # continuation lines folded into one notice
  MAX_COPYRIGHT_LENGTH => 1024,      # stored length of one notice
  MAX_COPYRIGHT_SOURCE => 300        # source line length above which this is a minified blob, not a notice
};

# Service modes that guarantee checkouts are complete and not amended by the OBS server
my $SAFE_OBS_SRVICE_MODES = {buildtime => 1, localonly => 1, manual => 1, disabled => 1};

# According to Adrian, this is the only exception currently
my $SAFE_OBS_SRVICE_NAMES = {product_converter => 1};

# Drop-in replacements for Mojo::JSON's encode_json/decode_json/to_json, configured exactly like the
# Cpanel::JSON::XS instances Mojo installs except that they do not sort the keys. Nothing we serialise
# is ever compared or checksummed as text - it is always decoded back into a structure, and
# report_checksum() builds and sorts its own - so the sorting was only ever wasted work. It is also
# actively dangerous: with Cpanel::JSON::XS 4.43 "canonical" never returns for a hash holding two or
# more distinct keys that contain non-ASCII characters (roughly twenty keys in, once the sort leaves
# insertion-sort territory), and we key hashes on filenames and contributor names taken straight out of
# the archive. That is an infinite loop at full CPU with no syscalls in it, so it does not even show up
# under strace. Keep every other flag, in particular allow_dupkeys, or hostile input that used to parse
# starts dying.
my $JSON_BINARY = Cpanel::JSON::XS->new->utf8;
my $JSON_TEXT   = Cpanel::JSON::XS->new;
$_->allow_nonref->allow_unknown->allow_blessed->convert_blessed->stringify_infnan->escape_slash->allow_dupkeys
  for $JSON_BINARY, $JSON_TEXT;

sub decode_json_fast ($bytes) { return $JSON_BINARY->decode($bytes) }
sub encode_json_fast ($data)  { return $JSON_BINARY->encode($data) }
sub to_json_fast     ($data)  { return $JSON_TEXT->encode($data) }

# Licenses and exceptions are updated with "perl tools/update_licenses.pl"
our @SPDX_LICENSES     = split "\n", path(__FILE__)->dirname->child('resources', 'license_list.txt')->slurp;
our @SPDX_EXCEPTIONS   = split "\n", path(__FILE__)->dirname->child('resources', 'license_exceptions.txt')->slurp;
our @SCANCODE_LICENSES = split "\n", path(__FILE__)->dirname->child('resources', 'license_list_scancode.txt')->slurp;

my %SPDX_IDENTIFIER_CANONICAL = map { lc($_) => $_ } @SPDX_LICENSES;
my $SPDX_IDENTIFIER_RE        = do {
  my $identifiers = join '|', map {quotemeta} sort { length $b <=> length $a || $a cmp $b } @SPDX_LICENSES;
  qr/(?<![\w.+-])($identifiers)(?![\w.+-])/i;
};

# A "catch-all" license names nothing anyone could distribute under, and the name has to say so. Two
# naming conventions for two different reasons: the "Any ..." vocabulary (Any Permissive, Any reference
# local, ...) is license-shaped text we decline to identify, and the "-Unspecified" suffix is a family
# whose version the text does not pin down (GPL-Unspecified). Neither counts as coverage for the "covered"
# gate, and neither reaches SPDX output. The name is the only source of truth: license_patterns.catch_all
# is derived from it on every write, so renaming a license is the only way to change the flag.
#
# One placeholder anywhere in an expression makes the whole expression one, whichever side of the operator
# it is on: "MIT OR BSD-Unspecified" and "BSD-Unspecified OR MIT" are the same statement, and an anchored
# rule would have flagged only the first. Being told "MIT, or some BSD" still leaves the BSD unidentified,
# and the fragment that would have named it is exactly what the "covered" gate must not sweep away.
sub license_is_catch_all ($license) {
  return 0 unless defined $license && length $license;
  return $license =~ /(?:^|[\s(])Any / || $license =~ /-Unspecified(?:[\s)]|$)/ ? 1 : 0;
}

# File names are the bytes the filesystem uses, but they reach us through JSON manifests, Minion job
# arguments and text columns, each of which hands back characters. Joining those to anything, or looking
# them up against a name that is still bytes, then silently names no file at all.
sub fs_bytes ($string) {
  utf8::downgrade($string, 1);
  return $string;
}

# Every path inside a checkout goes through here, so a name cannot be bytes on one code path and
# characters on another. It is the flag that matters, not the codepoints: two identical strings name
# different files if one of them carries it, because Perl hands the syscall the UTF-8 encoding instead.
sub checkout_path (@parts) { return path(fs_bytes(path(@parts)->to_string)) }

sub extract_spdx_identifiers ($string) {
  return [] unless defined $string;

  my @identifiers;
  while ($string =~ /$SPDX_IDENTIFIER_RE/g) {
    push @identifiers, $SPDX_IDENTIFIER_CANONICAL{lc $1} // $1;
  }

  return \@identifiers;
}

# RFC-sized bounds prevent quadratic scanning on long hostile input.
my $EMAIL_RE = qr/[\w\.\+%-]{1,254}+@[\w-]{1,254}+\.[\w\.-]{1,254}\w/;
my $URL_RE   = qr!
  \b(\S{1,254}\s\S{1,254})\s+[\(<]?($EMAIL_RE)[\)>]?\s |
  mailto:($EMAIL_RE)["' ]*>\s*([^<@\s]{1,254}\s+[^<@\s]{1,254})\s*< |
  \b($EMAIL_RE)\b |
  \b((https?|ftp|file)://[\w-]{1,254}+\.[\w\./:\\\+~-]{1,4000}\w\??)\b
!ix;

# Collect the URLs and email addresses of one file's text into $meta. Kept separate from the reading of
# the file (Cavil::Checkout) because this is the part that faces hostile input: it runs over every file
# of every package, test corpora of security tooling included, so it is worth being able to hold a
# string against it directly.
#
# urls with user@ are currently not supported.
sub extract_urls_and_emails ($text, $meta = undef) {
  $meta //= {emails => {}, urls => {}};

  # Every branch of $URL_RE needs either an "@" or a "://", so text containing neither cannot match
  # anywhere. Most source files are exactly that, and skipping them outright is worth about a third of
  # the time this costs on a package. Purely a shortcut for the common case - an attacker supplies an
  # "@" for free, so the bounds in $URL_RE are what keep the bad case cheap.
  return $meta if index($text, '@') < 0 && index($text, '://') < 0;

  while ($text =~ /$URL_RE/g) {
    my ($name, $email, $email2, $name2, $email3, $url) = ($1, $2, $3, $4, $5, $6);
    $email = $email2 unless defined $email;
    $email = $email3 unless defined $email;
    $name  = $name2  unless defined $name;

    $email = undef if defined $email and $email =~ m{(\@-|\@.*(\.-|-\.))};             # RFC 822 illegal
    $email = undef if defined $email and $email =~ m{[\@\.]example\.(net|com|org)};    # RFC 2606
    $url   = undef if defined $url   and $url   =~ m{[/\.]example\.(net|com|org)};     # RFC 2606
    $name  = undef if defined $name  and ($name eq lc $name or $name =~ m{[\(\):\d,\n\r]});

    # file:// urls not wanted in our context.
    $url = undef if defined $url and $url =~ m{^file:/};

    # put each url,email or cve in the list only once. (Once per file.)
    if (defined $email) {
      $email = lc $email;
      $meta->{emails}->{$email} ||= {name => undef, count => 0};
      $meta->{emails}->{$email}->{count}++;
      $meta->{emails}->{$email}->{name} ||= $name;
    }
    if (defined $url) {
      $url =~ s{^(\w+://.[^/])}{lc $1}e;
      $meta->{urls}->{$url} ||= 0;
      $meta->{urls}->{$url}++;
    }
  }

  return $meta;
}

# An unfilled placeholder out of a license boilerplate, not somebody's notice. The bare words are matched
# case sensitively (a "Year" or "Owner" in a real holder name is not a placeholder) while the bracketed
# forms are not, and the bracket spans are bounded so a line of punctuation cannot make this expensive.
my $COPYRIGHT_PLACEHOLDER = qr{
    \b (?: YEAR | YYYY | yyyy | xxxx | XXXX ) \b
  | \b (?i: name \s+ of \s+ (?: the \s+ )? (?: author | copyright \s+ (?: owner | holder ) ) ) \b
  | [<\[] [^>\]]{0,40} (?i: year | name | author | owner | holder ) [^>\]]{0,40} [>\]]
}x;

# The start of the license itself. Reaching one of these means the notice above it has ended, so it stops
# continuation folding from swallowing a whole license body into one "notice".
my $COPYRIGHT_BODY = qr{^(?:
    Permission \s+ is \s+ hereby
  | Redistribution \s+ and \s+ use
  | This \s+ (?: program | software | library | file | work ) \s+ is \s+ (?: free | licensed )
  | Licensed \s+ under
  | THE \s+ SOFTWARE \s+ IS \s+ PROVIDED
)}xi;

# The copyright notices in one file's text, keyed by notice with an occurrence count. Exported for the
# same reason as extract_urls_and_emails: it faces hostile input, so being able to hold a string against
# it directly is worth the indirection.
#
# A notice that names its holder on the lines below it ("Copyright (c) 2019" over an indented list of
# names) is worthless to a NOTICE file without them, so a bounded run of continuation lines is folded in.
sub extract_copyrights ($text) {
  my %copyrights;

  # Most files carry no notice at all, and splitting those into lines is this function's entire cost
  return \%copyrights unless $text =~ /Copyright|\(c\)|\(C\)|\x{00a9}/;

  my @lines = split /\n/, $text, -1;
  my $limit = @lines < MAX_COPYRIGHT_SCAN ? @lines : MAX_COPYRIGHT_SCAN;

  my $found = 0;
  for (my $i = 0; $i < $limit; $i++) {
    next if length $lines[$i] > MAX_COPYRIGHT_SOURCE;
    next unless $lines[$i] =~ /^($COPYRIGHT_LEADER)($COPYRIGHT_TOKEN)\s+(\S.*)$/;
    my ($indent, $token, $rest) = (length $1, $2, $3);

    # A notice opens on its year or its holder; "Copyright and related rights are waived" is prose
    next unless $rest =~ /^(?:[0-9(<"'\x{00a9}]|\p{Lu})/;

    # The Artistic License and the SIL OFL define "Copyright Holder" as a term and then use it in prose
    next if $rest =~ /^(?:Holders?|Owners?|Notice)\b/;

    my $tail = $rest;
    my @more;
    for my $j ($i + 1 .. $i + MAX_COPYRIGHT_FOLLOW) {
      last if $j >= $limit || length $lines[$j] > MAX_COPYRIGHT_SOURCE;

      last unless $lines[$j] =~ /^($COPYRIGHT_LEADER)(\S.*)$/;
      my ($next_indent, $next) = (length $1, $2);
      last if $next =~ /^$COPYRIGHT_TOKEN/ || $next =~ $COPYRIGHT_BODY;

      # Indented under the notice, or the notice broke off mid sentence, or the trailer it pairs with
      last
        unless $next_indent > $indent || $tail =~ /(?:,|\band\b|\bby\b|\d{4})$/ || $next =~ /^All rights reserved\b/i;

      push @more, $next;
      ($tail, $i) = ($next, $j);
    }

    my $notice = join ' ', "$token $rest", @more;
    $notice =~ s/\s+/ /g;
    $notice =~ s/^\s+|\s+$//g;

    # The comment closes, the notice does not; this text goes into a NOTICE file as it stands
    $notice =~ s{\s*(?:\*/|-->|\*\)|--\}\}|\}\})$}{};
    $notice = substr $notice, 0, MAX_COPYRIGHT_LENGTH if length $notice > MAX_COPYRIGHT_LENGTH;
    next if $notice =~ $COPYRIGHT_PLACEHOLDER;

    $copyrights{$notice}++;
    last if ++$found >= MAX_COPYRIGHTS;
  }

  return \%copyrights;
}

# Best-effort expansion of simple RPM spec macros, so metadata fields (most importantly Version) do
# not end up stored as unresolved macros like "%{mainver}". This only ever does literal string
# substitution from macros the spec defines itself; it never evaluates anything. Shell (%(...)),
# %{expand:...}/%{lua:...}, conditional references (%{?foo}) and %if branches are deliberately left
# untouched, and unknown macros are passed through verbatim. A pass cap makes recursive or cyclic
# definitions terminate safely.
sub expand_spec_macros ($content) {
  return $content unless defined $content;

  # Collect simple "%define NAME VALUE" / "%global NAME VALUE" definitions (first wins, like rpm).
  # Lines starting with %{...} (conditional/expand defines) or without a value are skipped.
  my %macros;
  for my $line (split "\n", $content) {
    next unless $line =~ /^\s*%(?:define|global)\s+(\w+)\s+(.+?)\s*$/;
    $macros{$1} //= $2;
  }

  # rpm auto-defines %{name}, %{version} and %{release} from the corresponding tags; seed them with
  # the raw tag values so references elsewhere (e.g. in Source URLs) resolve too. These values may
  # themselves be macros, which the fixpoint below takes care of.
  for my $line (split "\n", $content) {
    if    ($line =~ /^Name:\s*(.+?)\s*$/)    { $macros{name}    //= $1 }
    elsif ($line =~ /^Version:\s*(.+?)\s*$/) { $macros{version} //= $1 }
    elsif ($line =~ /^Release:\s*(.+?)\s*$/) { $macros{release} //= $1 }
  }

  # Expand references repeatedly to resolve chains (e.g. mainver -> major), bounded so recursive or
  # cyclic definitions cannot loop forever. Only defined macros are substituted; the "(?<!%)" guard
  # leaves escaped "%%" alone, and using /ge with a hash lookup (never string interpolation) means
  # hostile macro values cannot inject regex or replacement syntax.
  for (1 .. 10) {
    my $before = $content;
    $content =~ s/(?<!%)%\{(\w+)\}/exists $macros{$1} ? $macros{$1} : "%{$1}"/ge;
    $content =~ s/(?<!%)%(\w+)/exists $macros{$1} ? $macros{$1} : "%$1"/ge;
    last if $content eq $before;
  }

  return $content;
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

sub md5_file ($file) {
  my $md5 = Digest::MD5->new;
  $md5->addfile(path($file)->open('r'));
  return $md5->hexdigest;
}

sub file_and_checksum ($path, $first_line, $last_line) {
  my %lines;
  for (my $line = $first_line; $line <= $last_line; $line += 1) {
    $lines{$line} = 1;
  }

  my $ctx = Cavil::PatternEngine::init_hash(0, 0);

  my $text = '';
  for my $row (@{Cavil::PatternEngine::read_lines($path, \%lines)}) {
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
  Cavil::PatternEngine::init_matcher();
  my $a   = Cavil::PatternEngine::parse_tokens($text);
  my $ctx = Cavil::PatternEngine::init_hash(0, 0);
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
  my $ctx = Cavil::PatternEngine::init_hash(0, 0);
  $ctx->add($text);
  return $ctx->hex;
}

# Similarity normalization follows SPDX matching principles and is not for pattern storage.
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

# Reuse the matcher tokenizer so shingle and bag vocabularies agree.
sub text_shingles ($text, $k = 3) {
  Cavil::PatternEngine::init_matcher();
  my $toks = Cavil::PatternEngine::parse_tokens(normalize_license_text($text));

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

# Same shingles as text_shingles, but each reduced to a compact 60-bit integer id (positive, so it fits
# a signed BIGINT) via the engine's content hash. This is the on-disk/queryable form stored in the
# pattern_shingles table and used to score snippets against it: maintenance and scoring MUST derive ids
# through this one function so the numbers always match. Returns a hashref keyed by id.
sub text_shingle_ids ($text, $k = 3) {
  no warnings 'portable';    # 60-bit hex ids exceed 32 bits; that is fine on the 64-bit Perl Cavil requires
  my $shingles = text_shingles($text, $k);
  my %ids;
  for my $shingle (keys %$shingles) {
    my $ctx = Cavil::PatternEngine::init_hash(0, 0);
    $ctx->add($shingle);
    $ids{hex substr($ctx->hex, 0, 15)} = 1;
  }
  return \%ids;
}

# One partial character at the end of a truncated read fails the decode of the whole text, dropping it
# back to bytes where every "\xa9" continuation byte reads as a copyright sign
my $PARTIAL_UTF8 = qr/(?:[\xc2-\xdf]|[\xe0-\xef][\x80-\xbf]{0,1}|[\xf0-\xf4][\x80-\xbf]{0,2})\z/;

sub slurp_and_decode ($path, $max = $MAX_FILE_SIZE) {

  open my $file, '<', $path or croak qq{Can't open file "$path": $!};
  croak qq{Can't read from file "$path": $!} unless defined($file->sysread(my $content, $max, 0));

  $content =~ s/$PARTIAL_UTF8//;

  # Text that is not UTF-8 stays a byte string, which Perl reads as one codepoint per byte and so is
  # Latin-1 by another name - the right guess for the files that reach this
  return Mojo::Util::decode('UTF-8', $content) // $content;
}

# The label and the license can differ: a list may want to say "Curated text" while the viewer still has to
# be asked for the license itself. The "spdx" class tells the viewer whether there is a page to link out to.
sub _license_button ($label, $license, $spdx) {
  my $class = $spdx ? 'license-link spdx' : 'license-link';
  return
      qq{<button type="button" class="$class" data-license="@{[Mojo::Util::xml_escape($license)]}">}
    . Mojo::Util::xml_escape($label)
    . '</button>';
}

# A name with no SPDX identifier in it is one indivisible token, so either the whole thing has a curated
# text to show or none of it does
sub license_link ($name, $has_text = 0, $label = undef) {
  return spdx_link($name) unless $has_text;
  return _license_button($label // $name, $name, 0);
}

# 5MB, so only workers that serve a license page pay the decode
sub license_text ($id) {
  return undef unless defined $id && length $id;
  state $texts = decode_json_fast(path(__FILE__)->dirname->child('resources', 'license_texts.json')->slurp)->{texts};
  return $texts->{$id};
}

# Exceptions as well as licenses, unlike extract_spdx_identifiers, whose callers would read
# "GPL-2.0-only WITH Autoconf-exception-2.0" as two licenses. Bounded, so "Mitch" does not match MIT.
my $SPDX_ATOM_RE = do {
  my $atoms = join '|',
    map {quotemeta} sort { length $b <=> length $a || $a cmp $b } (@SPDX_LICENSES, @SPDX_EXCEPTIONS);
  qr/(?<![\w.+-])($atoms)(?![\w.+-])/;
};

# Whether the identifiers account for the whole expression. "MIT AND Vendor-Thing-1.0" yields the MIT
# identifier but is not covered by it, so reproducing MIT's text alone would leave half the terms out.
sub spdx_only_expression ($expression) {
  return 0 unless defined $expression && length $expression;
  my $rest = $expression =~ s/$SPDX_ATOM_RE//gr;
  $rest =~ s/\b(?:AND|OR|WITH)\b//gi;
  $rest =~ s/[\s()+]//g;
  return length($rest) ? 0 : 1;
}

sub spdx_identifiers ($expression) {
  return [] unless defined $expression;

  my (@identifiers, %seen);
  while ($expression =~ /$SPDX_ATOM_RE/g) {
    push @identifiers, $1 unless $seen{$1}++;
  }
  return \@identifiers;
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
    $out .= $is_token ? _license_button($part, $part, 1) : Mojo::Util::xml_escape($part);
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

# Legal review notices are a non-standard convention used in SUSE spec/Dockerfile/Helm comments. A notice opens with a
# "Legal-Review-Notice:" comment and continues across the following comment lines until a blank line, an empty comment
# line, a non-comment line, or a new notice ends the block. The possessive "#++" stops an empty "###" line from leaking
# a stray "#" into the text.
my $LEGAL_REVIEW_NOTICE_RE      = qr/^\s*#+\s*Legal-Review-Notice:\s*(.+)\s*$/i;
my $LEGAL_REVIEW_NOTICE_CONT_RE = qr/^\s*#++\s*(\S.*?)\s*$/;

sub legal_review_notices ($content) {
  my @lines = split "\n", $content;
  my @notices;
  for (my $i = 0; $i < @lines; $i++) {
    next unless $lines[$i] =~ $LEGAL_REVIEW_NOTICE_RE;
    (my $text = $1) =~ s/\s+$//;
    while ($i + 1 < @lines) {
      my $next = $lines[$i + 1];
      last if $next =~ $LEGAL_REVIEW_NOTICE_RE || $next !~ $LEGAL_REVIEW_NOTICE_CONT_RE;
      $text .= "\n$1";
      $i++;
    }
    push @notices, $text;
  }
  return \@notices;
}

sub pattern_matches ($pattern, $text) {
  my $matcher = Cavil::PatternEngine::init_matcher();
  my $parsed  = Cavil::PatternEngine::parse_tokens($pattern);
  $matcher->add_pattern(1, $parsed);

  my $file    = tempfile->spew("ABC\n$text\nABC\n", 'UTF-8');
  my $matches = !!@{$matcher->find_matches($file)};
  undef $file;

  return $matches;
}

sub pattern_contains_redundant_skip ($pattern) {
  return $pattern =~ /^\s*\$SKIP/ || $pattern =~ /\$SKIP\d*\s*$/;
}

# A wildcard anywhere, which is what stops a pattern from being reproducible as license text
sub pattern_contains_skip ($pattern) { return $pattern =~ /\$SKIP\d*/ ? 1 : 0 }

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
  for my $row (@{Cavil::PatternEngine::read_lines($path, \%needed_lines)}) {
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
