# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package Cavil::PostProcess::Markup;
use Mojo::Base -base, -signatures;

use Exporter     qw(import);
use HTML::Parser ();

our @EXPORT_OK = qw(looks_like_markup strip_markup strip_markup_string);

# Extensions we treat as markup. OOXML/ODF are already unzipped to component .xml
# files by the time PostProcess runs, so ".xml" covers document.xml / content.xml.
my $MARKUP_EXT_RE = qr/\.(?:x?html?|xml|xhtml|svg|rng|xsl|xslt|xsd)$/i;

# Elements whose *text content* is never license prose - drop it entirely.
my %SKIP_CONTENT = map { $_ => 1 } qw(script style);

# Cheap gate: decide whether a file should go through the markup stripper instead of
# the plain line-wrapper. Extension is the primary signal; the content sniff is a
# guard so we never strip a mislabeled plain-text file (the failure that killed the
# old w3m step - see git c580533c0). $head is the first chunk of the file.
sub looks_like_markup ($path, $head) {
  return 0 unless defined $head && length $head;

  # Extension says markup AND there is at least one tag in the head.
  return 1 if $path =~ $MARKUP_EXT_RE && $head =~ /<[A-Za-z!?\/]/;

  # Unmistakable document markers regardless of extension.
  return 1 if $head =~ /<\?xml\b/;
  return 1 if $head =~ /<!DOCTYPE\s+html/i;
  return 1 if $head =~ /<html[\s>]/i;

  return 0;
}

# Build a streaming HTML::Parser that extracts entity-decoded text and hands it to
# $line_cb one complete line at a time. Only the current line is buffered, so peak
# memory is O(longest text run), independent of file size - no DOM tree. Tag
# boundaries end the current line (blank lines are never emitted) so tokens on either
# side of markup never merge and each text run is its own line for readable snippet
# display. Returns ($parser, $flush); the caller drives the parser then calls $flush
# to emit any trailing line. Text inside <script>/<style> is dropped.
sub _make_parser ($line_cb) {
  my $line       = '';    # current line buffer (whitespace-collapsed, no leading space)
  my $skip_depth = 0;     # >0 while inside <script>/<style>

  my $flush = sub {
    return unless $line =~ /\S/;
    $line_cb->($line);
    $line = '';
  };
  my $emit_break = sub { $flush->(); $line = '' };
  my $emit_text  = sub ($text) {
    return if $skip_depth;
    $text =~ s/\s+/ /g;                # collapse all whitespace (incl newlines)
    $text =~ s/^ // if $line eq '';    # trim leading space at line start
    return if $text eq '' || $text eq ' ';
    $line .= $text;
  };

  my $p = HTML::Parser->new(api_version => 3, marked_sections => 1, unbroken_text => 1);

  # Text nodes: decoded text. CDATA arrives via the same handler with marked_sections.
  $p->handler(text => sub ($dtext) { $emit_text->($dtext) }, 'dtext');

  # Comments are kept - license declarations (SPDX-License-Identifier, copyright notices)
  # routinely live in `<!-- ... -->`, and the raw scan used to see them. Emit the comment
  # body on its own line(s) so it is not glued to surrounding text.
  $p->handler(comment => sub ($text) { $emit_break->(); $emit_text->($text); $emit_break->() }, 'text');

  # Tag boundaries: end the line, and enter/leave skip regions for script/style.
  $p->handler(start => sub ($tag) { $skip_depth++ if $SKIP_CONTENT{$tag}; $emit_break->() }, 'tagname');
  $p->handler(
    end => sub ($tag) { $skip_depth-- if $SKIP_CONTENT{$tag} && $skip_depth > 0; $emit_break->() },
    'tagname'
  );

  return ($p, $flush);
}

# Stream markup from $in_path, calling $line_cb->($line) for each stripped line (no
# trailing newline). Input is read in chunks through a UTF-8 layer, so peak memory
# stays flat regardless of file size, entity-decoded characters (e.g. &copy; -> ©) and
# UTF-8 literals both round-trip correctly, and the lines handed to $line_cb are
# character strings (callers must write them through a UTF-8 layer). Invalid byte
# sequences are substituted with U+FFFD. This is the entry PostProcess drives so it can
# line-wrap each stripped line as it arrives.
sub strip_markup ($in_path, $line_cb) {
  my ($p, $flush) = _make_parser($line_cb);
  open my $in, '<:encoding(UTF-8)', $in_path or die qq{Can't open "$in_path": $!};
  $p->parse_file($in);
  $p->eof;
  close $in;
  $flush->();
  return 1;
}

# Convenience for tests / callers that already have the text in memory. Returns the
# stripped text as lines joined by "\n" (no leading/trailing blank line).
sub strip_markup_string ($str) {
  my @lines;
  my ($p, $flush) = _make_parser(sub ($line) { push @lines, $line });
  $p->parse($str);
  $p->eof;
  $flush->();
  return join "\n", @lines;
}

1;
