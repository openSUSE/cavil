# Copyright (C) 2024 SUSE LLC
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

use Mojo::Base -strict;

use Test::More;
use Cavil::ReportUtil (
  qw(estimated_risk incompatible_licenses is_license_filename minimal_snippet new_license_names new_unresolved_files),
  qw(overlapping_licenses report_checksum report_shortname should_clear_boilerplate should_cover_snippet),
  qw(should_fold_snippet should_overlap_clear smart_edit_snippet spdx_edit_snippet summary_delta summary_delta_score)
);
use Cavil::Util qw(SNIPPET_SCORE_VERSION extract_spdx_identifiers);

subtest 'estimated_risk' => sub {
  subtest 'Risk 0' => sub {
    is estimated_risk(0, 0.10), 8, 'high risk';
    is estimated_risk(0, 0.20), 7, 'high risk';
    is estimated_risk(0, 0.30), 6, 'high risk';
    is estimated_risk(0, 0.40), 5, 'medium risk';
    is estimated_risk(0, 0.50), 5, 'medium risk';
    is estimated_risk(0, 0.60), 5, 'medium risk';
    is estimated_risk(0, 0.70), 5, 'medium risk';
    is estimated_risk(0, 0.80), 5, 'medium risk';
    is estimated_risk(0, 0.89), 5, 'medium risk';
    is estimated_risk(0, 0.90), 1, 'low risk';
    is estimated_risk(0, 0.94), 1, 'low risk';
    is estimated_risk(0, 0.95), 0, 'low risk';
    is estimated_risk(0, 0.99), 0, 'low risk';
  };

  subtest 'Risk 1' => sub {
    is estimated_risk(1, 0.10), 8, 'high risk';
    is estimated_risk(1, 0.20), 7, 'high risk';
    is estimated_risk(1, 0.30), 7, 'high risk';
    is estimated_risk(1, 0.40), 6, 'high risk';
    is estimated_risk(1, 0.50), 5, 'high risk';
    is estimated_risk(1, 0.60), 5, 'high risk';
    is estimated_risk(1, 0.70), 5, 'high risk';
    is estimated_risk(1, 0.80), 5, 'medium risk';
    is estimated_risk(1, 0.89), 5, 'medium risk';
    is estimated_risk(1, 0.90), 2, 'low risk';
    is estimated_risk(1, 0.93), 2, 'low risk';
    is estimated_risk(1, 0.94), 1, 'low risk';
    is estimated_risk(1, 0.99), 1, 'low risk';
  };

  subtest 'Risk 2' => sub {
    is estimated_risk(2, 0.10), 8, 'high risk';
    is estimated_risk(2, 0.20), 8, 'high risk';
    is estimated_risk(2, 0.30), 7, 'high risk';
    is estimated_risk(2, 0.40), 6, 'high risk';
    is estimated_risk(2, 0.50), 6, 'high risk';
    is estimated_risk(2, 0.60), 5, 'high risk';
    is estimated_risk(2, 0.70), 5, 'high risk';
    is estimated_risk(2, 0.80), 5, 'medium risk';
    is estimated_risk(2, 0.89), 5, 'medium risk';
    is estimated_risk(2, 0.90), 3, 'low risk';
    is estimated_risk(2, 0.92), 3, 'low risk';
    is estimated_risk(2, 0.93), 2, 'low risk';
    is estimated_risk(2, 0.99), 2, 'low risk';
  };

  subtest 'Risk 3' => sub {
    is estimated_risk(3, 0.10), 8, 'high risk';
    is estimated_risk(3, 0.20), 8, 'high risk';
    is estimated_risk(3, 0.30), 7, 'high risk';
    is estimated_risk(3, 0.40), 7, 'high risk';
    is estimated_risk(3, 0.50), 6, 'high risk';
    is estimated_risk(3, 0.60), 5, 'medium risk';
    is estimated_risk(3, 0.70), 5, 'medium risk';
    is estimated_risk(3, 0.80), 5, 'medium risk';
    is estimated_risk(3, 0.90), 4, 'low risk';
    is estimated_risk(3, 0.91), 4, 'low risk';
    is estimated_risk(3, 0.92), 3, 'low risk';
    is estimated_risk(3, 0.99), 3, 'low risk';
  };

  subtest 'Risk 4' => sub {
    is estimated_risk(4, 0.10), 9, 'high risk';
    is estimated_risk(4, 0.20), 8, 'high risk';
    is estimated_risk(4, 0.30), 8, 'high risk';
    is estimated_risk(4, 0.40), 7, 'high risk';
    is estimated_risk(4, 0.50), 7, 'high risk';
    is estimated_risk(4, 0.60), 6, 'high risk';
    is estimated_risk(4, 0.70), 6, 'high risk';
    is estimated_risk(4, 0.80), 5, 'medium risk';
    is estimated_risk(4, 0.90), 5, 'medium risk';
    is estimated_risk(4, 0.91), 4, 'low risk';
    is estimated_risk(4, 0.99), 4, 'low risk';
  };

  subtest 'Risk 5' => sub {
    is estimated_risk(5, 0.10), 9, 'high risk';
    is estimated_risk(5, 0.20), 8, 'high risk';
    is estimated_risk(5, 0.30), 8, 'high risk';
    is estimated_risk(5, 0.40), 7, 'high risk';
    is estimated_risk(5, 0.50), 7, 'high risk';
    is estimated_risk(5, 0.60), 7, 'high risk';
    is estimated_risk(5, 0.70), 6, 'high risk';
    is estimated_risk(5, 0.80), 6, 'high risk';
    is estimated_risk(5, 0.87), 6, 'high risk';
    is estimated_risk(5, 0.88), 5, 'high risk';
    is estimated_risk(5, 0.90), 5, 'medium risk';
    is estimated_risk(5, 0.99), 5, 'medium risk';
  };

  subtest 'Risk 6' => sub {
    is estimated_risk(6, 0.10), 9, 'high risk';
    is estimated_risk(6, 0.20), 8, 'high risk';
    is estimated_risk(6, 0.30), 8, 'high risk';
    is estimated_risk(6, 0.40), 8, 'high risk';
    is estimated_risk(6, 0.50), 8, 'high risk';
    is estimated_risk(6, 0.60), 7, 'high risk';
    is estimated_risk(6, 0.70), 7, 'high risk';
    is estimated_risk(6, 0.80), 7, 'high risk';
    is estimated_risk(6, 0.83), 7, 'high risk';
    is estimated_risk(6, 0.84), 6, 'high risk';
    is estimated_risk(6, 0.90), 6, 'high risk';
    is estimated_risk(6, 0.99), 6, 'high risk';
  };
};

subtest 'incompatible_licenses' => sub {
  subtest 'No incompatible licenses' => sub {
    is_deeply incompatible_licenses({},               []), [], 'no incompatible licenses found';
    is_deeply incompatible_licenses({licenses => {}}, []), [], 'no incompatible licenses found';

    my $rules = [{licenses => ['GPL-2.0-only', 'Apache-2.0']}];
    is_deeply incompatible_licenses({},               $rules), [], 'no incompatible licenses found';
    is_deeply incompatible_licenses({licenses => {}}, $rules), [], 'no incompatible licenses found';

    my $report
      = {licenses =>
        {'MIT' => {risk => 1}, 'Apache-2.0' => {risk => 2, spdx => 'Apache-2.0'}, 'BSD-3-Clause' => {risk => 1}}
      };
    is_deeply incompatible_licenses($report, $rules), [], 'no incompatible licenses found';

    $report = {
      licenses => {
        'GPL-2.0-only' => {risk => 1, spdx => 'GPL-2.0-only'},
        'BSD-3-Clause' => {risk => 1},
        'Apache-2.0'   => {risk => 2, spdx => 'Apache-2.0'}
      }
    };
    $rules = [{licenses => ['GPL-2.0-only', 'Apache-2.0', 'MIT']}];
    is_deeply incompatible_licenses($report, $rules), [], 'no incompatible licenses found';
  };

  subtest 'Incompatible licenses' => sub {
    subtest 'Main licenses' => sub {
      my $report = {
        licenses => {
          'MIT AND GPL-2.0+' => {risk => 1, spdx => 'MIT AND GPL-2.0-only'},
          'BSD-3-Clause'     => {risk => 1},
          'Apache-2.0'       => {risk => 2, spdx => 'Apache-2.0'}
        }
      };
      my $rules = [{licenses => ['GPL-2.0-only', 'Apache-2.0', 'MIT']}];
      is_deeply incompatible_licenses($report, $rules), [{licenses => ['GPL-2.0-only', 'Apache-2.0', 'MIT']}],
        'incompatible licenses found';
    };

    subtest 'Keyword matches' => sub {
      my $report = {
        licenses     => {'BSD-3-Clause' => {risk => 1}, 'Apache-2.0' => {risk => 2, spdx => 'Apache-2.0'}},
        missed_files => {14 => [5, 1, "", ""], 8 => [5, 1, "", ""], 9 => [7, '0.5902', 'GPL-2.0', 'GPL-2.0-only']},
      };
      my $rules = [{licenses => ['GPL-2.0-only', 'Apache-2.0']}];
      is_deeply incompatible_licenses($report, $rules), [{licenses => ['GPL-2.0-only', 'Apache-2.0']}],
        'incompatible licenses found';
    };
  };

  subtest 'Defaults' => sub {
    my $report = {
      licenses => {
        'MIT AND GPL-2.0-only' => {risk => 1, spdx => 'MIT AND GPL-2.0-only'},
        'BSD-3-Clause'         => {risk => 1},
        'Apache-2.0'           => {risk => 2, spdx => 'Apache-2.0'}
      }
    };
    is_deeply incompatible_licenses($report), [{licenses => ['GPL-2.0-only', 'Apache-2.0']}],
      'incompatible licenses found';
  };

  subtest 'GPL-2.0-only vs v3 family' => sub {
    my $report = {
      licenses => {
        'GPL-2.0-only'     => {risk => 5, spdx => 'GPL-2.0-only'},
        'GPL-3.0-or-later' => {risk => 5, spdx => 'GPL-3.0-or-later'}
      }
    };
    is_deeply incompatible_licenses($report), [{licenses => ['GPL-2.0-only', 'GPL-3.0-or-later']}],
      'GPL-2.0-only and GPL-3.0-or-later flagged';

    $report = {
      licenses => {
        'GPL-2.0-only'      => {risk => 5, spdx => 'GPL-2.0-only'},
        'AGPL-3.0-or-later' => {risk => 5, spdx => 'AGPL-3.0-or-later'}
      }
    };
    is_deeply incompatible_licenses($report), [{licenses => ['GPL-2.0-only', 'AGPL-3.0-or-later']}],
      'GPL-2.0-only and AGPL-3.0-or-later flagged';
  };

  subtest 'GPL-2.0-only vs CDDL' => sub {
    my $report
      = {
      licenses => {'GPL-2.0-only' => {risk => 5, spdx => 'GPL-2.0-only'}, 'CDDL-1.0' => {risk => 5, spdx => 'CDDL-1.0'}}
      };
    is_deeply incompatible_licenses($report), [{licenses => ['GPL-2.0-only', 'CDDL-1.0']}],
      'GPL-2.0-only and CDDL-1.0 flagged (ZFS-on-Linux case)';

    $report
      = {
      licenses => {'GPL-2.0-only' => {risk => 5, spdx => 'GPL-2.0-only'}, 'CDDL-1.1' => {risk => 5, spdx => 'CDDL-1.1'}}
      };
    is_deeply incompatible_licenses($report), [{licenses => ['GPL-2.0-only', 'CDDL-1.1']}],
      'GPL-2.0-only and CDDL-1.1 flagged';
  };

  subtest 'Classpath exception is not flagged' => sub {
    my $report = {
      licenses => {
        'GPL-2.0 with Classpath exception' => {risk => 5, spdx => 'GPL-2.0-only WITH Classpath-exception-2.0'},
        'Apache-2.0'                       => {risk => 2, spdx => 'Apache-2.0'}
      }
    };
    is_deeply incompatible_licenses($report), [], 'Classpath exception permits combining GPL with Apache-2.0';

    # The Classpath-exception strip must not also remove a sibling GPL term
    # that appears elsewhere in the same SPDX expression.
    $report = {
      licenses => {
        'Mixed'      => {risk => 5, spdx => '(GPL-2.0-only WITH Classpath-exception-2.0) AND GPL-2.0-only'},
        'Apache-2.0' => {risk => 2, spdx => 'Apache-2.0'}
      }
    };
    is_deeply incompatible_licenses($report), [{licenses => ['GPL-2.0-only', 'Apache-2.0']}],
      'plain GPL-2.0-only alongside an excepted variant is still flagged';
  };
};

subtest 'minimal_snippet' => sub {
  subtest 'Minimal snippets' => sub {
    is_deeply minimal_snippet({text => 'foo'}), {'text' => 'foo', start_line => 1}, 'minimal snippet';
    is_deeply minimal_snippet({text => "foo\nbar\nbaz\n", sline => 23}),
      {'text' => "foo\nbar\nbaz\n", start_line => 23}, 'minimal snippet';
    is_deeply minimal_snippet({text => "foo\nbar\nbaz\n", keywords => {}}),
      {'text' => "foo\nbar\nbaz\n", start_line => 1}, 'minimal snippet';
    is_deeply minimal_snippet({text => "foo\nbar\nbaz\n", keywords => {}, matches => {}}),
      {'text' => "foo\nbar\nbaz\n", start_line => 1}, 'minimal snippet';
    is_deeply minimal_snippet({text => "foo\nbar\nbaz\n", keywords => {1 => 1}, matches => {}}),
      {'text' => "foo\nbar\nbaz\n", start_line => 1}, 'minimal snippet';
    is_deeply minimal_snippet({text => "foo", keywords => {0 => 1}, matches => {}}),
      {'text' => 'foo', start_line => 1}, 'minimal snippet';
    is_deeply minimal_snippet({text => "foo", keywords => {0 => 1}, matches => {0 => 1}}),
      {'text' => 'foo', start_line => 1}, 'minimal snippet';
  };

  subtest 'Overlapping license at beginning' => sub {
    is_deeply minimal_snippet({text => "foo\nbar\nbaz\n", keywords => {1 => 24}, matches => {0 => 23}}),
      {'text' => "bar\nbaz\n", start_line => 2}, 'minimal snippet';

    my $snippet = {
      "keywords" => {"30" => 22897},
      "matches"  => {
        "0"  => 28495,
        "1"  => 28495,
        "10" => 28495,
        "11" => 28495,
        "12" => 28495,
        "13" => 28495,
        "14" => 28495,
        "15" => 28495,
        "16" => 28495,
        "17" => 28495,
        "18" => 28495,
        "19" => 28495,
        "2"  => 28495,
        "20" => 28495,
        "21" => 28495,
        "22" => 28495,
        "23" => 28495,
        "3"  => 28495,
        "4"  => 28495,
        "5"  => 28495,
        "6"  => 28495,
        "7"  => 28495,
        "8"  => 28495,
        "9"  => 28495
      },
      "package" => {
        "filename" => "rustc-1.88.0-src/vendor/encoding_rs-0.8.35/src/lib.processed.rs",
        "id"       => 467294,
        "name"     => "rust-1.88"
      },
      "sline" => 16,
      "text"  => "// Redistribution and use in source and binary forms, with or without\n// modification,"
        . " are permitted provided that the following conditions are met:\n//\n// 1. Redistributions"
        . " of source code must retain the above copyright notice, this\n//    list of conditions and"
        . " the following disclaimer.\n//\n// 2. Redistributions in binary form must reproduce the"
        . " above copyright notice,\n//    this list of conditions and the following disclaimer in the"
        . " documentation\n//    and/or other materials provided with the distribution.\n//\n// 3."
        . " Neither the name of the copyright holder nor the names of its\n//    contributors may be"
        . " used to endorse or promote products derived from\n//    this software without specific prior"
        . " written permission.\n//\n// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND"
        . " CONTRIBUTORS \"AS IS\"\n// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED"
        . " TO, THE\n// IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE"
        . " ARE\n// DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE\n//"
        . "FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL\n// DAMAGES"
        . " (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR\n// SERVICES; LOSS OF"
        . " USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER\n// CAUSED AND ON ANY THEORY OF"
        . " LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,\n// OR TORT (INCLUDING NEGLIGENCE OR"
        . " OTHERWISE) ARISING IN ANY WAY OUT OF THE USE\n// OF THIS SOFTWARE, EVEN IF ADVISED OF THE"
        . " POSSIBILITY OF SUCH DAMAGE.\n\n#![cfg_attr(\n    feature = \"cargo-clippy\",\n    "
        . "allow(doc_markdown, inline_always, new_ret_no_self)\n)]\n\n//! encoding_rs is a Gecko-oriented"
        . " Free Software / Open Source implementation\n//! of the"
        . " [Encoding Standard](https://encoding.spec.whatwg.org/) in Rust.\n"
    };
    my $expected_text
      = "\n#![cfg_attr(\n    feature = \"cargo-clippy\",\n    allow(doc_markdown, inline_always, "
      . "new_ret_no_self)\n)]\n\n//! encoding_rs is a Gecko-oriented Free Software / Open Source"
      . " implementation\n//! of the [Encoding Standard](https://encoding.spec.whatwg.org/) in Rust.\n";
    is_deeply minimal_snippet($snippet), {text => $expected_text, start_line => 40},
      'overlapping license at beginning removed';
  };

  subtest 'Multiple overlapping licenses at beginning' => sub {
    my $snippet = {
      text     => "one\ntwo\nthree\nfour\nfive\nsix\nseven\n",
      keywords => {5 => 24},
      matches  => {0 => 23, 2 => 27, 3 => 34}
    };
    is minimal_snippet($snippet)->{text}, "five\nsix\nseven\n", 'minimal snippet';
  };

  subtest 'Overlapping license at end' => sub {
    is minimal_snippet({text => "foo\nbar\nbaz\n", keywords => {1 => 24}, matches => {2 => 23}})->{text}, "foo\nbar",
      'minimal snippet';
  };

  subtest 'Multiple overlapping licenses at end' => sub {
    my $snippet
      = {text => "one\ntwo\nthree\nfour\nfive\nsix\nseven\n", keywords => {2 => 24}, matches => {6 => 23, 4 => 27}};
    is minimal_snippet($snippet)->{text}, "one\ntwo\nthree\nfour", 'minimal snippet';
  };
};

subtest 'smart_edit_snippet' => sub {
  subtest 'No keywords is a no-op' => sub {
    is_deeply smart_edit_snippet({text => "foo\nbar\nbaz\n", sline => 5}),
      {text => "foo\nbar\nbaz\n", start_line => 5, changed => 0}, 'no keywords, no change';
    is_deeply smart_edit_snippet({text => "foo\nbar\nbaz\n", sline => 5, keywords => {}, matches => {}}),
      {text => "foo\nbar\nbaz\n", start_line => 5, changed => 0}, 'empty keywords, no change';
  };

  subtest 'Keywords in the middle, both sides trimmed' => sub {
    my $snippet = {
      text =>
        "line one\nline two\nline three\nKEYWORD HERE\nafter one\nafter two\nafter three\nafter four\nafter five\nafter six\nafter seven\n",
      keywords => {3 => 42},
      sline    => 1
    };
    my $result = smart_edit_snippet($snippet);
    is $result->{text}, "one\nline two\nline three\nKEYWORD HERE\nafter one\nafter two\nafter",
      'trimmed to keyword core with PAD_WORDS padding';
    is $result->{start_line}, 1, 'start line unchanged (still on line 1)';
    is $result->{changed},    1, 'snippet was trimmed';
  };

  subtest 'Padding shorter than PAD_WORDS keeps everything' => sub {
    my $snippet = {text => "ab cd\nKEYWORD\nef gh\n", keywords => {1 => 1}, sline => 1};
    is_deeply smart_edit_snippet($snippet), {text => "ab cd\nKEYWORD\nef gh\n", start_line => 1, changed => 0},
      'short padding kept as-is';
  };

  subtest 'Keyword at the start: only trailing side trimmed' => sub {
    my $snippet = {text => "KEYWORD\none\ntwo three four five six\n", keywords => {0 => 1}, sline => 7};
    my $result  = smart_edit_snippet($snippet);
    is $result->{text},       "KEYWORD\none\ntwo three four five", 'tail trimmed to 5 tokens';
    is $result->{start_line}, 7,                                   'start line preserved';
    is $result->{changed},    1,                                   'snippet was trimmed';
  };

  subtest 'Keyword at the end: only leading side trimmed' => sub {
    my $snippet = {text => "ab cd ef gh ij kl\nmn\nKEYWORD\n", keywords => {2 => 1}, sline => 1};
    my $result  = smart_edit_snippet($snippet);
    is $result->{text},       "ef gh ij kl\nmn\nKEYWORD\n", 'leading trimmed to 5 tokens';
    is $result->{start_line}, 1,                            'start line still 1 (trimmed within first line)';
    is $result->{changed},    1,                            'snippet was trimmed';
  };

  subtest 'Dropping entire leading lines bumps start_line' => sub {
    my $snippet = {
      text     => "alpha\nbeta\ngamma\ndelta\nepsilon\nzeta eta theta iota kappa\nKEYWORD\nlambda mu nu xi omicron\n",
      keywords => {6 => 1},
      sline    => 1
    };
    my $result = smart_edit_snippet($snippet);
    is $result->{text}, "zeta eta theta iota kappa\nKEYWORD\nlambda mu nu xi omicron\n", 'leading whole lines dropped';
    is $result->{start_line}, 6, 'start line bumped by 5 dropped lines';
    is $result->{changed},    1, 'snippet was trimmed';
  };

  subtest 'Delegates overlapping license boundary trim to minimal_snippet' => sub {
    my $snippet = {
      text     => "MATCH ONE\nMATCH TWO\nKEYWORD\ntrail one two three four five six seven\n",
      keywords => {2 => 24},
      matches  => {0 => 23, 1 => 23},
      sline    => 10
    };
    my $result = smart_edit_snippet($snippet);
    is $result->{text}, "KEYWORD\ntrail one two three four",
      'minimal_snippet strips leading match lines, then trailing pad trimmed';
    is $result->{start_line}, 12, 'start line follows minimal_snippet offset';
    is $result->{changed},    1,  'snippet was trimmed';
  };

  subtest 'Collapses copyright lines to $SKIP10' => sub {
    my @cases = (
      ['Copyright (c) 2018 Foo Bar',                               'Copyright (c) $SKIP10'],
      ['Copyright (C) 2024 SUSE LLC',                              'Copyright (C) $SKIP10'],
      ['Copyright © 2019 John Doe',                                'Copyright © $SKIP10'],
      ['Copyright 2016, 2018-2019 Joe Anybody',                    'Copyright $SKIP10'],
      ['Copyright (c) 2003-2018 Foo',                              'Copyright (c) $SKIP10'],
      ['Copyright (c) 2003, 2005, 2018 Foo',                       'Copyright (c) $SKIP10'],
      ['Copyright (c) 2018 Jane Doe <jane@example.org>',           'Copyright (c) $SKIP10'],
      ['Copyright (c) Alice, some rights reserved',                'Copyright (c) $SKIP10'],
      ['Copyright 2018-present Foo Project',                       'Copyright $SKIP10'],
      ['(c) 2018 Foo',                                             '(c) $SKIP10'],
      ['(C) Copyright 2018 Foo',                                   '(C) Copyright $SKIP10'],
      ['© 2019 Example Corporation <https://corp.example.com>',    '© $SKIP10'],
      ['SPDX-FileCopyrightText: 2019 Jane Doe <jane@example.com>', 'SPDX-FileCopyrightText: $SKIP10'],
      ['SPDX-FileCopyrightText: Contributors to Example Project',  'SPDX-FileCopyrightText: $SKIP10'],
      ['SPDX-SnippetCopyrightText: (C) Example Cooperative',       'SPDX-SnippetCopyrightText: $SKIP10'],
    );
    for my $case (@cases) {
      my ($input, $expected) = @$case;
      my $snippet = {text => $input, keywords => {0 => 1}, sline => 1};
      is smart_edit_snippet($snippet)->{text}, $expected, "collapsed: $input";
    }
  };

  subtest 'Preserves comment-marker prefixes on copyright lines' => sub {
    my @cases = (
      ['# Copyright (C) 2024 SUSE LLC', '# Copyright (C) $SKIP10'],
      ['// Copyright (c) 2018 Foo',     '// Copyright (c) $SKIP10'],
      [' * Copyright (c) 2018 Foo',     ' * Copyright (c) $SKIP10'],
      ['## Copyright 2018 Foo',         '## Copyright $SKIP10'],
      ['; Copyright (c) 2018 Foo',      '; Copyright (c) $SKIP10'],
    );
    for my $case (@cases) {
      my ($input, $expected) = @$case;
      my $snippet = {text => $input, keywords => {0 => 1}, sline => 1};
      is smart_edit_snippet($snippet)->{text}, $expected, "preserved prefix on: $input";
    }
  };

  subtest 'Does not collapse non-copyright text' => sub {
    my @cases = (
      'Copyright',                              # bare anchor with nothing after
      'The Copyright Office should be sent',    # anchor not at line start
      'Licensed under the Apache License',      # no copyright anchor at all
      'see Copyright notice above',             # anchor mid-sentence
    );
    for my $line (@cases) {
      my $snippet = {text => $line, keywords => {0 => 1}, sline => 1};
      is smart_edit_snippet($snippet)->{text}, $line, "not collapsed: $line";
    }
  };

  subtest 'Collapses each line of a multi-line copyright stack independently' => sub {
    my $snippet = {
      text     => "Copyright (c) 2018 Foo\nCopyright (c) 2019 Bar\nCopyright (c) 2020 Baz <baz\@x>\n",
      keywords => {0 => 1, 1 => 1, 2 => 1},
      sline    => 1
    };
    is smart_edit_snippet($snippet)->{text}, "Copyright (c) \$SKIP10\nCopyright (c) \$SKIP10\nCopyright (c) \$SKIP10\n",
      'each line collapsed, line count preserved';
  };

  subtest 'Mixed copyright and non-copyright lines' => sub {
    my $snippet = {
      text     => "Copyright (c) 2018 Foo\nLicensed under MIT\nSee Copyright notice\n",
      keywords => {1 => 1},
      sline    => 1
    };
    is smart_edit_snippet($snippet)->{text}, "Copyright (c) \$SKIP10\nLicensed under MIT\nSee Copyright notice\n",
      'only the copyright line is collapsed';
  };

  subtest 'Collapse applies even when nothing else is trimmed' => sub {
    my $snippet = {text => "Copyright (c) 2018 Foo\n", keywords => {0 => 1}, sline => 1};
    my $result  = smart_edit_snippet($snippet);
    is $result->{text},    "Copyright (c) \$SKIP10\n", 'short text still gets copyright collapsed';
    is $result->{changed}, 1,                          'reported as changed';
  };

  subtest 'No-op when text has no copyright lines and no trimming applies' => sub {
    my $snippet = {text => "ab cd\nKEYWORD\nef gh\n", keywords => {1 => 1}, sline => 1};
    my $result  = smart_edit_snippet($snippet);
    is $result->{text},    "ab cd\nKEYWORD\nef gh\n", 'unchanged';
    is $result->{changed}, 0,                         'no change reported';
  };

  subtest 'Combines trimming with copyright collapse' => sub {
    my $snippet = {
      text     => "noise one two three four five\nCopyright (c) 2018 Foo Bar\nKEYWORD\ntrail one two three four five\n",
      keywords => {2 => 1},
      sline    => 1
    };
    my $result = smart_edit_snippet($snippet);
    is $result->{text}, "Copyright (c) \$SKIP10\nKEYWORD\ntrail one two three four",
      'trimmed leading noise and collapsed copyright';
    is $result->{changed}, 1, 'reported as changed';
  };
};

subtest 'spdx_edit_snippet' => sub {
  subtest 'extract_spdx_identifiers finds known identifiers in text order' => sub {
    is_deeply extract_spdx_identifiers('SPDX-License-Identifier: MIT'), ['MIT'],               'simple SPDX line';
    is_deeply extract_spdx_identifiers('first Apache-2.0, then MIT'),   ['Apache-2.0', 'MIT'], 'multiple identifiers';
    is_deeply extract_spdx_identifiers('/* (GPL-2.0-or-later) */'),     ['GPL-2.0-or-later'],  'punctuation boundary';
    is_deeply extract_spdx_identifiers('license=mit;'),                 ['MIT'], 'canonicalizes identifier casing';
  };

  subtest 'extract_spdx_identifiers ignores identifier substrings' => sub {
    is_deeply extract_spdx_identifiers('Mitch'), [], 'MIT is not matched inside Mitch';
    is_deeply extract_spdx_identifiers('XMIT'),  [], 'MIT is not matched with a leading identifier character';
    is_deeply extract_spdx_identifiers('MITch'), [], 'MIT is not matched with a trailing identifier character';
    is_deeply extract_spdx_identifiers('Apache-2.0-only'), [], 'Apache-2.0 is not matched inside a longer SPDX token';
  };

  subtest 'replaces snippet with first SPDX identifier' => sub {
    my $result = spdx_edit_snippet({text => "Copyright\nLicensed under Apache-2.0 or MIT\n", sline => 42});
    is_deeply $result, {text => 'SPDX-License-Identifier: Apache-2.0', start_line => 42, changed => 1},
      'first text-order identifier used';
  };

  subtest 'leaves identifier empty when none is found' => sub {
    my $result = spdx_edit_snippet({text => 'Copyright Mitch', sline => 7});
    is_deeply $result, {text => 'SPDX-License-Identifier: ', start_line => 7, changed => 1}, 'empty identifier tail';
  };

  subtest 'reports unchanged for an exact SPDX replacement' => sub {
    my $result = spdx_edit_snippet({text => 'SPDX-License-Identifier: MIT', sline => 3});
    is_deeply $result, {text => 'SPDX-License-Identifier: MIT', start_line => 3, changed => 0}, 'unchanged';
  };
};

subtest 'report_checksum' => sub {
  subtest 'Specfile license' => sub {
    is report_checksum({}, {}), '1709a28fde41022c01762131a1711875', 'empty report';
    is report_checksum({main => {license => 'MIT'}}, {}), '2d5198bd51f0617d05bf585eb3dc4758', 'specfile license only';
    is report_checksum({main => {license => 'GPL-2.0+'}}, {}), '10371a26faed4e5fe9bac58c3b7b2c25',
      'canonicalize license';
    is report_checksum({main => {license => 'GPL-2.0-or-later'}}, {}), '10371a26faed4e5fe9bac58c3b7b2c25',
      'already caninicallized license';
  };

  subtest 'Dig licenses' => sub {
    is report_checksum({main => {license => 'MIT'}}, {licenses => {'Apache-2.0' => {risk => 2}}}),
      'e91c43850ffd197cee057b93e1f00e0a', 'specfile and dig licenses';
    is report_checksum({main => {license => 'MIT'}}, {licenses => {'Apache-2.0' => {risk => 2}, 'Foo' => {risk => 0}}}),
      'e91c43850ffd197cee057b93e1f00e0a', 'ignore risk 0 licenses';
    is report_checksum({main => {license => 'MIT'}},
      {licenses => {'Apache-2.0' => {risk => 2}, 'BSD-3-Clause' => {risk => 1}}}),
      '9c6028aac6ea076c135afa22bb1af168', 'two dig licenses';
  };

  subtest 'Flags' => sub {
    is report_checksum({main => {license => 'MIT'}}, {licenses => {'Apache-2.0' => {risk => 2, flags => ['patent']}}}),
      '44145ca2199684606c72e444d16c10b5', 'one license flag';
    is report_checksum({main => {license => 'MIT'}},
      {licenses => {'Apache-2.0' => {risk => 2, flags => ['patent', 'trademark']}}}),
      '4bbcf593950c619f3beb693643925559', 'two license flags';
  };

  subtest 'Snippets' => sub {
    is report_checksum(
      {main => {license => 'MIT'}},
      {
        licenses        => {'Apache-2.0' => {risk => 2}, 'BSD-3-Clause' => {risk => 1}},
        missed_snippets => {2            => [[10, 20, 4, '6d5198bd51f0617d05bf585rb3dc475f']]}
      }
      ),
      'e53a9998d69ce6a27f198c415abaf363', 'one snippet present';
    is report_checksum(
      {main => {license => 'MIT'}},
      {
        licenses        => {'Apache-2.0' => {risk => 2}, 'BSD-3-Clause' => {risk => 1}},
        missed_snippets => {
          2 => [[10, 20, 4, '6d5198bd51f0617d05bf585rb3dc475f'], [30, 40, 2, '9d5198bd51f0a17d05af585rb3dc475e']],
          3 => [[10, 20, 1, '1f5198bd51fb617d05bf585rb3dc47ae']]
        }
      }
      ),
      '1715f865453e0ab679688cf0c219fbe4', 'multiple snippets present';
    is report_checksum(
      {main => {license => 'MIT'}},
      {
        licenses        => {'Apache-2.0' => {risk => 2}, 'BSD-3-Clause' => {risk => 1}},
        missed_snippets => {
          2 => [[10, 20, 4, '6d5198bd51f0617d05bf585rb3dc475f'], [30, 40, 2, '9d5198bd51f0a17d05af585rb3dc475e']],
          3 => [[10, 20, 1, '1f5198bd51fb617d05bf585rb3dc47ae'], [30, 40, 4, '6d5198bd51f0617d05bf585rb3dc475f']]
        }
      }
      ),
      '1715f865453e0ab679688cf0c219fbe4', 'duplicate snippet hashes deduped';
  };

  subtest 'License incompatibility' => sub {
    is report_checksum(
      {main => {license => 'MIT'}},
      {
        licenses =>
          {'Apache-2.0' => {risk => 2, spdx => 'Apache-2.0'}, 'GPL-2.0-only' => {risk => 1, spdx => 'GPL-2.0-only'}},
        incompatible_licenses => []
      }
      ),
      '331540e1872a52991c64674c4faf3720', 'no incompatible licenses';
    is report_checksum(
      {main => {license => 'MIT'}},
      {
        licenses =>
          {'Apache-2.0' => {risk => 2, spdx => 'Apache-2.0'}, 'GPL-2.0-only' => {risk => 1, spdx => 'GPL-2.0-only'}},
        incompatible_licenses => [{licenses => ['GPL-2.0-only', 'Apache-2.0']}]
      }
      ),
      '8f0cae03ec2acb4147e89311232dd454', 'include incompatible licenses';
    is report_checksum(
      {main => {license => 'MIT'}},
      {
        licenses =>
          {'Apache-2.0' => {risk => 2, spdx => 'Apache-2.0'}, 'GPL-2.0-only' => {risk => 1, spdx => 'GPL-2.0-only'}},
        incompatible_licenses => [{licenses => ['GPL-2.0-only', 'Apache-2.0']}, {licenses => ['MIT', 'GPL-2.0-only']}]
      }
      ),
      'bd544f815c9eaf725a820f3db2f21c48', 'multiple incompatible licenses';
  };
};

subtest 'summary_delta_score' => sub {
  subtest 'Specfile' => sub {
    is summary_delta_score(
      {id => 1, specfile => 'MIT', missed_snippets => {}, licenses => {}},
      {id => 2, specfile => 'MIT', missed_snippets => {}, licenses => {}}
      ),
      0, 'same specfile';
    is summary_delta_score(
      {id => 1, specfile => 'MIT',      missed_snippets => {}, licenses => {}},
      {id => 2, specfile => 'GPL-2.0+', missed_snippets => {}, licenses => {}}
      ),
      1000, 'different specfile';
  };

  subtest 'Incompatible licenses' => sub {
    is summary_delta_score(
      {id => 1, specfile => 'MIT', missed_snippets => {}, licenses => {}, incompatible_licenses => []},
      {id => 2, specfile => 'MIT', missed_snippets => {}, licenses => {}, incompatible_licenses => []}
      ),
      0, 'no new incompatible licenses';
    is summary_delta_score(
      {
        id                    => 1,
        specfile              => 'MIT',
        missed_snippets       => {},
        licenses              => {},
        incompatible_licenses => [{licenses => ['GPL-2.0-only', 'Apache-2.0']}]
      },
      {
        id                    => 2,
        specfile              => 'MIT',
        missed_snippets       => {},
        licenses              => {},
        incompatible_licenses => [{licenses => ['GPL-2.0-only', 'Apache-2.0']}]
      }
      ),
      0, 'no new incompatible licenses';
    is summary_delta_score(
      {id => 1, specfile => 'MIT', missed_snippets => {}, licenses => {}, incompatible_licenses => []},
      {
        id                    => 2,
        specfile              => 'MIT',
        missed_snippets       => {},
        licenses              => {},
        incompatible_licenses => [{licenses => ['GPL-2.0-only', 'Apache-2.0']}]
      }
      ),
      1000, 'new incompatible licenses';
  };

  subtest 'Snippets' => sub {
    subtest 'Not noteworthy' => sub {
      is summary_delta_score(
        {
          id              => 1,
          specfile        => 'MIT',
          missed_snippets => {
            'Mojolicious-7.25/lib/Mojolicious.pm' => ['541e8cc6ac467ffcbb5b2c27088def98'],
            'Mojolicious-7.25/LICENSE' => ['641e8cc6ac467ffcbb5b2c27088def99', '741e8cc6ac467ffcbb5b2c27088def9a']
          },
          licenses => {}
        },
        {
          id              => 2,
          specfile        => 'MIT',
          missed_snippets => {
            'Mojolicious-7.25/lib/Mojolicious.pm' => ['541e8cc6ac467ffcbb5b2c27088def98'],
            'Mojolicious-7.25/LICENSE' => ['641e8cc6ac467ffcbb5b2c27088def99', '741e8cc6ac467ffcbb5b2c27088def9a']
          },
          licenses => {}
        }
        ),
        0, 'same snippets';
      is summary_delta_score(
        {
          id              => 1,
          specfile        => 'MIT',
          missed_snippets => {
            'Mojolicious-7.25/lib/Mojolicious.pm' => ['541e8cc6ac467ffcbb5b2c27088def98'],
            'Mojolicious-7.25/LICENSE' => ['641e8cc6ac467ffcbb5b2c27088def99', '741e8cc6ac467ffcbb5b2c27088def9a']
          },
          licenses => {}
        },
        {
          id              => 2,
          specfile        => 'MIT',
          missed_snippets => {
            'Mojolicious-7.25/lib/Mojolicious.pm' => ['541e8cc6ac467ffcbb5b2c27088def98'],
            'Mojolicious-7.25/LICENSE'            => ['741e8cc6ac467ffcbb5b2c27088def9a']
          },
          licenses => {}
        }
        ),
        0, 'removed snippet';
      is summary_delta_score(
        {
          id              => 1,
          specfile        => 'MIT',
          missed_snippets => {
            'Mojolicious-7.25/lib/Mojolicious.pm' => ['541e8cc6ac467ffcbb5b2c27088def98'],
            'Mojolicious-7.25/LICENSE'            => ['641e8cc6ac467ffcbb5b2c27088def99']
          },
          licenses => {}
        },
        {
          id              => 2,
          specfile        => 'MIT',
          missed_snippets => {'Mojolicious-7.25/LICENSE' => ['641e8cc6ac467ffcbb5b2c27088def99']},
          licenses        => {}
        }
        ),
        0, 'removed file';
      is summary_delta_score(
        {
          id              => 1,
          specfile        => 'MIT',
          missed_snippets => {
            'Mojolicious-7.25/lib/Mojolicious.pm' => ['541e8cc6ac467ffcbb5b2c27088def98'],
            'Mojolicious-7.25/Changes'            => ['641e8cc6ac467ffcbb5b2c27088def99']
          },
          licenses => {}
        },
        {
          id              => 2,
          specfile        => 'MIT',
          missed_snippets => {
            'Mojolicious-7.25/lib/Mojolicious.pm' => ['541e8cc6ac467ffcbb5b2c27088def98'],
            'Mojolicious-7.25/LICENSE'            => ['641e8cc6ac467ffcbb5b2c27088def99']
          },
          licenses => {}
        }
        ),
        0, 'different file with same snippets';
    };

    subtest 'Noteworthy' => sub {
      is summary_delta_score(
        {
          id              => 1,
          specfile        => 'MIT',
          missed_snippets => {'Mojolicious-7.25/lib/Mojolicious.pm' => ['541e8cc6ac467ffcbb5b2c27088def98']},
          licenses        => {}
        },
        {
          id              => 2,
          specfile        => 'MIT',
          missed_snippets => {
            'Mojolicious-7.25/lib/Mojolicious.pm' => ['541e8cc6ac467ffcbb5b2c27088def98'],
            'Mojolicious-7.25/LICENSE'            => ['641e8cc6ac467ffcbb5b2c27088def99']
          },
          licenses => {}
        }
        ),
        10, 'new file with snippets';
      is summary_delta_score(
        {
          id              => 1,
          specfile        => 'MIT',
          missed_snippets => {'Mojolicious-7.25/lib/Mojolicious.pm' => ['541e8cc6ac467ffcbb5b2c27088def98']},
          licenses        => {}
        },
        {
          id              => 2,
          specfile        => 'MIT',
          missed_snippets => {
            'Mojolicious-7.25/lib/Mojolicious.pm' => ['541e8cc6ac467ffcbb5b2c27088def98'],
            'Mojolicious-7.25/LICENSE'            => ['641e8cc6ac467ffcbb5b2c27088def99'],
            'Mojolicious-7.25/README'             => ['441e8cc6ac467ffcbb5b2c27088def9a']
          },
          licenses => {}
        }
        ),
        20, 'new file with snippets';
      is summary_delta_score(
        {
          id              => 1,
          specfile        => 'MIT',
          missed_snippets => {
            'Mojolicious-7.25/lib/Mojolicious.pm' => ['541e8cc6ac467ffcbb5b2c27088def98'],
            'Mojolicious-7.25/LICENSE'            => ['641e8cc6ac467ffcbb5b2c27088def99']
          },
          licenses => {}
        },
        {
          id              => 2,
          specfile        => 'MIT',
          missed_snippets => {
            'Mojolicious-7.25/lib/Mojolicious.pm' => ['541e8cc6ac467ffcbb5b2c27088def98'],
            'Mojolicious-7.25/LICENSE'            => ['741e8cc6ac467ffcbb5b2c27088def9a']
          },
          licenses => {}
        }
        ),
        10, 'different snippets in same files';
      is summary_delta_score(
        {
          id              => 1,
          specfile        => 'MIT',
          missed_snippets => {
            'Mojolicious-7.25/lib/Mojolicious.pm' => ['541e8cc6ac467ffcbb5b2c27088def98'],
            'Mojolicious-7.25/LICENSE'            => ['641e8cc6ac467ffcbb5b2c27088def99']
          },
          licenses => {}
        },
        {
          id              => 2,
          specfile        => 'MIT',
          missed_snippets => {
            'Mojolicious-7.25/lib/Mojolicious.pm' => ['541e8cc6ac467ffcbb5b2c27088def98'],
            'Mojolicious-7.25/LICENSE'            => [
              '641e8cc6ac467ffcbb5b2c27088def99', '741e8cc6ac467ffcbb5b2c27088def9a',
              'f41e8cc6ac467ffcbb5b2c27088def9f'
            ]
          },
          licenses => {}
        }
        ),
        20, 'additional snippets in same files';
    };
  };

  subtest 'Licenses' => sub {
    subtest 'Not noteworthy' => sub {
      is summary_delta_score(
        {id => 1, specfile => 'MIT', missed_snippets => {}, licenses => {'Apache-2.0' => 5}},
        {id => 2, specfile => 'MIT', missed_snippets => {}, licenses => {'Apache-2.0' => 5}}
        ),
        0, 'same licenses';
      is summary_delta_score(
        {id => 1, specfile => 'MIT', missed_snippets => {}, licenses => {'MIT' => 3, 'Apache-2.0' => 5}},
        {id => 2, specfile => 'MIT', missed_snippets => {}, licenses => {'MIT' => 3}}
        ),
        0, 'License removed';
      is summary_delta_score(
        {id => 1, specfile => 'MIT', missed_snippets => {}, licenses => {'Apache-2.0' => 5}},
        {id => 2, specfile => 'MIT', missed_snippets => {}, licenses => {'Apache-2.0' => 4}}
        ),
        0, 'different risk';
    };

    subtest 'Noteworthy' => sub {
      is summary_delta_score(
        {id => 1, specfile => 'MIT', missed_snippets => {}, licenses => {'Apache-2.0' => 5}},
        {id => 2, specfile => 'MIT', missed_snippets => {}, licenses => {'Apache-2.0' => 5, 'MIT' => 3}}
        ),
        30, 'new license';
      is summary_delta_score(
        {id => 1, specfile => 'MIT', missed_snippets => {}, licenses => {'Apache-2.0' => 5}},
        {
          id              => 2,
          specfile        => 'MIT',
          missed_snippets => {},
          licenses        => {'Apache-2.0' => 5, 'MIT' => 3, 'GPL-2.0+' => 1}
        }
        ),
        40, 'new licenses';
      is summary_delta_score(
        {id => 1, specfile => 'MIT', missed_snippets => {}, licenses => {}},
        {id => 2, specfile => 'MIT', missed_snippets => {}, licenses => {'Apache-2.0' => 5, 'MIT' => 3}}
        ),
        80, 'more new licenses';
    };
  };
};

subtest 'summary_delta' => sub {
  subtest 'Specfile' => sub {
    is summary_delta(
      {id => 1, specfile => 'MIT', missed_snippets => {}, licenses => {}},
      {id => 2, specfile => 'MIT', missed_snippets => {}, licenses => {}}
      ),
      '', 'same specfile';
    is summary_delta(
      {id => 1, specfile => 'MIT',      missed_snippets => {}, licenses => {}},
      {id => 2, specfile => 'GPL-2.0+', missed_snippets => {}, licenses => {}}
      ),
      "Diff to closest match 1\n\n  Spec file license  MIT -> GPL-2.0+\n", 'different specfile';
  };

  subtest 'Incompatible licenses' => sub {
    is summary_delta(
      {id => 1, specfile => 'MIT', missed_snippets => {}, licenses => {}, incompatible_licenses => []},
      {id => 2, specfile => 'MIT', missed_snippets => {}, licenses => {}, incompatible_licenses => []}
      ),
      '', 'no new incompatible licenses';
    is summary_delta(
      {
        id                    => 1,
        specfile              => 'MIT',
        missed_snippets       => {},
        licenses              => {},
        incompatible_licenses => [{licenses => ['GPL-2.0-only', 'Apache-2.0']}]
      },
      {
        id                    => 2,
        specfile              => 'MIT',
        missed_snippets       => {},
        licenses              => {},
        incompatible_licenses => [{licenses => ['GPL-2.0-only', 'Apache-2.0']}]
      }
      ),
      '', 'no new incompatible licenses';
    is summary_delta(
      {id => 1, specfile => 'MIT', missed_snippets => {}, licenses => {'Apache-2.0' => 2}},
      {
        id                    => 2,
        specfile              => 'MIT',
        missed_snippets       => {},
        licenses              => {'Apache-2.0' => 2, 'GPL-2.0-only' => 1},
        incompatible_licenses => [{licenses => ['GPL-2.0-only', 'Apache-2.0']}]
      }
      ),
      "Diff to closest match 1\n\n  New licenses (by risk)\n    1  GPL-2.0-only\n\n"
      . "  Possible license incompatibility\n    GPL-2.0-only, Apache-2.0\n", 'new incompatible licenses';
  };

  subtest 'Snippets' => sub {
    subtest 'Not noteworthy' => sub {
      is summary_delta(
        {
          id              => 1,
          specfile        => 'MIT',
          missed_snippets => {
            'Mojolicious-7.25/lib/Mojolicious.pm' => ['541e8cc6ac467ffcbb5b2c27088def98'],
            'Mojolicious-7.25/LICENSE' => ['641e8cc6ac467ffcbb5b2c27088def99', '741e8cc6ac467ffcbb5b2c27088def9a']
          },
          licenses => {}
        },
        {
          id              => 2,
          specfile        => 'MIT',
          missed_snippets => {
            'Mojolicious-7.25/lib/Mojolicious.pm' => ['541e8cc6ac467ffcbb5b2c27088def98'],
            'Mojolicious-7.25/LICENSE' => ['641e8cc6ac467ffcbb5b2c27088def99', '741e8cc6ac467ffcbb5b2c27088def9a']
          },
          licenses => {}
        }
        ),
        '', 'same snippets';
      is summary_delta(
        {
          id              => 1,
          specfile        => 'MIT',
          missed_snippets => {
            'Mojolicious-7.25/lib/Mojolicious.pm' => ['541e8cc6ac467ffcbb5b2c27088def98'],
            'Mojolicious-7.25/LICENSE' => ['641e8cc6ac467ffcbb5b2c27088def99', '741e8cc6ac467ffcbb5b2c27088def9a']
          },
          licenses => {}
        },
        {
          id              => 2,
          specfile        => 'MIT',
          missed_snippets => {
            'Mojolicious-7.25/lib/Mojolicious.pm' => ['541e8cc6ac467ffcbb5b2c27088def98'],
            'Mojolicious-7.25/LICENSE'            => ['741e8cc6ac467ffcbb5b2c27088def9a']
          },
          licenses => {}
        }
        ),
        '', 'removed snippet';
      is summary_delta(
        {
          id              => 1,
          specfile        => 'MIT',
          missed_snippets => {
            'Mojolicious-7.25/lib/Mojolicious.pm' => ['541e8cc6ac467ffcbb5b2c27088def98'],
            'Mojolicious-7.25/LICENSE'            => ['641e8cc6ac467ffcbb5b2c27088def99']
          },
          licenses => {}
        },
        {
          id              => 2,
          specfile        => 'MIT',
          missed_snippets => {'Mojolicious-7.25/LICENSE' => ['641e8cc6ac467ffcbb5b2c27088def99']},
          licenses        => {}
        }
        ),
        '', 'removed file';
    };

    subtest 'Noteworthy' => sub {

      # The individual files are surfaced as structured data (new_unresolved_files)
      # and badged in the report UI, so summary_delta only reports the count.
      is summary_delta(
        {
          id              => 1,
          specfile        => 'MIT',
          missed_snippets => {'Mojolicious-7.25/lib/Mojolicious.pm' => ['541e8cc6ac467ffcbb5b2c27088def98']},
          licenses        => {}
        },
        {
          id              => 2,
          specfile        => 'MIT',
          missed_snippets => {
            'Mojolicious-7.25/lib/Mojolicious.pm' => ['541e8cc6ac467ffcbb5b2c27088def98'],
            'Mojolicious-7.25/LICENSE'            => ['641e8cc6ac467ffcbb5b2c27088def99']
          },
          licenses => {}
        }
        ),
        "Diff to closest match 1\n\n  New unresolved matches\n", 'single new file';

      my %many = ('Mojolicious-7.25/lib/Mojolicious.pm' => ['541e8cc6ac467ffcbb5b2c27088def98']);
      $many{sprintf 'Mojolicious-7.25/FILE-%02d', $_} = [sprintf '%040d', $_] for 1 .. 6;
      is summary_delta(
        {
          id              => 1,
          specfile        => 'MIT',
          missed_snippets => {'Mojolicious-7.25/lib/Mojolicious.pm' => ['541e8cc6ac467ffcbb5b2c27088def98']},
          licenses        => {}
        },
        {id => 2, specfile => 'MIT', missed_snippets => \%many, licenses => {}}
        ),
        "Diff to closest match 1\n\n  New unresolved matches in 6 files\n", 'multiple new files (count only)';
    };
  };

  subtest 'Licenses' => sub {
    subtest 'Not noteworthy' => sub {
      is summary_delta(
        {id => 1, specfile => 'MIT', missed_snippets => {}, licenses => {'Apache-2.0' => 5}},
        {id => 2, specfile => 'MIT', missed_snippets => {}, licenses => {'Apache-2.0' => 5}}
        ),
        '', 'same licenses';
      is summary_delta(
        {id => 1, specfile => 'MIT', missed_snippets => {}, licenses => {'MIT' => 3, 'Apache-2.0' => 5}},
        {id => 2, specfile => 'MIT', missed_snippets => {}, licenses => {'MIT' => 3}}
        ),
        '', 'License removed';
      is summary_delta(
        {id => 1, specfile => 'MIT', missed_snippets => {}, licenses => {'Apache-2.0' => 5}},
        {id => 2, specfile => 'MIT', missed_snippets => {}, licenses => {'Apache-2.0' => 4}}
        ),
        '', 'different risk';
    };

    subtest 'Noteworthy' => sub {
      is summary_delta(
        {id => 1, specfile => 'MIT', missed_snippets => {}, licenses => {'Apache-2.0' => 5}},
        {id => 2, specfile => 'MIT', missed_snippets => {}, licenses => {'Apache-2.0' => 5, 'MIT' => 3}}
        ),
        "Diff to closest match 1\n\n  New licenses (by risk)\n    3  MIT\n", 'new license';
      is summary_delta(
        {id => 1, specfile => 'MIT', missed_snippets => {}, licenses => {'Apache-2.0' => 5}},
        {
          id              => 2,
          specfile        => 'MIT',
          missed_snippets => {},
          licenses        => {'Apache-2.0' => 5, 'MIT' => 3, 'GPL-2.0+' => 1}
        }
        ),
        "Diff to closest match 1\n\n  New licenses (by risk)\n    3  MIT\n    1  GPL-2.0+\n", 'new licenses';
      is summary_delta(
        {id => 1, specfile => 'MIT', missed_snippets => {}, licenses => {}},
        {id => 2, specfile => 'MIT', missed_snippets => {}, licenses => {'Apache-2.0' => 5, 'MIT' => 3}}
        ),
        "Diff to closest match 1\n\n  New licenses (by risk)\n    5  Apache-2.0\n    3  MIT\n", 'more new licenses';
    };

    subtest 'Name-based (flags ignored)' => sub {

      # Detection is by license name; a license that only gains a flag between
      # versions is the same UI row and is not reported as new.
      is summary_delta(
        {id => 1, specfile => 'MIT', missed_snippets => {}, licenses => {'MIT'        => 3}},
        {id => 2, specfile => 'MIT', missed_snippets => {}, licenses => {'MIT:patent' => 3}}
        ),
        '', 'existing license gaining a flag is not new';
      is summary_delta(
        {id => 1, specfile => 'MIT', missed_snippets => {}, licenses => {'MIT'        => 3}},
        {id => 2, specfile => 'MIT', missed_snippets => {}, licenses => {'MIT:patent' => 3, 'Apache-2.0' => 5}}
        ),
        "Diff to closest match 1\n\n  New licenses (by risk)\n    5  Apache-2.0\n",
        'only the genuinely new name is reported';
    };
  };
};

subtest 'new_unresolved_files' => sub {
  my $files
    = {10 => 'Mojolicious-7.25/lib/Mojolicious.pm', 11 => 'Mojolicious-7.25/LICENSE', 12 => 'Mojolicious-7.25/COPYING'};

  is_deeply new_unresolved_files(
    {id => 1, missed_snippets => {'Mojolicious-7.25/lib/Mojolicious.pm' => ['541e8cc6ac467ffcbb5b2c27088def98']}},
    {
      id              => 2,
      missed_snippets => {
        'Mojolicious-7.25/lib/Mojolicious.pm' => ['541e8cc6ac467ffcbb5b2c27088def98'],
        'Mojolicious-7.25/LICENSE'            => ['641e8cc6ac467ffcbb5b2c27088def99']
      }
    },
    $files
    ),
    [{id => 11, name => 'Mojolicious-7.25/LICENSE'}], 'single new file resolved to its id';

  is_deeply new_unresolved_files(
    {id => 1, missed_snippets => {'Mojolicious-7.25/lib/Mojolicious.pm' => ['541e8cc6ac467ffcbb5b2c27088def98']}},
    {
      id              => 2,
      missed_snippets => {
        'Mojolicious-7.25/lib/Mojolicious.pm' => ['541e8cc6ac467ffcbb5b2c27088def98'],
        'Mojolicious-7.25/LICENSE'            => ['641e8cc6ac467ffcbb5b2c27088def99'],
        'Mojolicious-7.25/COPYING'            => ['741e8cc6ac467ffcbb5b2c27088def9a']
      }
    },
    $files
    ),
    [{id => 12, name => 'Mojolicious-7.25/COPYING'}, {id => 11, name => 'Mojolicious-7.25/LICENSE'}],
    'all new files, sorted by name (no cap)';

  is_deeply new_unresolved_files({id => 1, missed_snippets => {}}, {id => 2, missed_snippets => {}}, $files), [],
    'no new files';
};

subtest 'new_license_names' => sub {
  is_deeply new_license_names({id => 1, licenses => {'Apache-2.0' => 5}},
    {id => 2, licenses => {'Apache-2.0' => 5, 'MIT' => 3, 'GPL-2.0-only' => 5}}),
    ['GPL-2.0-only', 'MIT'], 'new license names, sorted';

  is_deeply new_license_names({id => 1, licenses => {'MIT' => 3}}, {id => 2, licenses => {'MIT:patent' => 3}}), [],
    'a license that only gains a flag is not new';

  is_deeply new_license_names({id => 1, licenses => {'MIT' => 3}},
    {id => 2, licenses => {'MIT:patent' => 3, 'Apache-2.0' => 5}}),
    ['Apache-2.0'], 'flags ignored, only the new name reported';

  is_deeply new_license_names({id => 1, licenses => {'MIT' => 3}}, {id => 2, licenses => {'MIT' => 3}}), [],
    'no new licenses';
};

subtest 'report_shortname' => sub {
  is report_shortname('jemn9u', {}, {}), 'Unknown-0:jemn9u', 'minimal shortname';
  is report_shortname('jemn8u', {main => {license => 'Artistic-2.0'}}, {}), 'Artistic-2.0-0:jemn8u', 'same license';
  is report_shortname('jemn7u', {main => {license => 'MIT OR BSD-2-Clause'}}, {}), 'BSD-2-Clause-0:jemn7u',
    'multiple licenses';
  is report_shortname(
    'jemn6u',
    {main  => {license => 'MIT OR BSD-2-Clause'}},
    {risks => {5       => {'Apache-2.0' => {1 => [13, 13], 2 => [12, 13, 13]}, 'SUSE-NotALicense' => {4 => [10, 11]}}}}
    ),
    'BSD-2-Clause-5:jemn6u', 'license risk';
  is report_shortname(
    'jemn5u',
    {main => {license => 'MIT OR BSD-2-Clause'}},
    {
      risks => {5 => {'Apache-2.0' => {1 => [13, 13], 2 => [12, 13, 13]}, 'SUSE-NotALicense' => {4 => [10, 11]}}},
      missed_files => {12 => [9, 0, undef], 14 => [9, 0, undef], 8 => [9, 0, undef], 9 => [9, 0, undef]}
    }
    ),
    'BSD-2-Clause-9:jemn5u', 'snippet risk';
  is report_shortname(
    'jemn5u',
    {main => {license => 'MIT OR BSD-2-Clause'}},
    {
      risks => {3 => {'Apache-2.0' => {1 => [13, 13], 2 => [12, 13, 13]}, 'GPL-2.0' => {3 => [10, 11]}}},
      incompatible_licenses => [{licenses => ['GPL-2.0', 'Apache-2.0']}]
    }
    ),
    'BSD-2-Clause-9:jemn5u', 'incompatible license risk';
};

subtest 'should_fold_snippet' => sub {
  my $cfg = {enabled => 1, threshold => 0.9, min_margin => 0.15, max_risk => 5};

  # A confident, classified, current-version snippet whose closest pattern is a low-risk license
  my %snippet = (license => 1, likelyness => 0.97, second_match => 0.4, score_version => SNIPPET_SCORE_VERSION);
  my $pattern = {license => 'MIT', risk => 4};

  ok should_fold_snippet($cfg, \%snippet, $pattern), 'confident, low-risk, current-version snippet folds';

  subtest 'configuration gating' => sub {
    ok !should_fold_snippet({%$cfg, enabled => 0}, \%snippet, $pattern), 'never folds when disabled';
    ok !should_fold_snippet(undef,                 \%snippet, $pattern), 'never folds without config';
  };

  subtest 'snippet gating' => sub {
    ok !should_fold_snippet($cfg, {%snippet, license       => 0},   $pattern), 'needs the legal-text classifier flag';
    ok !should_fold_snippet($cfg, {%snippet, score_version => 0},   $pattern), 'needs the current score version';
    ok !should_fold_snippet($cfg, {%snippet, likelyness    => 0.8}, $pattern), 'needs to clear the threshold';
    ok !should_fold_snippet($cfg, {%snippet, second_match  => 0.9}, $pattern), 'needs a margin over the runner-up';
  };

  subtest 'pattern gating' => sub {
    ok !should_fold_snippet($cfg, \%snippet, undef), 'needs a closest pattern';
    ok !should_fold_snippet($cfg, \%snippet, {license => '', risk => 4}), 'ignores empty-license (keyword) patterns';
    ok !should_fold_snippet($cfg, \%snippet, {license => 'GPL-3.0-or-later', risk => 6}),
      'never folds a license above max_risk';
    ok should_fold_snippet($cfg, \%snippet, {license => 'GPL-2.0-or-later', risk => 5}), 'folds at exactly max_risk';
  };
};

subtest 'should_clear_boilerplate' => sub {
  my $cfg = {enabled => 1, clear_threshold => 0.97};

  # Recognized license boilerplate: high containment, ANY margin, any risk - we assert nothing
  my %snippet = (license => 1, likelyness => 0.98, second_match => 0.97, score_version => SNIPPET_SCORE_VERSION);
  my $pattern = {license => 'GPL-2.0-or-later', risk => 6};

  ok should_clear_boilerplate($cfg, \%snippet, $pattern),
    'high-containment legal text clears regardless of margin/risk';

  subtest 'configuration gating' => sub {
    ok !should_clear_boilerplate({enabled => 1, clear_threshold => 0},    \%snippet, $pattern), 'threshold 0 disables';
    ok !should_clear_boilerplate({enabled => 0, clear_threshold => 0.97}, \%snippet, $pattern), 'disabled feature';
    ok !should_clear_boilerplate(undef, \%snippet, $pattern), 'no config';
  };

  subtest 'snippet/pattern gating' => sub {
    ok !should_clear_boilerplate($cfg, {%snippet, license       => 0},    $pattern), 'needs the legal-text flag';
    ok !should_clear_boilerplate($cfg, {%snippet, score_version => 0},    $pattern), 'needs the current score version';
    ok !should_clear_boilerplate($cfg, {%snippet, likelyness    => 0.96}, $pattern),
      'below clear_threshold does not clear';
    ok !should_clear_boilerplate($cfg, \%snippet, undef),                      'needs a recognized pattern';
    ok !should_clear_boilerplate($cfg, \%snippet, {license => '', risk => 2}), 'ignores empty-license patterns';
  };

  subtest 'unlike folding, margin and risk are irrelevant' => sub {
    ok should_clear_boilerplate($cfg, {%snippet, second_match => 0.98}, $pattern), 'zero margin still clears';
    ok should_clear_boilerplate($cfg, \%snippet, {license => 'GPL-3.0-or-later', risk => 9}), 'high risk still clears';
  };
};

subtest 'overlapping_licenses' => sub {
  my $spans = [[2, 2, 'GPL-2.0-or-later'], [40, 60, 'MIT'], [70, 70, '']];    # last is a keyword (no license)
  is_deeply overlapping_licenses(2,  8,   $spans), ['GPL-2.0-or-later'], 'overlap at the start of the snippet';
  is_deeply overlapping_licenses(50, 55,  $spans), ['MIT'],              'overlap in the middle of the snippet';
  is_deeply overlapping_licenses(1,  100, [@$spans]), ['GPL-2.0-or-later', 'MIT'],
    'multiple licensed overlaps, deduped+sorted';
  is_deeply overlapping_licenses(65, 100, $spans), [], 'only an empty-license keyword match overlaps -> none';
  is_deeply overlapping_licenses(9,  39,  $spans), [], 'no overlap';
};

subtest 'should_overlap_clear' => sub {
  my $cfg   = {enabled => 1, overlap_clear => 1, overlap_guard => 0.9};
  my $legal = {license => 1, likelyness    => 0, plicense      => undef};

  ok should_overlap_clear($cfg, $legal, ['GPL-2.0-or-later']),
    'legal snippet over a licensed match clears (noise residual)';
  ok !should_overlap_clear($cfg, $legal,                        []),      'no licensed overlap -> no clear';
  ok !should_overlap_clear($cfg, {%$legal, license => 0},       ['MIT']), 'non-legal snippet -> no clear';
  ok !should_overlap_clear({%$cfg, overlap_clear => 0}, $legal, ['MIT']), 'disabled toggle -> no clear';
  ok !should_overlap_clear({%$cfg, enabled => 0},       $legal, ['MIT']), 'feature disabled -> no clear';

  # Guard: a snippet that itself strongly resembles a license outside the overlap set is kept
  ok !should_overlap_clear($cfg, {license => 1, likelyness => 0.97, plicense => 'Apache-2.0'}, ['GPL-2.0-or-later']),
    'resembles a different license at >= guard -> kept for review';
  ok should_overlap_clear($cfg, {license => 1, likelyness => 0.97, plicense => 'GPL-2.0-or-later'},
    ['GPL-2.0-or-later']), 'resembles a license it already overlaps -> still clears';
  ok should_overlap_clear($cfg, {license => 1, likelyness => 0.5, plicense => 'Apache-2.0'}, ['GPL-2.0-or-later']),
    'only weakly resembles a different license (< guard) -> clears';
};

subtest 'should_cover_snippet' => sub {
  my $cfg = {enabled => 1, cover_scope => 'file'};

  # Legal-text snippet whose closest license (risk 2) is already covered by a concrete license at >= risk
  my %snippet = (license => 1, score_version => SNIPPET_SCORE_VERSION, plicense => 'MIT', prisk => 2);

  ok should_cover_snippet($cfg, \%snippet, 3), 'lower-risk concrete coverage clears the fragment';
  ok should_cover_snippet($cfg, \%snippet, 2), 'coverage at exactly the fragment risk clears';

  subtest 'configuration gating' => sub {
    ok !should_cover_snippet({%$cfg, cover_scope => 'off'},         \%snippet, 3), 'cover_scope off -> no clear';
    ok !should_cover_snippet({enabled => 0, cover_scope => 'file'}, \%snippet, 3), 'feature disabled -> no clear';
    ok !should_cover_snippet(undef,                                 \%snippet, 3), 'no config -> no clear';
  };

  subtest 'snippet gating' => sub {
    ok !should_cover_snippet($cfg, {%snippet, license       => 0}, 3), 'needs the legal-text flag';
    ok !should_cover_snippet($cfg, {%snippet, score_version => 0}, 3), 'needs the current score version';
  };

  subtest 'coverage gating' => sub {
    ok !should_cover_snippet($cfg, \%snippet, undef), 'no concrete coverage in scope -> kept';
    ok !should_cover_snippet($cfg, \%snippet, 1),     'coverage riskier-than? no: fragment risk 2 > cover 1 -> kept';
  };

  subtest 'risk-monotonic guard' => sub {
    my %high = (%snippet, plicense => 'GPL-3.0-or-later', prisk => 5);
    ok !should_cover_snippet($cfg, \%high, 2), 'fragment resembling a higher-risk license than coverage -> kept';
    ok should_cover_snippet($cfg,  \%high, 5), 'same higher risk on both sides -> clears';
  };

  subtest 'no closest license means pure keyword noise (risk 0)' => sub {
    my %keyword = (license => 1, score_version => SNIPPET_SCORE_VERSION, plicense => '', prisk => undef);
    ok should_cover_snippet($cfg, \%keyword, 1), 'legal-text keyword noise in a licensed scope clears';
  };

  subtest 'catch_all closest license in a license file needs high similarity to clear' => sub {

    # In a license file, a grab-bag closest match (e.g. "Any CLA") has an unreliable risk read (the
    # bucket spans many risks), so risk-monotonicity is not trusted: the fragment clears only when its
    # similarity is high enough that it genuinely IS that boilerplate. A weak, ambiguous match is kept -
    # the open-webui LICENSE case, novel terms scoring 0.63 against "Any CLA".
    my %weak = (
      license         => 1,
      score_version   => SNIPPET_SCORE_VERSION,
      plicense        => 'Any CLA',
      prisk           => 1,
      pcatch_all      => 1,
      likelyness      => 0.63,
      is_license_file => 1
    );
    ok !should_cover_snippet($cfg, \%weak, 5), 'low-similarity grab-bag match in a license file is kept';

    my %strong = (%weak, likelyness => 0.95);
    ok should_cover_snippet($cfg,  \%strong, 5), 'high-similarity grab-bag boilerplate still clears';
    ok !should_cover_snippet($cfg, \%strong, 0), 'risk-monotonicity still applies once past the guard (risk 1 > 0)';

    ok should_cover_snippet({%$cfg, cover_guard => 0.6}, \%weak, 5), 'cover_guard is configurable';

    my %concrete = (%weak, pcatch_all => 0);
    ok should_cover_snippet($cfg, \%concrete, 5), 'a concrete closest license clears regardless of similarity';

    # Outside a license file the same weak grab-bag match is stray notice text and is still cleared
    ok should_cover_snippet($cfg, {%weak, is_license_file => 0}, 5),
      'the same weak grab-bag match in a non-license file still clears';
  };
};

subtest 'is_license_filename' => sub {

  # Every keyword alternative, at both the '^' and '/' anchors
  ok is_license_filename('LICENSE'),       'bare LICENSE at start of path (^ anchor)';
  ok is_license_filename('pkg/LICENSE'),   'LICENSE after a slash';
  ok is_license_filename('pkg/LICENCE'),   'LICENCE (British spelling, the [CS] branch)';
  ok is_license_filename('pkg/COPYING'),   'COPYING';
  ok is_license_filename('pkg/COPYRIGHT'), 'COPYRIGHT';
  ok is_license_filename('pkg/NOTICE'),    'NOTICE';
  ok is_license_filename('pkg/EULA'),      'EULA';
  ok is_license_filename('pkg/LEGAL'),     'LEGAL';
  ok is_license_filename('pkg/UNLICENSE'), 'UNLICENSE';

  # Trailing separators the regex allows after the keyword: '.', '-', or end of string
  ok is_license_filename('redis-8.0.6/LICENSE.txt'), 'LICENSE.txt (dot separator)';
  ok is_license_filename('foo/COPYING.LESSER'),      'COPYING.LESSER';
  ok is_license_filename('foo/LICENSE-2.0.txt'),     'LICENSE-2.0.txt (dash separator)';
  ok is_license_filename('foo/EULA.md'),             'EULA.md';
  ok is_license_filename('foo/license.processed'),   'case-insensitive + Cavil processed variant';

  # Boundaries: the keyword must sit at a path boundary and end at one
  ok !is_license_filename('spdx-0.13.4/src/text/licenses/OGDL-Taiwan-1.0'),
    'license-list reference data named after a license id is not a license file';
  ok !is_license_filename('src/main.rs'),      'ordinary source file';
  ok !is_license_filename('doc/RELICENSE.md'), 'keyword not at a path boundary (prefixed)';
  ok !is_license_filename('foo/LICENSEE.txt'), 'keyword not at a word boundary (suffixed: "licensee")';
  ok !is_license_filename('foo/MIT-LICENSE.txt'),
    'not start-anchored: MIT-LICENSE is deliberately excluded (matches the corpus estimate)';
  ok !is_license_filename('foo/NOTICE_TO_USERS'), 'NOTICE followed by "_" is not a boundary';
};

done_testing;
