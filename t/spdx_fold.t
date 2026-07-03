# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Mojo::Base -strict, -signatures;

use FindBin;
use lib "$FindBin::Bin/lib";

use Test::More;
use Test::Mojo;
use Cavil::Test;
use Cavil::Util qw(SNIPPET_SCORE_VERSION);
use Mojo::JSON  qw(decode_json);

plan skip_all => 'set TEST_ONLINE to enable this test' unless $ENV{TEST_ONLINE};

# All license expressions listed anywhere in the SPDX report
sub license_exprs ($body) {
  my $doc = decode_json($body);
  return [map { $_->{simplelicensing_licenseExpression} }
    grep { ($_->{type} // '') eq 'simplelicensing_LicenseExpression' } @{$doc->{'@graph'}}];
}

my $cavil_test = Cavil::Test->new(online => $ENV{TEST_ONLINE}, schema => 'spdx_fold_test');
my $config     = {%{$cavil_test->default_config},
  snippet_fold => {enabled => 1, threshold => 0.9, min_margin => 0.1, max_risk => 9}};
my $t   = Test::Mojo->new(Cavil => $config);
my $app = $t->app;
$cavil_test->spdx_fixtures($app);
my $db = $app->pg->db;

$app->minion->enqueue(unpack => [1]);
$app->minion->perform_jobs;
$t->get_ok('/login')->status_is(302);

subtest 'a folded snippet contributes its license to the SPDX report' => sub {

  # Fold one snippet into a synthetic license whose SPDX id cannot appear from any real match, so
  # its presence in the report proves it came from fold-in.
  my $pattern = $app->patterns->create(pattern => 'a unique foldable license marker phrase', license => 'Fold-Test');
  $db->query('UPDATE license_patterns SET spdx = ?, risk = 2 WHERE id = ?', 'Fold-Test-SPDX', $pattern->{id});
  is $db->query(
    'UPDATE snippets SET classified = TRUE, license = TRUE, like_pattern = ?, likelyness = 0.99, second_match = 0,
       score_version = ? WHERE id = (SELECT min(id) FROM snippets)', $pattern->{id}, SNIPPET_SCORE_VERSION
  )->rows, 1, 'one snippet set up to fold';
  $app->snippets->resolve_snippets(1);    # refresh the stored resolution the SPDX report now reads

  $t->get_ok('/spdx/1')->status_is(408);
  $app->minion->perform_jobs;
  is $app->minion->jobs({states => ['failed']})->total, 0, 'no failed jobs';

  my $exprs = license_exprs($t->get_ok('/spdx/1')->status_is(200)->tx->res->body);
  ok((grep {/\bFold-Test-SPDX\b/} @$exprs), 'folded license is listed for a file');
};

subtest 'a cleared boilerplate snippet asserts no license in the SPDX report' => sub {
  my $ct  = Cavil::Test->new(online => $ENV{TEST_ONLINE}, schema => 'spdx_clear_test');
  my $cfg = {
    %{$ct->default_config},
    snippet_fold => {enabled => 1, threshold => 0.95, min_margin => 0.15, max_risk => 5, clear_threshold => 0.95}
  };
  my $tt = Test::Mojo->new(Cavil => $cfg);
  my $a  = $tt->app;
  my $d  = $a->pg->db;
  $ct->spdx_fixtures($a);
  $a->minion->enqueue(unpack => [1]);
  $a->minion->perform_jobs;
  $tt->get_ok('/login')->status_is(302);

  my $p = $a->patterns->create(pattern => 'a unique clearable license marker phrase', license => 'Clear-Test');
  $d->query('UPDATE license_patterns SET spdx = ?, risk = 2 WHERE id = ?', 'Clear-Test-SPDX', $p->{id});

  # Zero margin so it cannot fold; high containment so it clears -> no license asserted.
  $d->query(
    'UPDATE snippets SET classified = TRUE, license = TRUE, like_pattern = ?, likelyness = 0.99, second_match = 0.99,
       score_version = ? WHERE id = (SELECT min(id) FROM snippets)', $p->{id}, SNIPPET_SCORE_VERSION
  );
  $a->snippets->resolve_snippets(1);

  $tt->get_ok('/spdx/1')->status_is(408);
  $a->minion->perform_jobs;
  my $exprs = license_exprs($tt->get_ok('/spdx/1')->status_is(200)->tx->res->body);
  ok(!(grep {/Clear-Test-SPDX/} @$exprs), 'cleared boilerplate asserts no license');
};

subtest 'an overlap-cleared snippet asserts nothing; the overlapping match still reports its license' => sub {
  my $ct  = Cavil::Test->new(online => $ENV{TEST_ONLINE}, schema => 'spdx_overlap_test');
  my $cfg = {
    %{$ct->default_config},
    snippet_fold => {
      enabled         => 1,
      threshold       => 0.95,
      min_margin      => 0.15,
      max_risk        => 5,
      clear_threshold => 0,
      overlap_clear   => 1,
      overlap_guard   => 0.9
    }
  };
  my $tt = Test::Mojo->new(Cavil => $cfg);
  my $a  = $tt->app;
  my $d  = $a->pg->db;
  $ct->spdx_fixtures($a);
  $a->minion->enqueue(unpack => [1]);
  $a->minion->perform_jobs;
  $tt->get_ok('/login')->status_is(302);

  # A real licensed match overlapping the snippet regions (the SPDX-line-swallowed case). Its SPDX id
  # cannot appear from anywhere else, so its presence proves the match - not the snippet - reports it.
  my $p = $a->patterns->create(pattern => 'a unique overlap match marker phrase', license => 'Overlap-Test');
  $d->query('UPDATE license_patterns SET spdx = ?, risk = 2 WHERE id = ?', 'Overlap-Test-SPDX', $p->{id});
  $d->query(
    'UPDATE snippets SET classified = TRUE, license = TRUE, likelyness = 0, like_pattern = NULL, score_version = 0');
  $d->insert('pattern_matches',
    {package => 1, file => $_->{file}, pattern => $p->{id}, sline => $_->{sline}, eline => $_->{sline}, ignored => 0})
    for $d->query('SELECT file, sline FROM file_snippets WHERE package = 1')->hashes->each;
  $a->snippets->resolve_snippets(1);

  $tt->get_ok('/spdx/1')->status_is(408);
  $a->minion->perform_jobs;
  my $exprs = license_exprs($tt->get_ok('/spdx/1')->status_is(200)->tx->res->body);
  ok((grep {/\bOverlap-Test-SPDX\b/} @$exprs), 'the overlapping match still reports its license');
};

done_testing;
