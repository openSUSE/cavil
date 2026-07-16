# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Mojo::Base -strict, -signatures;

use Test::More;
use Mojo::File qw(tempdir);
use Mojo::Util qw(encode);

# Diagnostics may contain decoded UTF-8 (©, —, …); keep the TAP handles from warning.
my $builder = Test::More->builder;
binmode $builder->$_, ':encoding(UTF-8)' for qw(output failure_output todo_output);
use Cavil::PostProcess::Markup qw(looks_like_markup strip_markup strip_markup_string);
use Cavil::Util                qw(pattern_matches);

subtest 'looks_like_markup gate' => sub {
  ok looks_like_markup('readme.html', '<html><body>GPL</body></html>'), 'html with a tag';
  ok looks_like_markup('content.xml', '<?xml version="1.0"?><r>x</r>'), 'xml declaration';
  ok looks_like_markup('doc.xhtml',   '<div>hi</div>'),                 'xhtml with a tag';
  ok looks_like_markup('weird.dat',   '<!DOCTYPE html><html>hi'),       'html marker without a markup extension';

  ok !looks_like_markup('notes.txt',  'if (a < b && c > d) return;'), 'plain text with angle brackets is left alone';
  ok !looks_like_markup('tmpl.cpp',   'std::vector<int> v; a<b>c;'),  'C++ templates are left alone';
  ok !looks_like_markup('page.xhtml', 'plain text, no tags at all'),  'markup extension but no tag';
  ok !looks_like_markup('empty.html', ''),                            'empty head';
};

subtest 'strip ODF/OOXML/HTML to clean text' => sub {
  my $odf = '<text:p text:style-name="P8">U.S.A. All rights reserved.</text:p>'
    . '<text:p>This product is protected by copyright and distributed under licenses restricting its use.</text:p>';
  my $odf_text = strip_markup_string($odf);
  is $odf_text,
    "U.S.A. All rights reserved.\n"
    . "This product is protected by copyright and distributed under licenses restricting its use.",
    'ODF paragraphs become clean lines';
  unlike $odf_text, qr/text:p|style-name|P8|[<>]/, 'no markup tokens leak';

  my $ooxml = '<w:p><w:pPr><w:pStyle w:val="NoteLevel1"/></w:pPr><w:r><w:t>Please be reminded that the program '
    . 'is a contact sport</w:t></w:r></w:p><w:p><w:r><w:t>and assumes full responsibility</w:t></w:r></w:p>';
  my $ooxml_text = strip_markup_string($ooxml);
  is $ooxml_text, "Please be reminded that the program is a contact sport\nand assumes full responsibility",
    'OOXML runs become clean lines';
  unlike $ooxml_text, qr/w:val|NoteLevel1|[<>]/, 'no OOXML markup tokens leak';
};

subtest 'script and style content is dropped' => sub {
  my $html = '<html><head><style>.p{color:red}</style><script>var license="FAKE-GPL";</script></head>'
    . '<body><p>Permission is hereby granted, free of charge, to any person</p></body></html>';
  my $text = strip_markup_string($html);
  is $text, 'Permission is hereby granted, free of charge, to any person', 'only body prose survives';
  unlike $text, qr/FAKE-GPL|color:red/, 'script and style bodies dropped';
};

subtest 'HTML entities are decoded' => sub {
  my $text = strip_markup_string('<p>Copyright &copy; 2026 &amp; contributors, redistribute &lt;source&gt; under '
      . '&sect;2, fee 5&nbsp;EUR, year &#169; em&#x2014;dash.</p>');
  like $text, qr/Copyright \x{a9} 2026 & contributors/, 'named &copy;/&amp; decoded';
  like $text, qr/redistribute <source> under/,          '&lt;/&gt; decoded';
  like $text, qr/\x{a7}2/,                              '&sect; decoded';
  like $text, qr/fee 5 EUR/,                            '&nbsp; decoded (and normalised to a plain space)';
  like $text, qr/year \x{a9} em\x{2014}dash/,           'numeric &#169; and hex &#x2014; decoded';
};

subtest 'comments are kept as decoded text (license notices live there)' => sub {
  my $text
    = strip_markup_string('<html><body><!-- Copyright &copy; 2010 by K. Kenny &lt;kb@acm.org&gt; -- '
      . 'Redistribution permitted under the Open Publication License &lt;http://example.org/&gt; -->'
      . '<p>Body</p></body></html>');
  like $text, qr/Copyright \x{a9} 2010 by K\. Kenny <kb\@acm\.org>/,
    'comment entities are decoded, not left as &copy;/&lt;';
  like $text,   qr/Open Publication License <http:/, 'a license reference inside a comment is preserved';
  unlike $text, qr/<!--|-->|&copy;|&lt;|&gt;/,       'no comment delimiters or raw entities leak';

  like strip_markup_string('<root><!-- SPDX-License-Identifier: Apache-2.0 --><a>x</a></root>'),
    qr/SPDX-License-Identifier: Apache-2\.0/, 'SPDX identifier in a comment survives';
};

subtest 'UTF-8 literals and entities round-trip through a file' => sub {
  my $dir = tempdir;
  my $in  = $dir->child('doc.html');
  $in->spew(encode 'UTF-8', qq{<p>caf\x{e9} &copy; \x{2603}</p>});    # UTF-8 café + &copy; + literal snowman

  my @lines;
  strip_markup($in->to_string, sub { push @lines, $_[0] });
  is scalar(@lines), 1,                           'one line';
  is $lines[0],      "caf\x{e9} \x{a9} \x{2603}", 'café literal, decoded ©, and snowman all correct characters';
};

subtest 'invalid byte sequences are handled gracefully' => sub {
  my $dir = tempdir;
  my $in  = $dir->child('bad.html');
  my $fh  = $in->open('>:raw');
  print $fh '<p>Bad byte ', chr(0xFF), ' then &amp; done</p>';
  close $fh;

  my @lines;
  strip_markup($in->to_string, sub { push @lines, $_[0] });
  like join('', @lines), qr/Bad byte .* then & done/, 'surrounding text and entity survive an invalid byte';
};

subtest 'match invariant: a pattern from stripped text matches the stripped text' => sub {
  my $raw = '<div><p>Permission is hereby granted, free of charge, to any person obtaining a copy of this '
    . 'software</p><p>and associated documentation files to deal in the Software without restriction.</p></div>';
  my $stripped = strip_markup_string($raw);
  ok pattern_matches($stripped, $stripped), 'stripped text is a usable, self-matching pattern';
};

done_testing;
