# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Mojo::Base -strict;

use FindBin;
use lib "$FindBin::Bin/lib";

use Test::More;
use Test::Mojo;
use Cavil::Test;
use Cavil::ReportUtil qw(summary_delta_score);

plan skip_all => 'set TEST_ONLINE to enable this test' unless $ENV{TEST_ONLINE};

my $cavil_test = Cavil::Test->new(online => $ENV{TEST_ONLINE}, schema => 'snippet_attribution_test');
my $t          = Test::Mojo->new(Cavil => $cavil_test->default_config);
$cavil_test->package_with_snippets_fixtures($t->app);

$t->app->minion->enqueue(unpack => [1]);
$t->app->minion->perform_jobs;

my $db      = $t->app->pg->db;
my $pkgs    = $t->app->packages;
my $reports = $t->app->reports;

my $base_file     = $db->select('matched_files', '*', {package => 1})->hashes->[0];
my $base_snippets = $db->select('file_snippets', '*', {package => 1}, {order_by => 'id'})->hashes;

# Mirror the indexed file_snippets onto a sibling matched_files row, with
# either original-first or duplicate-first physical insertion order
sub rebuild_file_snippets {
  my ($pkg_id, $orig_file_id, $orig_filename, $mimetype, $snippet_rows, $reverse) = @_;

  $db->delete('file_snippets', {package => $pkg_id});
  $db->delete('matched_files', {package => $pkg_id, id => {'!=' => $orig_file_id}});

  my $dup_file_id = $db->insert(
    'matched_files',
    {package   => $pkg_id, filename => "$orig_filename.duplicate", mimetype => $mimetype},
    {returning => 'id'}
  )->hash->{id};

  for my $file_id ($reverse ? ($dup_file_id, $orig_file_id) : ($orig_file_id, $dup_file_id)) {
    for my $row (@$snippet_rows) {
      $db->insert(
        'file_snippets',
        {
          package => $pkg_id,
          file    => $file_id,
          snippet => $row->{snippet},
          sline   => $row->{sline},
          eline   => $row->{eline}
        }
      );
    }
  }

  return $dup_file_id;
}

subtest 'Snippet attribution is stable across file_snippets row order' => sub {
  rebuild_file_snippets(1, $base_file->{id}, $base_file->{filename}, $base_file->{mimetype}, $base_snippets, 0);
  my @v1 = sort keys %{$reports->summary(1)->{missed_snippets}};

  rebuild_file_snippets(1, $base_file->{id}, $base_file->{filename}, $base_file->{mimetype}, $base_snippets, 1);
  my @v2 = sort keys %{$reports->summary(1)->{missed_snippets}};

  is_deeply \@v2, \@v1, 'same attribution regardless of insertion order';
};

subtest 'Byte-identical packages have a zero summary_delta_score' => sub {
  my $extra_pid = $t->app->patterns->create(
    pattern   => 'is granted to copy, distribute and/or modify',
    license   => 'GFDL-1.2',
    unique_id => '413430b9-8f04-49d8-93ef-953b68835d99'
  )->{id};
  my $anchor = $base_snippets->[0];

  rebuild_file_snippets(1, $base_file->{id}, $base_file->{filename}, $base_file->{mimetype}, $base_snippets, 0);
  $db->insert(
    'pattern_matches',
    {
      file    => $base_file->{id},
      package => 1,
      pattern => $extra_pid,
      sline   => $anchor->{sline},
      eline   => $anchor->{eline},
      ignored => 0
    }
  );

  my $pkg1    = $pkgs->find(1);
  my $pkg2_id = $pkgs->add(
    name            => $pkg1->{name},
    checkout_dir    => "$pkg1->{checkout_dir}-resubmit",
    api_url         => 'https://api.opensuse.org',
    requesting_user => 1,
    project         => 'devel:languages:perl',
    package         => $pkg1->{name},
    srcmd5          => "$pkg1->{checkout_dir}-resubmit",
    priority        => 5
  );
  $db->query(
    'INSERT INTO bot_reports (package, ldig_report, specfile_report, rolemodel)
     SELECT ?, ldig_report, specfile_report, rolemodel FROM bot_reports WHERE package = ?', $pkg2_id, 1
  );

  my $orig2_id = $db->insert(
    'matched_files',
    {package   => $pkg2_id, filename => $base_file->{filename}, mimetype => $base_file->{mimetype}},
    {returning => 'id'}
  )->hash->{id};
  for my $m (@{$db->select('pattern_matches', '*', {package => 1, file => $base_file->{id}})->hashes}) {
    $db->insert(
      'pattern_matches',
      {
        package      => $pkg2_id,
        file         => $orig2_id,
        pattern      => $m->{pattern},
        sline        => $m->{sline},
        eline        => $m->{eline},
        ignored      => $m->{ignored},
        ignored_line => $m->{ignored_line}
      }
    );
  }
  rebuild_file_snippets($pkg2_id, $orig2_id, $base_file->{filename}, $base_file->{mimetype}, $base_snippets, 1);

  is summary_delta_score($reports->summary(1), $reports->summary($pkg2_id)), 0, 'zero delta';
};

subtest 'Expanded file selection is stable when truncated by max_expanded_files' => sub {
  my $pkg3_id = $pkgs->add(
    name            => 'manyfiles',
    checkout_dir    => 'manyfiles-checkout',
    api_url         => 'https://api.opensuse.org',
    requesting_user => 1,
    project         => 'devel:languages:perl',
    package         => 'manyfiles',
    srcmd5          => 'manyfiles-checkout',
    priority        => 5
  );
  $db->query(
    'INSERT INTO bot_reports (package, ldig_report, specfile_report, rolemodel)
     SELECT ?, ldig_report, specfile_report, rolemodel FROM bot_reports WHERE package = ?', $pkg3_id, 1
  );

  for my $n (1 .. 10) {
    my $file_id = $db->insert(
      'matched_files',
      {package   => $pkg3_id, filename => "file$n.txt", mimetype => 'text/plain'},
      {returning => 'id'}
    )->hash->{id};
    my $snippet_id
      = $db->insert('snippets', {hash => "manyfiles-snippet-$n", text => "snippet text $n"}, {returning => 'id'})
      ->hash->{id};
    $db->insert('file_snippets',
      {package => $pkg3_id, file => $file_id, snippet => $snippet_id, sline => 1, eline => 5});
  }

  $reports->max_expanded_files(3);
  my @first  = sort keys %{$reports->summary($pkg3_id)->{missed_snippets}};
  my @second = sort keys %{$reports->summary($pkg3_id)->{missed_snippets}};

  cmp_ok scalar @first, '<', 10, 'truncated below total file count';
  is_deeply \@second, \@first, 'same files picked across calls';
};

done_testing;
