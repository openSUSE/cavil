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

  subtest 'cleared filter covers both clear and overlap, excludes fold' => sub {
    my %ids = map { $_->{id} => 1 } @{$app->snippets->unclassified({%base, resolution => 'clear'})->{snippets}};
    ok $ids{$clear_id},     'boilerplate-cleared snippet appears under Cleared';
    ok $ids{$overlap_id},   'overlap-cleared snippet appears under Cleared';
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

done_testing();
