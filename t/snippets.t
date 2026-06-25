# Copyright (C) 2018-2020 SUSE LLC
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

use Mojo::Base -strict, -signatures;

use FindBin;
use lib "$FindBin::Bin/lib";

use Test::More;
use Test::Mojo;
use Cavil::Test;
use Cavil::Util       qw(SNIPPET_SCORE_VERSION);
use Cavil::ReportUtil qw(should_fold_snippet should_clear_boilerplate should_overlap_clear);
use Cavil::Model::Snippets;

plan skip_all => 'set TEST_ONLINE to enable this test' unless $ENV{TEST_ONLINE};

my $cavil_test = Cavil::Test->new(online => $ENV{TEST_ONLINE}, schema => 'snippets_test');
my $t          = Test::Mojo->new(Cavil => $cavil_test->default_config);
$cavil_test->package_with_snippets_fixtures($t->app);

subtest 'Unpack and index with the job queue' => sub {
  my $unpack_id = $t->app->minion->enqueue(unpack => [1]);
  $t->app->minion->perform_jobs;

  like $t->app->packages->find(1)->{checksum}, qr/^Unknown-9:\w+/, 'right shortname';

  my $res = $t->app->pg->db->select('snippets', 'text', {}, {order_by => 'text'})->hashes;
  is_deeply(
    $res,
    [
      {
            text => "\nNow complex: The license might\nbe something cool\nbut we would not\nsay what we can do"
          . "\nand what we can not do\nwith the GPL. The problem\nis that if we continue\nthis line and afterwards"
          . "\ntalk again about the GPL,\nit should really be part\nof the same snippet. We don't\nwant GPL to abort it."
      },
      {
        text => "The GPL might be\nsomething cool\nbut we would not\nsay what we can do\nand what we can not do"
          . "\nwith the license.\n"
      },
      {
        text => "The license might be\nsomething cool\nbut we would not\nsay what we can do\nand what we can not do"
          . "\nwith the GPL."
      }
    ]
  );
};

subtest 'resolution + text-search filters and keyset pagination' => sub {
  my $config = {
    %{$cavil_test->default_config},
    snippet_fold => {enabled => 0, threshold => 0.95, min_margin => 0.15, max_risk => 5, clear_threshold => 0.95}
  };
  my $app = Test::Mojo->new(Cavil => $config)->app;
  my $db  = $app->pg->db;

  my $fold_pat = $app->patterns->create(pattern => 'a folded triage marker',    license => 'Triage-Fold', risk => 3);
  my $hirisk   = $app->patterns->create(pattern => 'a high risk triage marker', license => 'Triage-Risk', risk => 9);

  my $n    = 0;
  my $snip = sub (%o) {
    $n++;
    return $db->insert(
      'snippets',
      {
        hash          => "triage-$n-" . ($o{hash} // $n),
        text          => $o{text} // "snippet $n body text",
        package       => 1,
        classified    => $o{classified} // 1,
        license       => $o{license}    // 1,
        approved      => 0,
        confidence    => 100,
        likelyness    => $o{likelyness}    // 0,
        second_match  => $o{second_match}  // 0,
        score_version => $o{score_version} // SNIPPET_SCORE_VERSION,
        like_pattern  => $o{like_pattern}  // $fold_pat->{id}
      },
      {returning => 'id'}
    )->hash->{id};
  };

  # 12 fold-eligible (high score, wide margin) so we can exercise pagination, plus one clear-only
  # (zero margin), one high-risk (fold blocked by max_risk -> clears), and one that resolves to neither.
  my @fold_ids   = map { $snip->(likelyness => 0.99, second_match => 0.5, text => "fold marker body $_") } 1 .. 12;
  my $clear_id   = $snip->(likelyness => 0.99, second_match => 0.99, text => 'clear boilerplate body');
  my $neither_id = $snip->(likelyness => 0.50, second_match => 0.0,  text => 'unresolved noise body');

  my %base = (
    before        => 0,
    confidence    => 100,
    is_classified => 'true',
    is_approved   => 'false',
    is_legal      => 'true',
    not_legal     => 'true',
    timeframe     => 'any',
    resolution    => 'any',
    search        => ''
  );

  subtest 'folded filter + keyset pagination (no total)' => sub {
    my $page1 = $app->snippets->unclassified({%base, resolution => 'fold'});
    is scalar(@{$page1->{snippets}}), 10, 'first page caps at 10';
    ok $page1->{has_more},      'has_more is true when a page is full with more behind it';
    ok !exists $page1->{total}, 'no exact total is computed';

    my $before = $page1->{snippets}[-1]{id};
    my $page2  = $app->snippets->unclassified({%base, resolution => 'fold', before => $before});
    is scalar(@{$page2->{snippets}}), 2, 'second page returns the remaining folded rows';
    ok !$page2->{has_more}, 'has_more is false on the last page';

    my %ids = map { $_->{id} => 1 } @{$page1->{snippets}}, @{$page2->{snippets}};
    is_deeply [sort { $a <=> $b } keys %ids], [sort { $a <=> $b } @fold_ids], 'exactly the folded rows, only';
  };

  subtest 'cleared filter excludes folded, picks up zero-margin + risk-blocked' => sub {
    my $cleared = $app->snippets->unclassified({%base, resolution => 'clear'});
    my %ids     = map { $_->{id} => 1 } @{$cleared->{snippets}};
    ok $ids{$clear_id},     'zero-margin boilerplate clears';
    ok !$ids{$fold_ids[0]}, 'a folded row does not also appear under cleared';
    ok !$ids{$neither_id},  'low-similarity noise is neither folded nor cleared';
  };

  subtest 'full-text search narrows by lexeme' => sub {
    my $hits = $app->snippets->unclassified({%base, search => 'boilerplate'});
    my %ids  = map { $_->{id} => 1 } @{$hits->{snippets}};
    ok $ids{$clear_id},     'search matches the snippet containing the term';
    ok !$ids{$fold_ids[0]}, 'snippets without the term are excluded';

    my $none = $app->snippets->unclassified({%base, search => 'zzzdefinitelynotpresent'});
    is scalar(@{$none->{snippets}}), 0, 'a no-match term returns nothing';
  };

  subtest 'fold + search compose (the proactive-audit path)' => sub {
    my $hits = $app->snippets->unclassified({%base, resolution => 'fold', search => 'marker'});
    ok scalar(@{$hits->{snippets}}) > 0,                       'folded rows containing the term are returned';
    ok !(grep { $_->{id} == $clear_id } @{$hits->{snippets}}), 'the cleared row is excluded by the fold filter';
  };

  subtest 'snippet_resolution_sql contract' => sub {
    my $cfg = {enabled => 0, threshold => 0.95, min_margin => 0.15, max_risk => 5, clear_threshold => 0.97};

    my ($fold_sql, $fold_binds) = Cavil::Model::Snippets::snippet_resolution_sql($cfg, 'fold');
    like $fold_sql, qr/s\.likelyness >= \?/, 'fold predicate references the threshold';
    like $fold_sql, qr/lp\.risk <= \?/,      'fold predicate includes the risk gate';
    is_deeply $fold_binds, [SNIPPET_SCORE_VERSION, 0.95, 0.15, 5], 'fold binds in placeholder order';

    # The filter is "would fold at current thresholds" - enabling/disabling must not change it
    my ($enabled_sql) = Cavil::Model::Snippets::snippet_resolution_sql({%$cfg, enabled => 1}, 'fold');
    is $enabled_sql, $fold_sql, 'fold predicate ignores the enabled flag';

    my ($clear_sql, $clear_binds) = Cavil::Model::Snippets::snippet_resolution_sql($cfg, 'clear');
    like $clear_sql, qr/NOT \(/, 'clear excludes the fold set (fold wins)';
    is $clear_binds->[1], 0.97, 'clear uses clear_threshold';

    my ($off_sql) = Cavil::Model::Snippets::snippet_resolution_sql({%$cfg, clear_threshold => 0}, 'clear');
    is $off_sql, 'false', 'clear matches nothing when clear_threshold is unset';

    my ($no_risk_sql, $no_risk_binds)
      = Cavil::Model::Snippets::snippet_resolution_sql({%$cfg, max_risk => undef}, 'fold');
    unlike $no_risk_sql, qr/lp\.risk/, 'no risk gate when max_risk is undefined';
    is scalar(@$no_risk_binds), 3, 'one fewer bind without the risk gate';
  };

  subtest 'SQL filter matches the Perl gate (drift guard)' => sub {
    my $cfg = $config->{snippet_fold};
    my $all = $db->query(
      'SELECT s.*, lp.license AS plicense, lp.risk AS prisk
         FROM snippets s LEFT JOIN license_patterns lp ON lp.id = s.like_pattern'
    )->hashes;

    for my $kind (qw(fold clear)) {

      # Expected set from the Perl gate, with enabled forced on (the SQL deliberately ignores enabled)
      my %expect;
      for my $s (@$all) {
        my $cfg_on  = {%$cfg, enabled => 1};
        my $pattern = {license => $s->{plicense}, risk => $s->{prisk}};
        my $fold    = should_fold_snippet($cfg_on, $s, $pattern);
        my $ok      = $kind eq 'fold' ? $fold : (should_clear_boilerplate($cfg_on, $s, $pattern) && !$fold);
        $expect{$s->{id}} = 1 if $ok;
      }

      my ($sql, $binds) = Cavil::Model::Snippets::snippet_resolution_sql($cfg, $kind);
      my $rows
        = $db->query("SELECT s.id FROM snippets s LEFT JOIN license_patterns lp ON lp.id = s.like_pattern WHERE $sql",
        @$binds)->hashes;
      my %got = map { $_->{id} => 1 } @$rows;

      is_deeply [sort { $a <=> $b } keys %got], [sort { $a <=> $b } keys %expect],
        "$kind SQL predicate selects exactly what the Perl gate accepts";
    }
  };
};

# The "Cleared" filter must include overlap-cleared snippets and stay in lock-step with the Perl gates
# (the SQL and Perl are duplicate implementations of the same decision, so this guard is load-bearing).
subtest 'clear filter incl. overlap matches the Perl gates (drift guard)' => sub {
  my $ct     = Cavil::Test->new(online => $ENV{TEST_ONLINE}, schema => 'snippets_overlap_drift_test');
  my $config = {
    %{$ct->default_config},
    snippet_fold => {
      enabled         => 0,
      threshold       => 0.95,
      min_margin      => 0.15,
      max_risk        => 5,
      clear_threshold => 0.95,
      overlap_clear   => 1,
      overlap_guard   => 0.9
    }
  };
  my $cfg = $config->{snippet_fold};
  my $app = Test::Mojo->new(Cavil => $config)->app;
  $ct->package_with_snippets_fixtures($app);
  $app->minion->enqueue(unpack => [1]);
  $app->minion->perform_jobs;
  my $db = $app->pg->db;

  my $gpl    = $db->query("SELECT id FROM license_patterns WHERE license = 'GPL' LIMIT 1")->hash->{id};
  my $apache = $app->patterns->create(pattern => 'a distinct apache drift marker text', license => 'Apache-2.0')->{id};
  $db->query('UPDATE license_patterns SET risk = 4 WHERE id = ?', $apache);
  my $mf = $db->query('SELECT id FROM matched_files WHERE package = 1 LIMIT 1')->hash->{id};

  # Build one snippet per case: a file_snippets row at a distinct line range, optionally with an
  # overlapping licensed match on its first line. classified=TRUE throughout (the page only lists
  # classified snippets), so the comparison isolates the fold/clear/overlap logic.
  my $line = 0;
  my $mk   = sub (%o) {
    $line += 100;
    my $sid = $db->insert(
      'snippets',
      {
        hash          => "drift-$line",
        text          => "drift snippet $line",
        package       => 1,
        classified    => 1,
        license       => (exists $o{legal} ? $o{legal} : 1),
        approved      => 0,
        confidence    => 100,
        likelyness    => $o{likelyness}    // 0,
        second_match  => $o{second_match}  // 0,
        score_version => $o{score_version} // 0,
        like_pattern  => $o{like_pattern}
      },
      {returning => 'id'}
    )->hash->{id};
    $db->insert('file_snippets', {package => 1, file => $mf, snippet => $sid, sline => $line, eline => $line + 5});
    $db->insert('pattern_matches',
      {package => 1, file => $mf, pattern => $o{overlap}, sline => $line + 1, eline => $line + 1, ignored => 0})
      if $o{overlap};
    return $sid;
  };

  my $V    = SNIPPET_SCORE_VERSION;
  my %case = (
    clear_noise    => $mk->(overlap => $gpl),                # noise over a match
    clear_same     => $mk->(overlap => $gpl, like_pattern => $gpl,    likelyness => 0.92, score_version => $V),
    keep_diff      => $mk->(overlap => $gpl, like_pattern => $apache, likelyness => 0.92, score_version => $V),
    clear_weakdiff => $mk->(overlap => $gpl, like_pattern => $apache, likelyness => 0.50, score_version => $V),
    no_overlap     => $mk->(),                               # nothing to clear
    nonlegal       => $mk->(overlap => $gpl, legal => 0),    # not legal text
    sim_clear      => $mk->(like_pattern => $gpl, likelyness => 0.99, second_match => 0.99, score_version => $V),
    fold_wins      =>
      $mk->(overlap => $gpl, like_pattern => $gpl, likelyness => 0.99, second_match => 0, score_version => $V)
  );

  # Expected "cleared" set from the Perl gates (enabled forced on; the filter ignores the flag),
  # computing the overlap licenses independently from the database.
  my $cfg_on           = {%$cfg, enabled => 1};
  my $overlap_licenses = sub ($sid) {
    return [
      map { $_->{license} } @{
        $db->query(
          'SELECT DISTINCT lp.license FROM file_snippets fs
             JOIN pattern_matches pm ON pm.file = fs.file AND pm.sline <= fs.eline AND pm.eline >= fs.sline
               AND pm.ignored = false
             JOIN license_patterns lp ON lp.id = pm.pattern AND lp.license <> \'\'
            WHERE fs.snippet = ?', $sid
        )->hashes
      }
    ];
  };
  my %expect;
  for my $s (
    @{
      $db->query(
        'SELECT s.*, lp.license AS plicense, lp.risk AS prisk
       FROM snippets s LEFT JOIN license_patterns lp ON lp.id = s.like_pattern WHERE s.classified'
      )->hashes
    }
    )
  {
    my $pat  = {license => $s->{plicense}, risk => $s->{prisk}};
    my $fold = should_fold_snippet($cfg_on, $s, $pat);
    my $clr  = should_clear_boilerplate($cfg_on, $s, $pat);
    my $ovc  = should_overlap_clear($cfg_on, {%$s, plicense => $s->{plicense}}, $overlap_licenses->($s->{id}));
    $expect{$s->{id}} = 1 if ($clr || $ovc) && !$fold;
  }

  # The SQL clear predicate over the same rows
  my ($sql, $binds) = Cavil::Model::Snippets::snippet_resolution_sql($cfg, 'clear');
  my %got = map { $_->{id} => 1 } @{
    $db->query("SELECT s.id FROM snippets s LEFT JOIN license_patterns lp ON lp.id = s.like_pattern WHERE $sql",
      @$binds)->hashes
  };
  is_deeply [sort { $a <=> $b } keys %got], [sort { $a <=> $b } keys %expect],
    'clear SQL (incl. overlap + guard) selects exactly what the Perl gates accept';

  # Intent checks against the Perl expectation, so a wrong gate is caught even if SQL agrees with it
  ok $expect{$case{clear_noise}},    'noise over a real match clears';
  ok $expect{$case{clear_same}},     'resembling the overlapped license still clears';
  ok $expect{$case{clear_weakdiff}}, 'only weakly resembling a different license clears';
  ok $expect{$case{sim_clear}},      'similarity boilerplate still clears';
  ok !$expect{$case{keep_diff}},     'resembling a different license at >= guard is kept';
  ok !$expect{$case{no_overlap}},    'no overlap and not similar enough -> not cleared';
  ok !$expect{$case{nonlegal}},      'non-legal text -> not cleared';
  ok !$expect{$case{fold_wins}},     'a fold is never reported as cleared';
};

done_testing();
