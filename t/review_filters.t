# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Mojo::Base -strict;

use FindBin;
use lib "$FindBin::Bin/lib";

use Test::More;
use Test::Mojo;
use Cavil::Test;

plan skip_all => 'set TEST_ONLINE to enable this test' unless $ENV{TEST_ONLINE};

my $cavil_test = Cavil::Test->new(online => $ENV{TEST_ONLINE}, schema => 'review_filters_test');
my $t          = Test::Mojo->new(Cavil => $cavil_test->default_config);
$cavil_test->no_fixtures($t->app);
my $pkgs = $t->app->packages;
my $uid  = $t->app->users->find_or_create(login => 'tester')->{id};

my %common = (
  api_url         => 'https://api.opensuse.org',
  requesting_user => $uid,
  project         => 'just:a:test',
  srcmd5          => 'abc1c36647a5d356883d490da2140def',
  priority        => 5
);
my $cve_id
  = $pkgs->add(%common, name => 'cve-pkg', checkout_dir => 'aaa1c36647a5d356883d490da2140def', package => 'cve-pkg');
my $plain = $pkgs->add(%common, name => 'plain-pkg', checkout_dir => 'bbb1c36647a5d356883d490da2140def',
  package => 'plain-pkg');
$pkgs->add_tags($cve_id, ['CVE']);

my $names = sub {
  my $search = shift;
  my $page   = $pkgs->paginate_open_reviews(
    {
      search        => $search,
      priority      => 0,
      in_progress   => 'false',
      not_embargoed => 'false',
      notes         => 'any',
      limit         => 100,
      offset        => 0
    }
  )->{page};
  return [sort map { $_->{name} } @$page];
};
my $recent_names = sub {
  my $search = shift;

  # Mark both reviewed so they appear in the recent listing, then filter
  $t->app->pg->db->query('UPDATE bot_packages SET reviewed = NOW() WHERE id = ANY(?)', [$cve_id, $plain]);
  my $page = $pkgs->paginate_recent_reviews(
    {
      search             => $search,
      by_user            => 'false',
      ai_assisted        => 'false',
      unresolved_matches => 'false',
      limit              => 100,
      offset             => 0
    }
  )->{page};
  return [sort map { $_->{name} } @$page];
};

subtest 'open reviews tag filter' => sub {
  is_deeply $names->(''),              ['cve-pkg', 'plain-pkg'], 'no filter returns both';
  is_deeply $names->('tag:CVE'),       ['cve-pkg'],              'tag:CVE narrows to the tagged package';
  is_deeply $names->('tag=CVE'),       ['cve-pkg'],              'tag=CVE works too';
  is_deeply $names->('tag:cve'),       ['cve-pkg'],              'tag match is case insensitive';
  is_deeply $names->('tag:CVE cve'),   ['cve-pkg'],              'residual text still applies (matches name)';
  is_deeply $names->('tag:CVE plain'), [],                       'residual text excludes the tagged package';
  is_deeply $names->('foo:bar'),       [],                       'unknown field folds into a substring search';
  is_deeply $names->('plain'),         ['plain-pkg'],            'plain text search is unchanged';
};

subtest 'recent reviews tag filter' => sub {
  is_deeply $recent_names->('tag:CVE'), ['cve-pkg'],              'tag:CVE narrows recent reviews';
  is_deeply $recent_names->(''),        ['cve-pkg', 'plain-pkg'], 'no filter returns both recent';
};

done_testing;
