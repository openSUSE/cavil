# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Mojo::Base -strict;

use FindBin;
use lib "$FindBin::Bin/lib";

use Test::More;
use Test::Mojo;
use Cavil::Test;

plan skip_all => 'set TEST_ONLINE to enable this test'   unless $ENV{TEST_ONLINE};
plan skip_all => 'Spooky::Patterns::XS is not installed' unless eval { require Spooky::Patterns::XS; 1 };
require Cavil::Matcher;

# The rest of the suite runs on the default "cavil" engine; this one boots the whole app on the
# alternative "spooky" engine to prove it is still fully supported, and that both engines resolve
# the same matches on the same files.
my $cavil_test = Cavil::Test->new(online => $ENV{TEST_ONLINE}, schema => 'matcher_switch_test');
my $config     = $cavil_test->default_config;
$config->{matcher} = 'spooky';
my $t = Test::Mojo->new(Cavil => $config);
$cavil_test->mojo_fixtures($t->app);

my $app    = $t->app;
my $db     = $app->pg->db;
my $minion = $app->minion;
my $cache  = $cavil_test->cache_dir;

is $app->config->{matcher},      'spooky', 'configured for the spooky engine';
is Cavil::PatternEngine::name(), 'spooky', 'engine switch is active';

subtest 'Indexing on the spooky engine uses engine-specific caches' => sub {
  $minion->enqueue(unpack => [1]);
  $minion->perform_jobs;
  is $minion->backend->list_jobs(0, 100, {states => ['failed']})->{total}, 0, 'no failed jobs';

  ok -f $cache->child('cavil.tokens'),             'spooky token cache built';
  ok -f $cache->child('cavil.pattern.bag'),        'spooky bag cache built';
  ok !-f $cache->child('cavil.matcher'),           'cavil matcher cache not created';
  ok !-f $cache->child('cavil.pattern.bag.cavil'), 'cavil bag cache not created';

  my $matches = $db->query('SELECT COUNT(*) AS c FROM pattern_matches WHERE package = 1')->hash->{c};
  ok $matches > 0, 'the spooky engine found matches';
};

subtest 'Both engines resolve identical matches on the indexed fixture files' => sub {

  # Load every global pattern into both engines directly (parse_tokens is engine-independent).
  my $spooky = Spooky::Patterns::XS::init_matcher();
  my $cavil  = Cavil::Matcher::init_matcher();
  my $rows   = $db->select('license_patterns', ['id', 'pattern'], {packname => ''});
  while (my $row = $rows->array) {
    my ($id, $pattern) = @$row;
    my $tokens = Spooky::Patterns::XS::parse_tokens($pattern);
    $spooky->add_pattern($id, $tokens);
    $cavil->add_pattern($id, $tokens);
  }

  my $unpacked = $app->packages->pkg_checkout_dir(1)->child('.unpacked');
  my @files    = grep { -f $_ } @{$unpacked->list_tree->to_array};
  ok scalar(@files) > 0, 'fixture has unpacked files to compare';

  my $diffs = 0;
  for my $file (@files) {
    $diffs++ unless _same($spooky->find_matches("$file"), $cavil->find_matches("$file"));
  }
  is $diffs, 0, "engines agree on all @{[scalar @files]} files";
};

subtest 'Cache lifecycle (expire + rebuild) works on the spooky engine' => sub {
  ok -f $cache->child('cavil.tokens'), 'token cache present before removal';

  $t->get_ok('/login')->status_is(302);
  $t->delete_ok('/licenses/remove_pattern/1')->status_is(200)->json_is('' => 'ok');

  ok !-f $cache->child('cavil.tokens'),      'spooky token cache expired on removal';
  ok !-f $cache->child('cavil.pattern.bag'), 'spooky bag cache expired on removal';

  $minion->perform_jobs;
  is $minion->backend->list_jobs(0, 100, {states => ['failed']})->{total}, 0, 'reindex finished cleanly';
  ok -f $cache->child('cavil.tokens'), 'spooky token cache rebuilt';
};

sub _same {
  my ($a, $b) = @_;
  return 0 unless @$a == @$b;
  for my $i (0 .. $#$a) {
    return 0 unless $a->[$i][0] == $b->[$i][0] && $a->[$i][1] == $b->[$i][1] && $a->[$i][2] == $b->[$i][2];
  }
  return 1;
}

done_testing;
