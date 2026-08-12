# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package Cavil::PostProcess::Markup;
use Mojo::Base -base, -signatures;

use Exporter       qw(import);
use HTML::Parser   ();
use HTML::Entities qw(decode_entities);

our @EXPORT_OK = qw(looks_like_markup strip_markup strip_markup_string);

# OOXML and ODF components reach post-processing as XML.
my $MARKUP_EXT_RE = qr/\.(?:x?html?|xml|xhtml|svg|rng|xsl|xslt|xsd)$/i;

# Script and style content creates false license prose.
my %SKIP_CONTENT = map { $_ => 1 } qw(script style);

# Require markup syntax even for known extensions to protect mislabeled plain text.
sub looks_like_markup ($path, $head) {
  return 0 unless defined $head && length $head;

  return 1 if $path =~ $MARKUP_EXT_RE && $head =~ /<[A-Za-z!?\/]/;

  return 1 if $head =~ /<\?xml\b/;
  return 1 if $head =~ /<!DOCTYPE\s+html/i;
  return 1 if $head =~ /<html[\s>]/i;

  return 0;
}

# Streaming bounds memory; tag boundaries prevent token merging. Source lines
# preserve report locations after whitespace collapse.
sub _make_parser ($line_cb) {
  my $line       = '';
  my $src        = 0;
  my $skip_depth = 0;

  my $flush = sub {
    return unless $line =~ /\S/;
    $line_cb->($line, $src);
    $line = '';
  };
  my $emit_break = sub { $flush->(); $line = '' };
  my $emit_text  = sub ($text, $lineno) {
    return if $skip_depth;

    # Leading newlines move text past the preceding tag's reported line.
    $lineno += ($1 =~ tr/\n//) if $line eq '' && $text =~ /^(\s*\n)/;

    $text =~ s/\s+/ /g;
    $text =~ s/^ // if $line eq '';
    return if $text eq '' || $text eq ' ';

    # Embedded newlines must not shift attribution to the end of a text run.
    $src = $lineno if $line eq '';
    $line .= $text;
  };

  my $p = HTML::Parser->new(api_version => 3, marked_sections => 1, unbroken_text => 1);

  $p->handler(text => sub ($dtext, $lineno) { $emit_text->($dtext, $lineno) }, 'dtext,line');

  # Preserve license declarations in comments and decode them like text nodes.
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

  $p->handler(start => sub ($tag) { $skip_depth++ if $SKIP_CONTENT{$tag}; $emit_break->() }, 'tagname');
  $p->handler(
    end => sub ($tag) { $skip_depth-- if $SKIP_CONTENT{$tag} && $skip_depth > 0; $emit_break->() },
    'tagname'
  );

  return ($p, $flush);
}

# UTF-8 streaming bounds memory and gives downstream writers character strings.
sub strip_markup ($in_path, $line_cb) {
  my ($p, $flush) = _make_parser($line_cb);
  open my $in, '<:encoding(UTF-8)', $in_path or die qq{Can't open "$in_path": $!};
  $p->parse_file($in);
  $p->eof;
  close $in;
  $flush->();
  return 1;
}

sub strip_markup_string ($str) {
  my @lines;
  my ($p, $flush) = _make_parser(sub ($line, $src) { push @lines, $line });
  $p->parse($str);
  $p->eof;
  $flush->();
  return join "\n", @lines;
}

1;
