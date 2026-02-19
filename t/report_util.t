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
use Cavil::ReportUtil (qw(estimated_risk incompatible_licenses minimal_snippet report_checksum report_shortname),
  qw( summary_delta summary_delta_score));

subtest 'estimated_risk' => sub {
  subtest 'Risk 0' => sub {
    is estimated_risk(0, 0.10), 8, 'high risk';
    is estimated_risk(0, 0.20), 7, 'high risk';
    is estimated_risk(0, 0.30), 6, 'high risk';
    is estimated_risk(0, 0.40), 5, 'high risk';
    is estimated_risk(0, 0.50), 5, 'high risk';
    is estimated_risk(0, 0.60), 4, 'high risk';
    is estimated_risk(0, 0.70), 4, 'high risk';
    is estimated_risk(0, 0.80), 4, 'high risk';
    is estimated_risk(0, 0.89), 4, 'high risk';
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
    is estimated_risk(1, 0.60), 4, 'high risk';
    is estimated_risk(1, 0.70), 4, 'high risk';
    is estimated_risk(1, 0.80), 4, 'high risk';
    is estimated_risk(1, 0.89), 4, 'high risk';
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
    is estimated_risk(2, 0.70), 4, 'high risk';
    is estimated_risk(2, 0.80), 4, 'high risk';
    is estimated_risk(2, 0.89), 4, 'high risk';
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
    is estimated_risk(3, 0.60), 5, 'high risk';
    is estimated_risk(3, 0.70), 5, 'high risk';
    is estimated_risk(3, 0.80), 4, 'high risk';
    is estimated_risk(3, 0.90), 4, 'high risk';
    is estimated_risk(3, 0.91), 4, 'high risk';
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
    is estimated_risk(4, 0.80), 5, 'high risk';
    is estimated_risk(4, 0.90), 5, 'high risk';
    is estimated_risk(4, 0.91), 4, 'high risk';
    is estimated_risk(4, 0.99), 4, 'high risk';
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
    is estimated_risk(5, 0.90), 5, 'high risk';
    is estimated_risk(5, 0.99), 5, 'high risk';
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
};

subtest 'minimal_snippet' => sub {
  subtest 'Minimal snippets' => sub {
    is minimal_snippet({text => 'foo'}),             'foo',             'minimal snippet';
    is minimal_snippet({text => "foo\nbar\nbaz\n"}), "foo\nbar\nbaz\n", 'minimal snippet';
    is minimal_snippet({text => "foo\nbar\nbaz\n", keywords => {}}), "foo\nbar\nbaz\n", 'minimal snippet';
    is minimal_snippet({text => "foo\nbar\nbaz\n", keywords => {}, matches => {}}), "foo\nbar\nbaz\n",
      'minimal snippet';
    is minimal_snippet({text => "foo\nbar\nbaz\n", keywords => {1 => 1}, matches => {}}), "foo\nbar\nbaz\n",
      'minimal snippet';
    is minimal_snippet({text => "foo", keywords => {0 => 1}, matches => {}}),       'foo', 'minimal snippet';
    is minimal_snippet({text => "foo", keywords => {0 => 1}, matches => {0 => 1}}), 'foo', 'minimal snippet';
  };

  subtest 'Overlapping license at beginning' => sub {
    is minimal_snippet({text => "foo\nbar\nbaz\n", keywords => {1 => 24}, matches => {0 => 23}}), "bar\nbaz\n",
      'minimal snippet';

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
    is minimal_snippet($snippet), $expected_text, 'overlapping license at beginning removed';
  };

  subtest 'Multiple overlapping licenses at beginning' => sub {
    my $snippet = {
      text     => "one\ntwo\nthree\nfour\nfive\nsix\nseven\n",
      keywords => {5 => 24},
      matches  => {0 => 23, 2 => 27, 3 => 34}
    };
    is minimal_snippet($snippet), "five\nsix\nseven\n", 'minimal snippet';
  };

  subtest 'Overlapping license at end' => sub {
    is minimal_snippet({text => "foo\nbar\nbaz\n", keywords => {1 => 24}, matches => {2 => 23}}), "foo\nbar",
      'minimal snippet';
  };

  subtest 'Multiple overlapping licenses at end' => sub {
    my $snippet
      = {text => "one\ntwo\nthree\nfour\nfive\nsix\nseven\n", keywords => {2 => 24}, matches => {6 => 23, 4 => 27}};
    is minimal_snippet($snippet), "one\ntwo\nthree\nfour", 'minimal snippet';
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
        licenses => {'Apache-2.0' => {risk => 2}, 'BSD-3-Clause' => {risk => 1}},
        snippets => {2            => {4    => '6d5198bd51f0617d05bf585rb3dc475f'}}
      }
      ),
      'e53a9998d69ce6a27f198c415abaf363', 'one snippets present';
    is report_checksum(
      {main => {license => 'MIT'}},
      {
        licenses => {'Apache-2.0' => {risk => 2}, 'BSD-3-Clause' => {risk => 1}},
        snippets => {
          2 => {4 => '6d5198bd51f0617d05bf585rb3dc475f', 2 => '9d5198bd51f0a17d05af585rb3dc475e'},
          3 => {1 => '1f5198bd51fb617d05bf585rb3dc47ae'}
        }
      }
      ),
      '7351d8ac9fd4bbdb1cdda1293984c58d', 'one snippets present';
    is report_checksum(
      {main => {license => 'MIT'}},
      {
        licenses => {'Apache-2.0' => {risk => 2}, 'BSD-3-Clause' => {risk => 1}},
        snippets => {
          2 => {4 => '6d5198bd51f0617d05bf585rb3dc475f', 2 => '9d5198bd51f0a17d05af585rb3dc475e'},
          3 => {1 => '1f5198bd51fb617d05bf585rb3dc47ae', 4 => '6d5198bd51f0617d05bf585rb3dc475f'}
        }
      }
      ),
      '7351d8ac9fd4bbdb1cdda1293984c58d', 'exclude duplicate snippets';
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
      "Diff to closest match 1:\n\n  Different spec file license: MIT\n\n", 'different specfile';
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
      "Diff to closest match 1:\n\n  Found new license GPL-2.0-only (risk 1) not present in old report\n\n"
      . "  Found new possible license incompatibility involving: GPL-2.0-only, Apache-2.0\n\n",
      'new incompatible licenses';
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
        "Diff to closest match 1:\n\n  Found new unresolved matches in Mojolicious-7.25/LICENSE\n\n",
        'new file with snippets';
      is summary_delta(
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
            'Mojolicious-7.25/COPYING'            => ['641e8cc6ac467ffcbb5b2c27088def9a']
          },
          licenses => {}
        }
        ),
        "Diff to closest match 1:\n\n  Found new unresolved matches in Mojolicious-7.25/COPYING\n\n",
        'different file with snippets';
      is summary_delta(
        {
          id              => 1,
          specfile        => 'MIT',
          missed_snippets => {
            'Mojolicious-7.25/lib/Mojolicious.pm' => ['541e8cc6ac467ffcbb5b2c27088def98'],
            'Mojolicious-7.25/README'             => ['641e8cc6ac467ffcbb5b2c27088def99']
          },
          licenses => {}
        },
        {
          id              => 2,
          specfile        => 'MIT',
          missed_snippets => {
            'Mojolicious-7.25/lib/Mojolicious.pm' => ['541e8cc6ac467ffcbb5b2c27088def98'],
            'Mojolicious-7.25/README'             => ['741e8cc6ac467ffcbb5b2c27088def9a']
          },
          licenses => {}
        }
        ),
        "Diff to closest match 1:\n\n  Found new unresolved matches in Mojolicious-7.25/README\n\n",
        'different snippets in same files';
      is summary_delta(
        {
          id              => 1,
          specfile        => 'MIT',
          missed_snippets => {
            'Mojolicious-7.25/lib/Mojolicious.pm' => ['541e8cc6ac467ffcbb5b2c27088def98'],
            'Mojolicious-7.25/LEGAL'              => ['641e8cc6ac467ffcbb5b2c27088def99']
          },
          licenses => {}
        },
        {
          id              => 2,
          specfile        => 'MIT',
          missed_snippets => {
            'Mojolicious-7.25/lib/Mojolicious.pm' => ['541e8cc6ac467ffcbb5b2c27088def98'],
            'Mojolicious-7.25/LEGAL'              => [
              '641e8cc6ac467ffcbb5b2c27088def99', '741e8cc6ac467ffcbb5b2c27088def9a',
              'f41e8cc6ac467ffcbb5b2c27088def9f'
            ]
          },
          licenses => {}
        }
        ),
        "Diff to closest match 1:\n\n  Found new unresolved matches in Mojolicious-7.25/LEGAL\n\n",
        'additional snippets in same files';
      is summary_delta(
        {
          id              => 1,
          specfile        => 'MIT',
          missed_snippets => {'Mojolicious-7.25/lib/Mojolicious.pm' => ['541e8cc6ac467ffcbb5b2c27088def98'],},
          licenses        => {}
        },
        {
          id              => 2,
          specfile        => 'MIT',
          missed_snippets => {
            'Mojolicious-7.25/lib/Mojolicious.pm' => ['541e8cc6ac467ffcbb5b2c27088def98'],
            'Mojolicious-7.25/LICENSE'            => ['641e8cc6ac467ffcbb5b2c27088def99'],
            'Mojolicious-7.25/COPYING'            => ['741e8cc6ac467ffcbb5b2c27088def9a']

          },
          licenses => {}
        }
        ),
        "Diff to closest match 1:\n\n  Found new unresolved matches in Mojolicious-7.25/COPYING and 1 other file\n\n",
        'two new files';
      is summary_delta(
        {
          id              => 1,
          specfile        => 'MIT',
          missed_snippets => {'Mojolicious-7.25/lib/Mojolicious.pm' => ['541e8cc6ac467ffcbb5b2c27088def98'],},
          licenses        => {}
        },
        {
          id              => 2,
          specfile        => 'MIT',
          missed_snippets => {
            'Mojolicious-7.25/lib/Mojolicious.pm' => ['541e8cc6ac467ffcbb5b2c27088def98'],
            'Mojolicious-7.25/LICENSE'            => ['641e8cc6ac467ffcbb5b2c27088def99'],
            'Mojolicious-7.25/COPYING'            => ['741e8cc6ac467ffcbb5b2c27088def9a'],
            'Mojolicious-7.25/README'             => ['741e8cc6ac467ffcbb5b2c27088def9a'],
            'Mojolicious-7.25/README.txt'         => ['741e8cc6ac467ffcbb5b2c27088def9e']

          },
          licenses => {}
        }
        ),
        "Diff to closest match 1:\n\n  Found new unresolved matches in Mojolicious-7.25/COPYING and 2 other files\n\n",
        'three new files';
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
        "Diff to closest match 1:\n\n  Found new license MIT (risk 3) not present in old report\n\n", 'new license';
      is summary_delta(
        {id => 1, specfile => 'MIT', missed_snippets => {}, licenses => {'Apache-2.0' => 5}},
        {
          id              => 2,
          specfile        => 'MIT',
          missed_snippets => {},
          licenses        => {'Apache-2.0' => 5, 'MIT' => 3, 'GPL-2.0+' => 1}
        }
        ),
        "Diff to closest match 1:\n\n  Found new license GPL-2.0+ (risk 1) not present in old report\n"
        . "  Found new license MIT (risk 3) not present in old report\n\n", 'new licenses';
      is summary_delta(
        {id => 1, specfile => 'MIT', missed_snippets => {}, licenses => {}},
        {id => 2, specfile => 'MIT', missed_snippets => {}, licenses => {'Apache-2.0' => 5, 'MIT' => 3}}
        ),
        "Diff to closest match 1:\n\n  Found new license Apache-2.0 (risk 5) not present in old report\n"
        . "  Found new license MIT (risk 3) not present in old report\n\n", 'more new licenses';
    };
  };
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

done_testing;
