# Copyright (C) 2026 SUSE LLC
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

plan skip_all => 'set TEST_ONLINE to enable this test' unless $ENV{TEST_ONLINE};

my $cavil_test = Cavil::Test->new(online => $ENV{TEST_ONLINE}, schema => 'snippet_context_test');
my $t          = Test::Mojo->new(Cavil => $cavil_test->default_config);
my $app        = $t->app;
$cavil_test->no_fixtures($app);

# The identical license block (with a keyword-less "license" pattern match) is
# what produces the snippet. Surrounded by neutral padding it extracts to the
# exact same text in both packages, so the snippet is deduplicated by hash. The
# only difference between the two packages is how many padding lines precede the
# block, which shifts the snippet's line number.
my $block = <<'BLOCK';
The license might be
something cool
but we would not
say what we can do
and what we can not do
with the GPL.
BLOCK

my $pad = "Neutral padding line with no keywords at all.\n";

sub make_package ($name, $md5, $leading) {
  my $dir = $cavil_test->checkout_dir->child($name, $md5)->make_path;

  # A fixed two-line padding frame directly wraps the block in both packages, so
  # the snippet region (which reaches one line above/below the keywords) extracts
  # byte-identical text. Only the extra padding above the frame varies, shifting
  # the line number without changing the snippet hash.
  $dir->child('README')->spew(($pad x $leading) . ($pad x 2) . $block . ($pad x 8));

  my $usr_id = $app->users->find_or_create(login => 'test_bot')->{id};
  my $pkgs   = $app->packages;
  my $pkg_id = $pkgs->add(
    name            => $name,
    checkout_dir    => $md5,
    api_url         => 'https://api.opensuse.org',
    requesting_user => $usr_id,
    project         => 'devel:test',
    package         => $name,
    srcmd5          => $md5,
    priority        => 5
  );
  $pkgs->imported($pkg_id);
  return $pkg_id;
}

# "license" and "copyright" are registered without a license, so a match becomes
# an unresolved snippet; "GPL" gives the block a second, resolved match.
my $patterns = $app->patterns;
$patterns->create(pattern => 'license');
$patterns->create(pattern => 'copyright');
$patterns->create(pattern => 'GPL', license => 'GPL');

# Same block, different line offset (block starts at line 3 vs line 13)
my $pkg_a = make_package('snippet-context-a', 'a' x 32, 0);
my $pkg_b = make_package('snippet-context-b', 'b' x 32, 10);
$app->minion->enqueue('unpack' => [$_]) for $pkg_a, $pkg_b;
$app->minion->perform_jobs;

my $db = $app->pg->db;

subtest 'Same snippet is deduplicated across packages at different lines' => sub {
  my $occurrences = $db->query(
    'SELECT fs.snippet, fs.file, fs.sline, m.package
     FROM file_snippets fs JOIN matched_files m ON (m.id = fs.file)
     WHERE m.package IN (?, ?) ORDER BY m.package', $pkg_a, $pkg_b
  )->hashes;

  is scalar(@$occurrences), 2, 'one occurrence per package';
  my ($a, $b) = @$occurrences;
  is $a->{snippet}, $b->{snippet}, 'both packages share the same deduplicated snippet';
  isnt $a->{sline}, $b->{sline},   'occurrences live on different lines';

  subtest 'with_context is scoped to the requested occurrence' => sub {
    my $snippets = $app->snippets;

    my $ctx_a = $snippets->with_context($a->{snippet}, $a->{file});
    is $ctx_a->{sline},             $a->{sline}, 'line number matches package A occurrence';
    is $ctx_a->{package}{filename}, 'README',    'filename for package A occurrence';

    my $ctx_b = $snippets->with_context($b->{snippet}, $b->{file});
    is $ctx_b->{sline}, $b->{sline}, 'line number matches package B occurrence';

    # Without a file id the lookup falls back to an arbitrary occurrence
    my $ctx_any = $snippets->with_context($a->{snippet});
    ok defined $ctx_any->{sline}, 'fallback lookup still returns a line';
    ok(($ctx_any->{sline} == $a->{sline} || $ctx_any->{sline} == $b->{sline}),
      'fallback line matches one of the real occurrences');
  };
};

done_testing();
