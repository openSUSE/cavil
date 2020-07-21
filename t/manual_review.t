use Mojo::Base -strict;

BEGIN { $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll' }

use Test::More;

plan skip_all => 'set TEST_ONLINE to enable this test' unless $ENV{TEST_ONLINE};

use Test::Mojo;
use Mojo::File qw(path tempdir);
use Mojo::Pg;
use Mojolicious::Lite;

# Isolate tests
my $pg = Mojo::Pg->new($ENV{TEST_ONLINE});
$pg->db->query('drop schema if exists analyze_test cascade');
$pg->db->query('create schema analyze_test');

# Create checkout directory
my $dir  = tempdir;
my @src  = ('perl-Mojolicious', 'c7cfdab0e71b0bebfdf8b2dc3badfecd');
my $mojo = $dir->child(@src)->make_path;
$_->copy_to($mojo->child($_->basename)) for path(__FILE__)->dirname->child('legal-bot', @src)->list->each;
@src  = ('perl-Mojolicious', 'da3e32a3cce8bada03c6a9d63c08cd58');
$mojo = $dir->child(@src)->make_path;
$_->copy_to($mojo->child($_->basename)) for path(__FILE__)->dirname->child('legal-bot', @src)->list->each;

app->log->level('error');

# Configure application
my $online = Mojo::URL->new($ENV{TEST_ONLINE})->query([search_path => 'analyze_test'])->to_unsafe_string;
my $config = {
  secrets                => ['just_a_test'],
  checkout_dir           => $dir,
  tokens                 => [],
  pg                     => $online,
  acceptable_risk        => 3,
  index_bucket_average   => 100,
  cleanup_bucket_average => 50,
  min_files_short_report => 20,
  max_email_url_size     => 26,
  max_task_memory        => 5_000_000_000,
  max_worker_rss         => 100000,
  max_expanded_files     => 100
};
my $t = Test::Mojo->new(Cavil => $config);
$t->app->pg->migrations->migrate;

# Prepare database
my $db     = $t->app->pg->db;
my $usr_id = $db->insert('bot_users', {login => 'test_bot'}, {returning => 'id'})->hash->{id};
my $pkg_id = $t->app->packages->add(
  name            => 'perl-Mojolicious',
  checkout_dir    => 'c7cfdab0e71b0bebfdf8b2dc3badfecd',
  api_url         => 'https://api.opensuse.org',
  requesting_user => $usr_id,
  project         => 'devel:languages:perl',
  package         => 'perl-Mojolicious',
  srcmd5          => 'bd91c36647a5d3dd883d490da2140401',
  priority        => 5
);
$t->app->packages->imported($pkg_id);
$t->app->patterns->create(pattern => 'You may obtain a copy of the License at', license => 'Apache-2.0');
$t->app->patterns->create(
  packname => 'perl-Mojolicious',
  pattern  => 'Licensed under the Apache License, Version 2.0',
  license  => 'Apache-2.0'
);
$t->app->patterns->create(pattern => 'License: Artistic-2.0', license => 'Artistic-2.0');
$t->app->patterns->create(pattern => 'License: GPL-1.0+',     license => 'GPL-1.0+');
$t->app->patterns->create(pattern => 'License: GPL-1.0+',     license => 'GPL-1.0+');
$t->app->patterns->create(pattern => 'the terms',             risk    => 9);
$t->app->patterns->create(pattern => 'copyright notice',      risk    => 9);

subtest 'Details after import (indexing in progress)' => sub {
  $t->get_ok('/reviews/details/1')->status_is(200)->text_like('#rpm-license', qr!Artistic-2.0!)
    ->text_like('#rpm-version', qr!7\.25!)->text_like('#rpm-summary', qr!Real-time web framework!)
    ->text_like('#rpm-group',   qr!Development/Libraries/Perl!)
    ->text_like('#rpm-url a',   qr!http://search\.cpan\.org/dist/Mojolicious/!)->text_like('#pkg-state', qr!new!)
    ->element_exists_not('#pkg-review')->element_exists_not('#pkg-shortname')
    ->element_exists_not('#pkg-review label[for=comment]')->element_exists_not('#pkg-review textarea[name=comment]')
    ->element_exists_not('#correct')->element_exists_not('#acceptable')->element_exists_not('#unacceptable');
  $t->get_ok('/reviews/calc_report/1')->status_is(408);
};

subtest 'Details after import (with login)' => sub {
  $t->get_ok('/login')->status_is(302)->header_is(Location => '/');

  $t->get_ok('/reviews/details/1')->status_is(200)->text_like('#rpm-license', qr!Artistic-2.0!)
    ->text_like('#rpm-version', qr!7\.25!)->text_like('#rpm-summary', qr!Real-time web framework!)
    ->text_like('#rpm-group',   qr!Development/Libraries/Perl!)
    ->text_like('#rpm-url a',   qr!http://search\.cpan\.org/dist/Mojolicious/!)->text_like('#pkg-state', qr!new!)
    ->element_exists('#pkg-review')->element_exists_not('#pkg-shortname')
    ->element_exists('#pkg-review label[for=comment]')->element_exists('#pkg-review textarea[name=comment]')
    ->element_exists('#correct')->element_exists('#acceptable')->element_exists('#unacceptable');
  $t->get_ok('/reviews/calc_report/1')->status_is(408);

  $t->get_ok('/logout')->status_is(302)->header_is(Location => '/');
};

# Unpack and index
$t->app->minion->enqueue(unpack => [$pkg_id]);
$t->app->minion->perform_jobs;

subtest 'Snippets after indexing' => sub {
  my $snippets = $t->app->pg->db->select('snippets')->hashes->to_array;
  is $snippets->[0]{id},           1,     'snippet';
  is $snippets->[0]{like_pattern}, undef, 'unlike any pattern';
  ok !$snippets->[0]{likelyness}, 'no likelyness';
  is $snippets->[1]{id},           2,     'snippet';
  is $snippets->[1]{like_pattern}, undef, 'unlike any pattern';
  ok !$snippets->[1]{likelyness}, 'no likelyness';
  is $snippets->[2]{id},           3,     'snippet';
  is $snippets->[2]{like_pattern}, undef, 'unlike any pattern';
  ok !$snippets->[2]{likelyness}, 'no likelyness';
  is $snippets->[3]{id},           4,     'snippet';
  is $snippets->[3]{like_pattern}, undef, 'unlike any pattern';
  ok !$snippets->[3]{likelyness}, 'no likelyness';
  is $snippets->[4]{id},           5,     'snippet';
  is $snippets->[4]{like_pattern}, undef, 'unlike any pattern';
  ok !$snippets->[4]{likelyness}, 'no likelyness';
  is $snippets->[5]{id},           6,     'snippet';
  is $snippets->[5]{like_pattern}, undef, 'unlike any pattern';
  ok !$snippets->[5]{likelyness}, 'no likelyness';
  is $snippets->[6], undef, 'no more snippets';
};

subtest 'Details after indexing' => sub {
  $t->get_ok('/login')->status_is(302)->header_is(Location => '/');

  $t->get_ok('/reviews/details/1')->status_is(200)->text_like('#rpm-license', qr!Artistic-2.0!)
    ->text_like('#rpm-version', qr!7\.25!)->text_like('#rpm-summary', qr!Real-time web framework!)
    ->text_like('#rpm-group',   qr!Development/Libraries/Perl!)
    ->text_like('#rpm-url a',   qr!http://search\.cpan\.org/dist/Mojolicious/!)->text_like('#pkg-state', qr!new!)
    ->element_exists('#pkg-review')->element_exists('#pkg-shortname')->element_exists('#pkg-review label[for=comment]')
    ->element_exists('#pkg-review textarea[name=comment]')->element_exists('#correct')->element_exists('#acceptable')
    ->element_exists('#unacceptable');

  $t->get_ok('/reviews/calc_report/1')->status_is(200)->element_exists('#license-chart')->element_exists('#emails')
    ->text_like('#emails tbody td', qr!coolo\@suse\.com!)->element_exists('#urls')
    ->text_like('#urls tbody td',   qr!http://mojolicious.org!);

  $t->get_ok('/logout')->status_is(302)->header_is(Location => '/');
};

# Reindex (with updated stats)
$t->app->minion->enqueue('pattern_stats');
$t->app->minion->perform_jobs;
$t->app->packages->reindex($pkg_id);
$t->app->minion->perform_jobs;

subtest 'Snippets after reindexing' => sub {
  my $snippets = $t->app->pg->db->select('snippets')->hashes->to_array;
  is $snippets->[0]{id},           1, 'snippet';
  is $snippets->[0]{like_pattern}, 6, 'like pattern';
  ok $snippets->[0]{likelyness} > 0, 'likelyness';
  is $snippets->[1]{id},           2, 'snippet';
  is $snippets->[1]{like_pattern}, 1, 'like pattern';
  ok $snippets->[1]{likelyness} > 0, 'likelyness';
  is $snippets->[2]{id},           3, 'snippet';
  is $snippets->[2]{like_pattern}, 5, 'like pattern';
  ok $snippets->[2]{likelyness} > 0, 'likelyness';
  is $snippets->[3]{id},           4, 'snippet';
  is $snippets->[3]{like_pattern}, 5, 'like pattern';
  ok $snippets->[3]{likelyness} > 0, 'likelyness';
  is $snippets->[4]{id},           5, 'snippet';
  is $snippets->[4]{like_pattern}, 2, 'like pattern';
  ok $snippets->[4]{likelyness} > 0, 'likelyness';
  is $snippets->[5]{id},           6, 'snippet';
  is $snippets->[5]{like_pattern}, 6, 'like pattern';
  ok $snippets->[5]{likelyness} > 0, 'likelyness';
  is $snippets->[6], undef, 'no more snippets';
};

subtest 'Details after reindexing' => sub {
  $t->get_ok('/login')->status_is(302)->header_is(Location => '/');

  $t->get_ok('/reviews/details/1')->status_is(200)->text_like('#rpm-license', qr!Artistic-2.0!)
    ->text_like('#rpm-version', qr!7\.25!)->text_like('#rpm-summary', qr!Real-time web framework!)
    ->text_like('#rpm-group',   qr!Development/Libraries/Perl!)
    ->text_like('#rpm-url a',   qr!http://search\.cpan\.org/dist/Mojolicious/!)->text_like('#pkg-state', qr!new!)
    ->element_exists('#pkg-review')->element_exists('#pkg-shortname')->element_exists('#pkg-review label[for=comment]')
    ->element_exists('#pkg-review textarea[name=comment]')->element_exists('#correct')->element_exists('#acceptable')
    ->element_exists('#unacceptable');

  $t->get_ok('/reviews/calc_report/1')->status_is(200)->element_exists('#license-chart')
    ->element_exists('#unmatched-files')->text_is('#unmatched-count', '4')
    ->text_like('#unmatched-files li:nth-of-type(1) a', qr!Mojolicious-7.25/Changes!)
    ->text_like('#unmatched-files li:nth-of-type(1)',   qr!100% Snippet - estimated risk 9!)
    ->text_like('#unmatched-files li:nth-of-type(2) a', qr!Mojolicious-7.25/LICENSE!)
    ->text_like('#unmatched-files li:nth-of-type(2)',   qr![0-9.]+% Snippet - estimated risk 9!)
    ->text_like('#unmatched-files li:nth-of-type(3) a', qr!perl-Mojolicious\.changes!)
    ->text_like('#unmatched-files li:nth-of-type(3)',   qr!100% Snippet - estimated risk 9!)
    ->text_like('#unmatched-files li:nth-of-type(4) a', qr!Mojolicious-7.25/lib/Mojolicious.pm!)
    ->text_like('#unmatched-files li:nth-of-type(4)',   qr![0-9.]+% Apache-2.0 - estimated risk 7!)
    ->element_exists('#risk-5')->text_like('#risk-5 li', qr!Apache-2.0!)
    ->text_like('#risk-5 li ul li:nth-of-type(1) a', qr!Mojolicious-7.25/lib/Mojolicious.pm!)
    ->text_like('#risk-5 li ul li:nth-of-type(2) a', qr!Mojolicious-7.25/lib/Mojolicious/resources/public/!);
  $t->element_exists('#emails')->text_like('#emails tbody td', qr!coolo\@suse\.com!)->element_exists('#urls')
    ->text_like('#urls tbody td', qr!http://mojolicious.org!);

  $t->get_ok('/logout')->status_is(302)->header_is(Location => '/');
};

subtest 'Manual review' => sub {
  $t->get_ok('/login')->status_is(302)->header_is(Location => '/');

  $t->post_ok('/reviews/review_package/1' => form => {comment => 'Test review', acceptable => 'Good Enough'})
    ->status_is(200)->text_like('#content a', qr!perl-Mojolicious!)->text_like('#content b', qr!acceptable!);

  $t->get_ok('/reviews/details/1')->status_is(200)->text_like('#rpm-license', qr!Artistic-2.0!)
    ->text_like('#rpm-version', qr!7\.25!)->text_like('#rpm-summary', qr!Real-time web framework!)
    ->text_like('#rpm-group',   qr!Development/Libraries/Perl!)
    ->text_like('#rpm-url a',   qr!http://search\.cpan\.org/dist/Mojolicious/!)->text_like('#pkg-state', qr!acceptable!)
    ->element_exists('#pkg-review')->element_exists('#pkg-shortname')->element_exists('#pkg-review label[for=comment]')
    ->element_exists('#pkg-review textarea[name=comment]')->element_exists('#correct')->element_exists('#acceptable')
    ->element_exists('#unacceptable');

  $t->get_ok('/reviews/calc_report/1')->status_is(200)->element_exists('#license-chart')
    ->element_exists('#unmatched-files')->text_is('#unmatched-count', '4')
    ->text_like('#unmatched-files li:nth-of-type(4) a', qr!Mojolicious-7.25/lib/Mojolicious.pm!)
    ->text_like('#unmatched-files li:nth-of-type(4)', qr!57% Apache-2.0 - estimated risk 7!)->element_exists('#risk-5');
  $t->element_exists('#emails')->text_like('#emails tbody td', qr!coolo\@suse\.com!)->element_exists('#urls')
    ->text_like('#urls tbody td', qr!http://mojolicious.org!);

  $t->get_ok('/logout')->status_is(302)->header_is(Location => '/');
};

# Clean up once we are done
$pg->db->query('drop schema analyze_test cascade');

done_testing;

