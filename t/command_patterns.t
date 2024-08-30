# Copyright (C) 2023 SUSE LLC
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

use FindBin;
use lib "$FindBin::Bin/lib";

use Test::More;
use Test::Mojo;
use Cavil::Test;
use Cavil::Command::patterns;

plan skip_all => 'set TEST_ONLINE to enable this test' unless $ENV{TEST_ONLINE};

my $cavil_test = Cavil::Test->new(online => $ENV{TEST_ONLINE}, schema => 'command_patterns_test');
my $config     = $cavil_test->default_config;
my $t          = Test::Mojo->new(Cavil => $config);
my $app        = $t->app;
$cavil_test->no_fixtures($app);

subtest 'Empty database' => sub {
  my $buffer = '';
  {
    open my $handle, '>', \$buffer;
    local *STDOUT = $handle;
    $app->start('patterns');
  }
  like $buffer, qr/0 licenses with 0 patterns/, 'no patterns';
};

subtest 'Patterns added' => sub {
  $cavil_test->mojo_fixtures($app);

  subtest 'All licenses' => sub {
    my $buffer = '';
    {
      open my $handle, '>', \$buffer;
      local *STDOUT = $handle;
      $app->start('patterns');
    }
    like $buffer, qr/4 licenses with 6 patterns/, 'mojo fixture patterns';
  };

  subtest 'Specific license' => sub {
    my $buffer = '';
    {
      open my $handle, '>', \$buffer;
      local *STDOUT = $handle;
      $app->start('patterns', '-l', 'Apache-2.0');
    }
    like $buffer, qr/Apache-2.0 has 2 patterns/, 'Apache-2.0 patterns';
  };
};

subtest 'Check risks' => sub {
  subtest 'Consistent risk assessments' => sub {
    my $buffer = '';
    {
      open my $handle, '>', \$buffer;
      local *STDOUT = $handle;
      $app->start('patterns', '--check-risks');
    }
    is $buffer, '', 'no noteworthy risk assessments';
  };

  subtest 'License with multiple risk assessments' => sub {
    my $patterns = $app->patterns;
    $patterns->create(pattern => 'My test license 1.0', license => 'MyTestLicense-1.0', risk => 7);
    $patterns->create(pattern => 'My license',          license => 'MyTestLicense-1.0', risk => 9);
    $patterns->create(pattern => 'Whatever',            license => 'MyTestLicense-1.0', risk => 7);

    my $buffer = '';
    {
      open my $handle, '>', \$buffer;
      local *STDOUT = $handle;
      $app->start('patterns', '--check-risks');
    }
    like $buffer, qr/MyTestLicense-1.0: 7, 9/, 'multiple risk assessments detected';
  };

  subtest 'Fix risk assessment for license' => sub {
    my $buffer = '';
    {
      open my $handle, '>', \$buffer;
      local *STDOUT = $handle;
      $app->start('patterns', '-l', 'MyTestLicense-1.0', '--fix-risk', '8');
    }
    like $buffer, qr/3 patterns fixed/, 'two patterns fixed';

    $buffer = '';
    {
      open my $handle, '>', \$buffer;
      local *STDOUT = $handle;
      $app->start('patterns', '--check-risks');
    }
    is $buffer, '', 'no noteworthy risk assessments anymore';
  };
};

subtest 'Check unused patterns' => sub {
  subtest 'Two unused patterns' => sub {
    my $buffer = '';
    {
      open my $handle, '>', \$buffer;
      local *STDOUT = $handle;
      $app->start('patterns', '--check-unused', '-l', 'MyTestLicense-1.0');
    }
    like $buffer, qr/7.+8.+My.+test.+license.+8.+8.+My.+license/s, 'both patterns are unused';
  };

  subtest 'Two unused patterns (short preview)' => sub {
    my $buffer = '';
    {
      open my $handle, '>', \$buffer;
      local *STDOUT = $handle;
      $app->start('patterns', '--check-unused', '-l', 'MyTestLicense-1.0', '--preview', '5');
    }
    like $buffer, qr/7.+8.+My.+te\.\.\.14.+8.+8.+My.+li\.\.\.5/s, 'both patterns are unused';
  };

  subtest 'One used and one unused' => sub {
    $app->pg->db->insert('matched_files',   {package => 1, filename => 'test.txt', mimetype => 'text/plain'});
    $app->pg->db->insert('pattern_matches', {file    => 1, package  => 1, pattern => 8, sline => 2, eline => 3});
    $app->pg->db->insert('pattern_matches', {file    => 1, package  => 1, pattern => 9, sline => 2, eline => 3});
    $app->pg->db->query('UPDATE bot_packages SET indexed = NOW() WHERE id = 1');

    subtest 'Unused pattern is visible' => sub {
      my $buffer = '';
      {
        open my $handle, '>', \$buffer;
        local *STDOUT = $handle;
        $app->start('patterns', '--check-unused', '-l', 'MyTestLicense-1.0');
      }
      like $buffer,   qr/7.+8.+My.+test.+license/s, 'first pattern is unused';
      unlike $buffer, qr/8.+8.+My.+license/s,       'second pattern is used';
      unlike $buffer, qr/9.+8.+Whatever/s,          'third pattern is used';
    };

    subtest 'Used pattern is visible' => sub {
      my $buffer = '';
      {
        open my $handle, '>', \$buffer;
        local *STDOUT = $handle;
        $app->start('patterns', '--check-used', '-l', 'MyTestLicense-1.0');
      }
      unlike $buffer, qr/7.+8.+My.+test.+license/s, 'first pattern is unused';
      like $buffer,   qr/8.+1.+8.+My.+license/s,    'second pattern is used';
      like $buffer,   qr/9.+1.+8.+Whatever/s,       'third pattern is used';
    };
  };

  subtest 'Remove unused patterns' => sub {
    my $buffer = '';
    {
      open my $handle, '>', \$buffer;
      local *STDOUT = $handle;
      $app->start('patterns', '--remove-unused', '7');
    }
    is $buffer, '', 'pattern removed';

    $buffer = '';
    {
      open my $handle, '>', \$buffer;
      local *STDOUT = $handle;
      $app->start('patterns', '--check-unused', '-l', 'MyTestLicense-1.0');
    }
    is $buffer, '', 'no unused patterns';

    eval { $app->start('patterns', '--remove-unused', '8') };
    like $@, qr/Pattern 8 is still in use and cannot be removed/, 'patterns still in use cannot be removed';
  };

  subtest 'Remove used patterns' => sub {
    my $before = $app->minion->jobs({task => 'index'})->total;
    my $buffer = '';
    {
      open my $handle, '>', \$buffer;
      local *STDOUT = $handle;
      $app->start('patterns', '--remove-used', '8');
    }
    like $buffer, qr/1 packages need to be reindexed/, 'pattern removed';
    my $after = $app->minion->jobs({task => 'index'})->total;
    ok $before < $after, 'packages will be reindexed';

    $buffer = '';
    {
      open my $handle, '>', \$buffer;
      local *STDOUT = $handle;
      $app->start('patterns', '--check-used', '-l', 'MyTestLicense-1.0');
    }
    unlike $buffer, qr/8.+1.+8.+My.+license/s, 'second pattern has been removed';
    like $buffer,   qr/9.+1.+8.+Whatever/,     'only third pattern remains';
  };
};

subtest 'Show pattern match' => sub {
  my $buffer = '';
  {
    open my $handle, '>', \$buffer;
    local *STDOUT = $handle;
    $app->start('patterns', '--match', '2');
  }
  like $buffer, qr/## Pattern Match/,           'header';
  like $buffer, qr/id: 2/,                      'match id';
  like $buffer, qr/license: MyTestLicense-1.0/, 'license';
  like $buffer, qr/pattern: Whatever/,          'pattern';
  like $buffer, qr/filename: test.txt/,         'filename';
};

subtest 'Inherit SPDX expressions from license name' => sub {
  my $before = $app->pg->db->query('SELECT * FROM license_patterns WHERE id = 1')->hash;

  my $buffer = '';
  {
    open my $handle, '>', \$buffer;
    local *STDOUT = $handle;
    $app->start('patterns', '--inherit-spdx');
  }
  like $buffer, qr/Apache-2\.0: 2 patterns updated/,   'Apache-2.0 patterns updated';
  like $buffer, qr/Artistic-2\.0: 1 patterns updated/, 'Artistic-2.0 patterns updated';

  my $after = $app->pg->db->query('SELECT * FROM license_patterns WHERE id = 1')->hash;
  is $before->{spdx}, '',           'no SPDX expression';
  is $after->{spdx},  'Apache-2.0', 'correct SPDX expression';
};

subtest 'Check SPDX' => sub {
  subtest 'Consistent SPDX expressions' => sub {
    my $buffer = '';
    {
      open my $handle, '>', \$buffer;
      local *STDOUT = $handle;
      $app->start('patterns', '--check-spdx');
    }
    is $buffer, '', 'no noteworthy risk assessments';
  };

  subtest 'License with multiple SPDX expressions' => sub {
    is $app->pg->db->query('UPDATE license_patterns SET spdx = ? WHERE id = 1', 'LicenseRef-Apache-2.0')->rows, 1,
      'one row updated';

    my $buffer = '';
    {
      open my $handle, '>', \$buffer;
      local *STDOUT = $handle;
      $app->start('patterns', '--check-spdx');
    }
    like $buffer, qr/Apache-2.0: Apache-2.0, LicenseRef-Apache-2.0/, 'multiple SPDX expressions detected';
  };
};

subtest 'Check unused ignore patterns' => sub {
  subtest 'No unused ignore patterns' => sub {
    my $buffer = '';
    {
      open my $handle, '>', \$buffer;
      local *STDOUT = $handle;
      $app->start('patterns', '--check-unused-ignore');
    }
    like $buffer, qr/Found 0 unused ignore patterns \(0 total\)/s, 'no patterns';

    $buffer = '';
    {
      open my $handle, '>', \$buffer;
      local *STDOUT = $handle;
      $app->start('patterns', '--remove-unused-ignore');
    }
    like $buffer, qr/No unused ignore patterns found/s, 'no patterns removed';
  };

  subtest 'Two unused ignore patterns' => sub {
    $app->packages->ignore_line({package => 'perl-Moose',  hash => '9be8204dd8bdc31a4d0877aa647f42c8'});
    $app->packages->ignore_line({package => 'perl-Minion', hash => 'ebe8204dd8bdc31a4d0877aa647f42cf'});
    $app->packages->ignore_line({package => 'perl-Minion', hash => 'fbe8204dd8bdc31a4d0877aa647f42c0'});
    my $id = $app->pg->db->query('SELECT id FROM ignored_lines WHERE hash = ?', 'fbe8204dd8bdc31a4d0877aa647f42c0')
      ->hash->{id};
    $app->pg->db->update('pattern_matches', {ignored => 1, ignored_line => $id}, {id => 2});

    subtest 'Check' => sub {
      my $buffer = '';
      {
        open my $handle, '>', \$buffer;
        local *STDOUT = $handle;
        $app->start('patterns', '--check-unused-ignore');

      }
      like $buffer, qr/Found 2 unused ignore patterns \(3 total\)/s, 'two patterns';
    };

    subtest 'Remove' => sub {
      my $buffer = '';
      {
        open my $handle, '>', \$buffer;
        local *STDOUT = $handle;
        $app->start('patterns', '--remove-unused-ignore');
      }
      like $buffer, qr/Removed 2 unused ignore patterns/s, 'two patterns removed';
    };
  };
};

done_testing();
