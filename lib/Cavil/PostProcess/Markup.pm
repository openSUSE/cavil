# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package Cavil::PostProcess::Markup;
use Mojo::Base -base, -signatures;

use Exporter       qw(import);
use HTML::Parser   ();
use HTML::Entities qw(decode_entities);

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
#
# Each line is reported as $line_cb->($line, $src_line), where $src_line is the line of
# the *input* the buffer started on. Stripping discards the input's own line structure
# (whitespace is collapsed, markup-only lines emit nothing), so this is the only way back
# to a position in the original file - Cavil::SPDX needs it to report a license found in
# a stripped file against the line it occupies in the file the report names.
sub _make_parser ($line_cb) {
  my $line       = '';    # current line buffer (whitespace-collapsed, no leading space)
  my $src        = 0;     # input line the current buffer started on
  my $skip_depth = 0;     # >0 while inside <script>/<style>

  my $flush = sub {
    return unless $line =~ /\S/;
    $line_cb->($line, $src);
    $line = '';
  };
  my $emit_break = sub { $flush->(); $line = '' };
  my $emit_text  = sub ($text, $lineno) {
    return if $skip_depth;

    # The run's reported line is where the run starts, and a run opening a buffer usually starts
    # with the newline that followed the previous tag - "<div>\nhello" is one run beginning on the
    # <div> line. That whitespace is about to be collapsed away, but its newlines still count
    # towards where the text itself sits, or every line of an indented document is off by one
    $lineno += ($1 =~ tr/\n//) if $line eq '' && $text =~ /^(\s*\n)/;

    $text =~ s/\s+/ /g;                # collapse all whitespace (incl newlines)
    $text =~ s/^ // if $line eq '';    # trim leading space at line start
    return if $text eq '' || $text eq ' ';

    # A text run can span several input lines (the newlines inside it were just collapsed),
    # so the buffer is attributed to the line it opened on, not the one it ends on
    $src = $lineno if $line eq '';
    $line .= $text;
  };

  my $p = HTML::Parser->new(api_version => 3, marked_sections => 1, unbroken_text => 1);

  # Text nodes: decoded text. CDATA arrives via the same handler with marked_sections.
  # With unbroken_text the reported line is the start of the whole run, which is what we want.
  $p->handler(text => sub ($dtext, $lineno) { $emit_text->($dtext, $lineno) }, 'dtext,line');

  # Comments are kept - license declarations (SPDX-License-Identifier, copyright notices)
  # routinely live in `<!-- ... -->`, and the raw scan used to see them. The comment event has no
  # decoded-text form, so strip the `<!--`/`-->` delimiters and decode entities ourselves (matching
  # how normal text is handled) - otherwise the body leaks out as raw "&copy;"/"&lt;". Emit on its
  # own line(s) so it is not glued to surrounding text.
  $p->handler(
    comment => sub ($text, $lineno) {
      $text =~ s/^<!--//;
      $text =~ s/-->$//;
      decode_entities($text);
      $emit_break->();
      $emit_text->($text, $lineno);
      $emit_break->();
    },
    'text,line'
  );

  # Tag boundaries: end the line, and enter/leave skip regions for script/style.
  $p->handler(start => sub ($tag) { $skip_depth++ if $SKIP_CONTENT{$tag}; $emit_break->() }, 'tagname');
  $p->handler(
    end => sub ($tag) { $skip_depth-- if $SKIP_CONTENT{$tag} && $skip_depth > 0; $emit_break->() },
    'tagname'
  );

  return ($p, $flush);
}

# Stream markup from $in_path, calling $line_cb->($line, $src_line) for each stripped
# line (no trailing newline). Input is read in chunks through a UTF-8 layer, so peak memory
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
  my ($p, $flush) = _make_parser(sub ($line, $src) { push @lines, $line });
  $p->parse($str);
  $p->eof;
  $flush->();
  return join "\n", @lines;
}

1;
