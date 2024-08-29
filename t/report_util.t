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
use Cavil::ReportUtil qw(estimated_risk report_checksum report_shortname summary_delta summary_delta_score);

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
        250, 'new file with snippets';
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
        150, 'different file with snippets';
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
        20, 'different snippets in same files';
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
        40, 'additional snippets in same files';
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
        "Diff to closest match 1:\n\n  New unresolved matches in Mojolicious-7.25/LICENSE\n\n",
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
            'Mojolicious-7.25/COPYING'            => ['641e8cc6ac467ffcbb5b2c27088def99']
          },
          licenses => {}
        }
        ),
        "Diff to closest match 1:\n\n  New unresolved matches in Mojolicious-7.25/COPYING\n\n",
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
        "Diff to closest match 1:\n\n  New unresolved matches in Mojolicious-7.25/README\n\n",
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
        "Diff to closest match 1:\n\n  New unresolved matches in Mojolicious-7.25/LEGAL\n\n",
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
        "Diff to closest match 1:\n\n  New unresolved matches in Mojolicious-7.25/COPYING and 1 file more\n\n",
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
            'Mojolicious-7.25/README'             => ['741e8cc6ac467ffcbb5b2c27088def9a']

          },
          licenses => {}
        }
        ),
        "Diff to closest match 1:\n\n  New unresolved matches in Mojolicious-7.25/COPYING and 2 files more\n\n",
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
  is report_shortname('jemn9u', {}, {}), 'Error-0:jemn9u', 'minimal shortname';
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
};

done_testing;
