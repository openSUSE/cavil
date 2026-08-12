# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Mojo::Base -strict, -signatures;

use FindBin;
use lib "$FindBin::Bin/lib";

use Test::More;
use Test::Mojo;
use Cavil::Test;

plan skip_all => 'set TEST_ONLINE to enable this test' unless $ENV{TEST_ONLINE};

my $cavil_test = Cavil::Test->new(online => $ENV{TEST_ONLINE}, schema => 'command_eval_fold_test');
my $t          = Test::Mojo->new(Cavil => $cavil_test->default_config);
$cavil_test->just_patterns_fixtures($t->app);

subtest 'eval_fold prints a calibration table' => sub {
  my $buffer = '';
  {
    open my $handle, '>', \$buffer;
    local *STDOUT = $handle;
    $t->app->start('eval_fold', '--folds', '2', '--distinctive', '0', '--min-distinctive', '1');
  }
  like $buffer, qr/Parameters: k=3/,               'echoes parameters';
  like $buffer, qr/Probes scored/,                 'runs the held-out evaluation';
  like $buffer, qr/threshold.*precision.*recall/s, 'prints the precision/recall table';
};

done_testing;
