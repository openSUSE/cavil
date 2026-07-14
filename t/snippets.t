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
use Cavil::Util qw(SNIPPET_SCORE_VERSION);

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

# The Classify Snippets page filters purely on the stored file_snippets.resolution column (computed
# once by resolve_snippets, covered in t/snippet_resolve.t), so here we set it directly and check the
# filter + full-text search + keyset pagination read it correctly.
subtest 'resolution + text-search filters and keyset pagination' => sub {
  my $app = Test::Mojo->new(Cavil => $cavil_test->default_config)->app;
  my $db  = $app->pg->db;
  my $mf  = $db->query('SELECT id FROM matched_files WHERE package = 1 LIMIT 1')->hash->{id};

  my $n    = 0;
  my $line = 0;
  my $snip = sub (%o) {
    $n++;
    $line += 100;
    my $sid = $db->insert(
      'snippets',
      {
        hash          => "triage-$n",
        text          => $o{text} // "snippet $n body",
        package       => 1,
        classified    => 1,
        license       => 1,
        approved      => 0,
        confidence    => 100,
        likelyness    => 0,
        second_match  => 0,
        score_version => SNIPPET_SCORE_VERSION
      },
      {returning => 'id'}
    )->hash->{id};
    $db->insert('file_snippets',
      {package => 1, file => $mf, snippet => $sid, sline => $line, eline => $line + 5, resolution => $o{resolution}});
    return $sid;
  };

  my @fold_ids   = map { $snip->(resolution => 'fold', text => "fold marker body $_") } 1 .. 12;
  my $clear_id   = $snip->(resolution => 'clear',   text => 'clear definitions body');
  my $overlap_id = $snip->(resolution => 'overlap', text => 'overlap notice body');
  my $covered_id = $snip->(resolution => 'covered', text => 'covered fragment body');
  my $none_id    = $snip->(resolution => undef,     text => 'unresolved noise body');

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

  subtest 'cleared filter covers clear, overlap and covered, excludes fold' => sub {
    my %ids = map { $_->{id} => 1 } @{$app->snippets->unclassified({%base, resolution => 'clear'})->{snippets}};
    ok $ids{$clear_id},     'boilerplate-cleared snippet appears under Cleared';
    ok $ids{$overlap_id},   'overlap-cleared snippet appears under Cleared';
    ok $ids{$covered_id},   'covered snippet appears under Cleared';
    ok !$ids{$fold_ids[0]}, 'a folded row does not appear under Cleared';
    ok !$ids{$none_id},     'an unresolved row does not appear under Cleared';
  };

  subtest 'full-text search narrows by lexeme' => sub {
    my %ids = map { $_->{id} => 1 } @{$app->snippets->unclassified({%base, search => 'definitions'})->{snippets}};
    ok $ids{$clear_id},     'search matches the snippet containing the term';
    ok !$ids{$fold_ids[0]}, 'snippets without the term are excluded';

    is scalar(@{$app->snippets->unclassified({%base, search => 'zzzdefinitelynotpresent'})->{snippets}}), 0,
      'a no-match term returns nothing';
  };

  subtest 'fold + search compose (the proactive-audit path)' => sub {
    my $hits = $app->snippets->unclassified({%base, resolution => 'fold', search => 'marker'});
    ok scalar(@{$hits->{snippets}}) > 0,                       'folded rows containing the term are returned';
    ok !(grep { $_->{id} == $clear_id } @{$hits->{snippets}}), 'the cleared row is excluded by the fold filter';
  };

  # Resolution is per occurrence: the same snippet can be folded in one file and unresolved in another.
  # Under a resolution filter the linked occurrence (and the count) must reflect the matching file, not
  # just the most recent occurrence.
  subtest 'resolution filter links to a matching occurrence' => sub {
    my $other = $db->insert(
      'matched_files',
      {package   => 1, filename => 'dir/other file#1.txt', mimetype => 'text/plain'},
      {returning => 'id'}
    )->hash->{id};
    my $sid = $db->insert(
      'snippets',
      {
        hash          => 'per-occ',
        text          => 'shared per-occurrence body',
        package       => 1,
        classified    => 1,
        license       => 1,
        approved      => 0,
        confidence    => 100,
        likelyness    => 0,
        second_match  => 0,
        score_version => SNIPPET_SCORE_VERSION
      },
      {returning => 'id'}
    )->hash->{id};

    # Folded only in the original file ($mf); unresolved in the newer occurrence ($other).
    $db->insert('file_snippets',
      {package => 1, file => $mf, snippet => $sid, sline => 7, eline => 9, resolution => 'fold'});
    $db->insert('file_snippets',
      {package => 1, file => $mf, snippet => $sid, sline => 10, eline => 12, resolution => 'fold'});
    $db->insert('file_snippets',
      {package => 1, file => $other, snippet => $sid, sline => 1, eline => 3, resolution => undef});

    my @rows = grep { $_->{id} == $sid } @{$app->snippets->unclassified({%base, resolution => 'fold'})->{snippets}};
    is scalar @rows, 1, 'the folded filter returns a shared snippet only once';
    my ($row) = @rows;
    ok $row, 'the snippet appears under the Folded filter';
    my $folded_name = $db->select('matched_files', 'filename', {id => $mf})->hash->{filename};
    is $row->{filename}, $folded_name, 'links to the folded occurrence, not the most recent (unresolved) one';
    is $row->{sline},    10,           'with the latest folded occurrence line';
    is $row->{files},    2,            'and counts only the matching (folded) occurrences';

    my ($any) = grep { $_->{id} == $sid } @{$app->snippets->unclassified({%base})->{snippets}};
    is $any->{files}, 3, 'the unfiltered view counts every occurrence';
  };
};

subtest 'snippet_search (impact ranking + detail)' => sub {
  my $app = $t->app;
  my $db  = $app->pg->db;
  my $gpl = $db->query("SELECT id FROM license_patterns WHERE license = 'GPL' LIMIT 1")->hash->{id};

  # A distinctive token isolates these rows from other subtests' snippets on package 1.
  my $mksnip = sub ($tag) {
    $db->insert(
      'snippets',
      {
        hash          => "impact-$tag",
        text          => "ZZIMPACT $tag body licensed under the GPL",
        package       => 1,
        classified    => 1,
        license       => 1,
        likelyness    => 0.7,
        second_match  => 0.1,
        score_version => SNIPPET_SCORE_VERSION,
        like_pattern  => $gpl
      },
      {returning => 'id'}
    )->hash->{id};
  };
  my $a    = $mksnip->('alpha');
  my $b    = $mksnip->('beta');
  my $line = 0;
  my $occ  = sub ($sid, $pkg, $file) {
    $line += 50;
    $db->insert(
      'file_snippets',
      {package   => $pkg, file => $file, snippet => $sid, sline => $line, eline => $line + 4},
      {returning => 'id'}
    )->hash->{id};
  };

  my $mf  = $db->query('SELECT id FROM matched_files WHERE package = 1 LIMIT 1')->hash->{id};
  my $ao1 = $occ->($a, 1, $mf);
  $occ->($a, 1, $mf);    # snippet A: 2 occurrences on package 1
  $occ->($b, 1, $mf);    # snippet B: 1

  # A second package so the distinct-package (reach) metric is exercised
  my $src = $db->query('SELECT source, requesting_user FROM bot_packages WHERE id = 1')->hash;
  my $p2  = $db->insert(
    'bot_packages',
    {
      name            => 'impact-pkg2',
      checkout_dir    => 'impactpkg2',
      source          => $src->{source},
      requesting_user => $src->{requesting_user},
      priority        => 5,
      state           => 'new'
    },
    {returning => 'id'}
  )->hash->{id};
  my $mf2 = $db->insert(
    'matched_files',
    {package   => $p2, filename => 'other/dir/x.txt', mimetype => 'text/plain'},
    {returning => 'id'}
  )->hash->{id};
  $occ->($a, $p2, $mf2);    # snippet A now spans 2 packages, 3 occurrences total

  subtest 'group=text impact ranking' => sub {
    my $r  = $app->snippets->snippet_search({group => 'text', search => 'ZZIMPACT', order => 'occurrences'});
    my %by = map { $_->{snippet_id} => $_ } @{$r->{snippets}};
    is $by{$a}{occurrences},          3,  'A counts all occurrences fleet-wide';
    is $by{$a}{packages},             2,  'A distinct-package (reach) count';
    is $by{$b}{occurrences},          1,  'B occurrence count';
    is $r->{snippets}[0]{snippet_id}, $a, 'ordered by occurrences (A first)';
    ok $by{$a}{closest_license}, 'carries the closest license';
  };

  subtest 'package scope + resolution filter' => sub {
    my %by = map { $_->{snippet_id} => $_ }
      @{$app->snippets->snippet_search({group => 'text', search => 'ZZIMPACT', package_id => 1})->{snippets}};
    is $by{$a}{occurrences}, 2, 'package scope restricts to package 1';

    # Resolve exactly one occurrence -> it drops from the unresolved default
    $db->query('UPDATE file_snippets SET resolution = ? WHERE id = ?', 'covered', $ao1);
    %by = map { $_->{snippet_id} => $_ }
      @{$app->snippets->snippet_search({group => 'text', search => 'ZZIMPACT', package_id => 1})->{snippets}};
    is $by{$a}{occurrences}, 1, 'covered occurrence excluded from unresolved default';

    %by
      = map { $_->{snippet_id} => $_ }
      @{$app->snippets->snippet_search(
        {group => 'text', search => 'ZZIMPACT', package_id => 1, resolution => 'covered'})->{snippets}};
    is $by{$a}{occurrences}, 1, 'resolution=covered finds the covered occurrence';
  };

  subtest 'group=none lists individual occurrences with detail' => sub {

    # Fresh file with only our matches, so detail (overlaps/covered_by) is deterministic
    my $mf3 = $db->insert(
      'matched_files',
      {package   => 1, filename => 'detail/dir/y.txt', mimetype => 'text/plain'},
      {returning => 'id'}
    )->hash->{id};
    my $c = $mksnip->('gamma');
    $db->insert('file_snippets', {package => 1, file => $mf3, snippet => $c, sline => 50, eline => 54});

    my $apache  = $app->patterns->create(pattern => 'zz apache detail marker', license => 'Apache-2.0')->{id};
    my $keyword = $app->patterns->create(pattern => 'zzkeyword tripped here')->{id};    # empty license = keyword
        # Apache match head-abutting the snippet (lines 45-49) and a keyword match inside (line 52)
    $db->insert('pattern_matches',
      {package => 1, file => $mf3, pattern => $apache, sline => 45, eline => 49, ignored => 0});
    $db->insert('pattern_matches',
      {package => 1, file => $mf3, pattern => $keyword, sline => 52, eline => 52, ignored => 0});

    my $r = $app->snippets->snippet_search({group => 'none', package_id => 1, search => 'ZZIMPACT gamma'});
    my ($row) = grep { $_->{snippet_id} == $c } @{$r->{snippets}};
    ok $row, 'group=none returns the occurrence';
    is $row->{file}, 'detail/dir/y.txt', 'with its file path';
    is $row->{line}, 50,                 'and line';
    my ($ov) = grep { $_->{license} eq 'Apache-2.0' } @{$row->{overlaps}};
    ok $ov, 'overlaps lists the abutting Apache match';
    is $ov->{position}, 'head', 'with head position';
    ok((grep { $_ eq 'zzkeyword tripped here' } @{$row->{keywords}}), 'keywords lists the literal keyword token');
    ok((grep { $_ eq 'Apache-2.0' } @{$row->{covered_by}{file}}), 'covered_by.file lists the concrete file license');
  };

  # The backlog is what the report shows as unresolved matches: snippets the classifier has rejected as
  # non-license text (classified = true AND license = false) are dropped, matching Cavil::Model::Reports.
  subtest 'classifier-rejected snippets are excluded' => sub {
    my $mkc = sub ($tag, $classified, $license) {
      my $sid = $db->insert(
        'snippets',
        {
          hash          => "classify-$tag",
          text          => "ZZCLASSIFY $tag body licensed under the GPL",
          package       => 1,
          classified    => $classified,
          license       => $license,
          likelyness    => 0.7,
          second_match  => 0.1,
          score_version => SNIPPET_SCORE_VERSION,
          like_pattern  => $gpl
        },
        {returning => 'id'}
      )->hash->{id};
      $db->insert('file_snippets', {package => 1, file => $mf, snippet => $sid, sline => 900, eline => 904});
      return $sid;
    };
    my $candidate = $mkc->('candidate', 1, 1);    # classified as a license -> shown
    my $pending   = $mkc->('pending',   0, 0);    # not yet classified      -> shown
    my $rejected  = $mkc->('rejected',  1, 0);    # classifier says non-legal -> hidden

    my %by = map { $_->{snippet_id} => $_ }
      @{$app->snippets->snippet_search({group => 'text', search => 'ZZCLASSIFY', package_id => 1})->{snippets}};
    ok $by{$candidate}, 'a confirmed license candidate is listed';
    ok $by{$pending},   'a snippet still pending classification is listed';
    ok !$by{$rejected}, 'a classifier-rejected non-license snippet is excluded';
  };

  # Anti-drift guard: snippet_search must agree with the report's own unresolved set (dig_report's
  # missed_snippets). This is the coupling every past bug broke (embargo, obsolete, classifier), so we
  # assert the two surfaces make the same call for each snippet disposition.
  subtest 'agrees with the report on what is unresolved' => sub {
    my $mk = sub ($tag, $classified, $license, $resolution) {
      my $sid = $db->insert(
        'snippets',
        {
          hash          => "drift-$tag",
          text          => "ZZDRIFT $tag body licensed under the GPL",
          package       => 1,
          classified    => $classified,
          license       => $license,
          likelyness    => 0.7,
          second_match  => 0.1,
          score_version => SNIPPET_SCORE_VERSION,
          like_pattern  => $gpl
        },
        {returning => 'id'}
      )->hash->{id};
      $db->insert('file_snippets',
        {package => 1, file => $mf, snippet => $sid, sline => 10, eline => 12, resolution => $resolution});
      return $sid;
    };
    my $cand = $mk->('cand', 1, 1, undef);     # unresolved license candidate -> shown by both
    my $rej  = $mk->('rej',  1, 0, undef);     # classifier-rejected          -> hidden by both
    my $fold = $mk->('fold', 1, 1, 'fold');    # resolved (folded)            -> hidden by both

    # The report's authoritative unresolved set, as snippet ids (missed_snippets: file -> [[.., id, ..]]).
    my $dig      = $app->reports->dig_report(1);
    my %reported = map { $_->[2] => 1 } map {@$_} values %{$dig->{missed_snippets}};

    # The tool's unresolved set for the same package.
    my %searched
      = map { $_->{snippet_id} => 1 }
      @{$app->snippets->snippet_search({group => 'text', package_id => 1, search => 'ZZDRIFT', limit => 100})
        ->{snippets}};

    is !!$searched{$cand}, !!$reported{$cand}, 'candidate: tool and report agree';
    is !!$searched{$rej},  !!$reported{$rej},  'classifier-rejected: tool and report agree';
    is !!$searched{$fold}, !!$reported{$fold}, 'folded: tool and report agree';
    ok $searched{$cand},  'candidate is shown';
    ok !$searched{$rej},  'classifier-rejected is hidden';
    ok !$searched{$fold}, 'folded is hidden';
  };

  subtest 'pagination' => sub {
    my $r = $app->snippets->snippet_search({group => 'text', search => 'ZZIMPACT', limit => 1});
    is scalar(@{$r->{snippets}}), 1, 'limit honored';
    ok $r->{has_more}, 'has_more set when more remain';
  };
};

# Embargo is a hard requirement: the snippet's own package (snippets.package) is the canonical
# text-level embargo (a snippet stays embargoed until an unembargoed package re-links it, per
# find_or_create), and an occurrence in an embargoed package must never be revealed or counted even
# for an otherwise-unembargoed snippet.
subtest 'snippet_search embargo gates' => sub {
  my $app = $t->app;
  my $db  = $app->pg->db;
  my $gpl = $db->query("SELECT id FROM license_patterns WHERE license = 'GPL' LIMIT 1")->hash->{id};
  my $src = $db->query('SELECT source, requesting_user FROM bot_packages WHERE id = 1')->hash;

  # An embargoed package with its own file, plus a clean file on the unembargoed package 1.
  my $pe = $db->insert(
    'bot_packages',
    {
      name            => 'embargo-pkg',
      checkout_dir    => 'embargopkg',
      source          => $src->{source},
      requesting_user => $src->{requesting_user},
      priority        => 5,
      state           => 'new',
      embargoed       => 1
    },
    {returning => 'id'}
  )->hash->{id};
  my $mfe = $db->insert(
    'matched_files',
    {package   => $pe, filename => 'secret/embargoed.txt', mimetype => 'text/plain'},
    {returning => 'id'}
  )->hash->{id};
  my $mf1 = $db->insert(
    'matched_files',
    {package   => 1, filename => 'clean/public.txt', mimetype => 'text/plain'},
    {returning => 'id'}
  )->hash->{id};

  my $mksnip = sub ($tag, $owner) {
    $db->insert(
      'snippets',
      {
        hash          => "embargo-$tag",
        text          => "ZZEMBARGO $tag body licensed under the GPL",
        package       => $owner,
        classified    => 1,
        license       => 1,
        likelyness    => 0.7,
        second_match  => 0.1,
        score_version => SNIPPET_SCORE_VERSION,
        like_pattern  => $gpl
      },
      {returning => 'id'}
    )->hash->{id};
  };

  # A snippet OWNED by the embargoed package, even with a (leaked) occurrence on the public package.
  my $emb = $mksnip->('owned', $pe);
  $db->insert('file_snippets', {package => $pe, file => $mfe, snippet => $emb, sline => 10, eline => 14});
  $db->insert('file_snippets', {package => 1, file => $mf1, snippet => $emb, sline => 60, eline => 64});

  # An unembargoed snippet with one public occurrence and one inside the embargoed package.
  my $mix = $mksnip->('mixed', 1);
  $db->insert('file_snippets', {package => 1, file => $mf1, snippet => $mix, sline => 70, eline => 74});
  $db->insert('file_snippets', {package => $pe, file => $mfe, snippet => $mix, sline => 20, eline => 24});

  # An Apache match only in the embargoed file, so detail enrichment leaking that occurrence would show up.
  my $apache = $app->patterns->create(pattern => 'zz embargo apache marker', license => 'Apache-2.0')->{id};
  $db->insert('pattern_matches',
    {package => $pe, file => $mfe, pattern => $apache, sline => 18, eline => 22, ignored => 0});

  subtest 'snippet owned by an embargoed package is hidden entirely' => sub {
    my %text = map { $_->{snippet_id} => $_ }
      @{$app->snippets->snippet_search({group => 'text', search => 'ZZEMBARGO'})->{snippets}};
    ok !$text{$emb}, 'embargoed-origin snippet excluded from group=text';
    ok $text{$mix},  'unembargoed snippet still present';

    my @none = grep { $_->{snippet_id} == $emb }
      @{$app->snippets->snippet_search({group => 'none', search => 'ZZEMBARGO'})->{snippets}};
    is scalar(@none), 0, 'embargoed-origin snippet excluded from group=none';
  };

  subtest 'occurrences in an embargoed package are neither counted nor revealed' => sub {
    my ($row)
      = grep { $_->{snippet_id} == $mix }
      @{$app->snippets->snippet_search({group => 'text', search => 'ZZEMBARGO'})->{snippets}};
    is $row->{occurrences}, 1, 'embargoed occurrence excluded from the count';
    is $row->{packages},    1, 'embargoed package excluded from the reach count';

    my @occ = grep { $_->{snippet_id} == $mix }
      @{$app->snippets->snippet_search({group => 'none', search => 'ZZEMBARGO'})->{snippets}};
    is scalar(@occ),  1,                  'only the unembargoed occurrence is listed';
    is $occ[0]{file}, 'clean/public.txt', 'embargoed file path is not revealed';
  };

  subtest 'group=text detail never enriches from an embargoed occurrence' => sub {
    my ($row)
      = grep { $_->{snippet_id} == $mix }
      @{$app->snippets->snippet_search({group => 'text', search => 'ZZEMBARGO', detail => 1})->{snippets}};
    ok $row, 'mixed snippet present with detail';
    ok !(grep { $_->{license} eq 'Apache-2.0' } @{$row->{overlaps} || []}),
      'the embargoed-file Apache overlap is not surfaced';
  };
};

# Obsolete packages are superseded - their unresolved snippets are dead work and must not inflate the
# impact ranking or lead reviewers to packages that no longer need review.
subtest 'snippet_search excludes obsolete packages' => sub {
  my $app = $t->app;
  my $db  = $app->pg->db;
  my $gpl = $db->query("SELECT id FROM license_patterns WHERE license = 'GPL' LIMIT 1")->hash->{id};
  my $src = $db->query('SELECT source, requesting_user FROM bot_packages WHERE id = 1')->hash;

  my $po = $db->insert(
    'bot_packages',
    {
      name            => 'obsolete-pkg',
      checkout_dir    => 'obsoletepkg',
      source          => $src->{source},
      requesting_user => $src->{requesting_user},
      priority        => 5,
      state           => 'new',
      obsolete        => 1
    },
    {returning => 'id'}
  )->hash->{id};
  my $mfo = $db->insert(
    'matched_files',
    {package   => $po, filename => 'stale/gone.txt', mimetype => 'text/plain'},
    {returning => 'id'}
  )->hash->{id};
  my $mfc = $db->insert(
    'matched_files',
    {package   => 1, filename => 'current/live.txt', mimetype => 'text/plain'},
    {returning => 'id'}
  )->hash->{id};

  my $mksnip = sub ($tag, $owner) {
    $db->insert(
      'snippets',
      {
        hash          => "obsolete-$tag",
        text          => "ZZOBSOLETE $tag body licensed under the GPL",
        package       => $owner,
        classified    => 1,
        license       => 1,
        likelyness    => 0.7,
        second_match  => 0.1,
        score_version => SNIPPET_SCORE_VERSION,
        like_pattern  => $gpl
      },
      {returning => 'id'}
    )->hash->{id};
  };

  # One snippet present in both a current and an obsolete package; one present only in the obsolete one.
  my $mix = $mksnip->('mixed', 1);
  $db->insert('file_snippets', {package => 1, file => $mfc, snippet => $mix, sline => 30, eline => 34});
  $db->insert('file_snippets', {package => $po, file => $mfo, snippet => $mix, sline => 40, eline => 44});
  my $dead = $mksnip->('dead', $po);
  $db->insert('file_snippets', {package => $po, file => $mfo, snippet => $dead, sline => 50, eline => 54});

  subtest 'obsolete occurrences are not counted' => sub {
    my %by = map { $_->{snippet_id} => $_ }
      @{$app->snippets->snippet_search({group => 'text', search => 'ZZOBSOLETE'})->{snippets}};
    is $by{$mix}{occurrences}, 1, 'obsolete occurrence excluded from the count';
    is $by{$mix}{packages},    1, 'obsolete package excluded from the reach count';
    ok !$by{$dead}, 'a snippet living only in obsolete packages disappears entirely';
  };

  subtest 'obsolete occurrences are not listed' => sub {
    my @occ = grep { $_->{snippet_id} == $mix }
      @{$app->snippets->snippet_search({group => 'none', search => 'ZZOBSOLETE'})->{snippets}};
    is scalar(@occ),     1,                  'only the current occurrence is listed';
    is $occ[0]{file},    'current/live.txt', 'obsolete file path is not shown';
    is $occ[0]{package}, 1,                  'group=none exposes the actionable package_id';
  };
};

done_testing();
