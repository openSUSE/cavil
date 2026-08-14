# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package Cavil::Test;
use Mojo::Base -base, -signatures;

use Cavil::Util qw(SNIPPET_SCORE_VERSION);
use Mojo::File  qw(path tempdir);
use Mojo::JSON  qw(from_json to_json);
use Mojo::Pg;
use Mojo::URL;
use Mojo::Util qw(scope_guard);

sub new ($class, %options) {

  # Database
  my $self = $class->SUPER::new(options => \%options);
  $self->{pg} = Mojo::Pg->new($options{online});
  $self->_ensure_extensions;
  $self->{db_guard} = $self->_prepare_schema($options{schema});

  # Temporary directories
  $self->{checkout_dir} = tempdir;
  $self->{cache_dir}    = tempdir;

  return $self;
}

sub cache_dir    ($self) { $self->{cache_dir} }
sub checkout_dir ($self) { $self->{checkout_dir} }

sub default_config ($self) {
  return {
    secrets                                  => ['just_a_test'],
    checkout_dir                             => $self->checkout_dir,
    cache_dir                                => $self->cache_dir,
    matcher                                  => $ENV{CAVIL_MATCHER} || 'cavil',
    tokens                                   => ['test_token'],
    pg                                       => $self->postgres_url,
    acceptable_risk                          => 4,
    auto_accept_risk                         => 0,
    index_bucket_average                     => 100,
    cleanup_bucket_average                   => 50,
    days_to_keep_orphaned_packages           => 7,
    days_to_keep_orphaned_duplicate_packages => 1,
    min_files_short_report                   => 20,
    max_email_url_size                       => 26,
    max_task_memory                          => 5_000_000_000,
    max_worker_rss                           => 100000,
    max_expanded_files                       => 100,
    max_file_browser_size                    => 1_000_000,
    always_generate_spdx_reports             => 0,
    spdx                                     => {
      namespace             => 'http://legaldb.suse.de/spdx/',
      creator               => {name => 'SUSE LLC', email => 'security@suse.de'},
      license_ref_namespace => 'cavil'
    },
    snippet_fold => {
      enabled         => 0,
      threshold       => 0.95,
      min_margin      => 0.15,
      max_risk        => 5,
      clear_threshold => 0,
      overlap_clear   => 0,
      overlap_guard   => 0.9,
      cover_scope     => 'off'
    }
  };
}

sub embargo_fixtures ($self, $app) {
  $self->mojo_fixtures($app);
  my $patterns = $app->patterns;

  # A pattern that will create new snippets with embargo
  $patterns->create(pattern => 'Added EXPERIMENTAL');
}

sub just_patterns_fixtures ($self, $app) {
  $self->no_fixtures($app);
  my $patterns = $app->patterns;
  $patterns->create(pattern => 'You may obtain a copy of the License at', license => 'Apache-2.0');
  $patterns->create(
    packname => 'perl-Mojolicious',
    pattern  => 'Licensed under the Apache License, Version 2.0',
    license  => 'Apache-2.0'
  );
  $patterns->create(pattern => 'License: Artistic-2.0',            license => 'Artistic-2.0');
  $patterns->create(pattern => 'License: MIT',                     license => 'MIT');
  $patterns->create(pattern => 'License: MIT-CMU',                 license => 'MIT-CMU');
  $patterns->create(pattern => 'powerful web development toolkit', license => 'SUSE-NotALicense');
  $patterns->create(pattern => 'the terms');
  $patterns->create(pattern => 'copyright notice');
}

sub mojo_fixtures ($self, $app) {
  $self->no_fixtures($app);

  my $dir       = $self->checkout_dir;
  my @src       = ('perl-Mojolicious', 'c7cfdab0e71b0bebfdf8b2dc3badfecd');
  my $mojo      = $dir->child(@src)->make_path;
  my $legal_bot = path(__FILE__)->dirname->dirname->dirname->child('legal-bot');
  $_->copy_to($mojo->child($_->basename)) for $legal_bot->child(@src)->list->each;
  @src  = ('perl-Mojolicious', 'da3e32a3cce8bada03c6a9d63c08cd58');
  $mojo = $dir->child(@src)->make_path;
  $_->copy_to($mojo->child($_->basename)) for $legal_bot->child(@src)->list->each;

  my $usr_id = $app->pg->db->insert('bot_users', {login => 'test_bot'}, {returning => 'id'})->hash->{id};
  my $pkgs   = $app->packages;
  my $pkg_id = $pkgs->add(
    name            => 'perl-Mojolicious',
    checkout_dir    => 'c7cfdab0e71b0bebfdf8b2dc3badfecd',
    api_url         => 'https://api.opensuse.org',
    requesting_user => $usr_id,
    project         => 'devel:languages:perl',
    package         => 'perl-Mojolicious',
    srcmd5          => 'bd91c36647a5d3dd883d490da2140401',
    priority        => 5
  );
  my $pkg = $pkgs->find($pkg_id);
  $pkg->{external_link} = "mojo#1";
  $pkgs->update($pkg);
  $pkgs->imported($pkg_id);
  my $pkg2_id = $pkgs->add(
    name            => 'perl-Mojolicious',
    checkout_dir    => 'da3e32a3cce8bada03c6a9d63c08cd58',
    api_url         => 'https://api.opensuse.org',
    requesting_user => 1,
    project         => 'devel:languages:perl',
    package         => 'perl-Mojolicious',
    srcmd5          => 'da3e32a3cce8bada03c6a9d63c08cd58',
    priority        => 5
  );
  my $pkg2 = $pkgs->find($pkg2_id);
  $pkg2->{external_link} = "mojo#2";
  $pkgs->update($pkg2);
  $pkgs->imported($pkg2_id);
  my $patterns = $app->patterns;
  $patterns->create(
    pattern   => 'You may obtain a copy of the License at',
    license   => 'Apache-2.0',
    unique_id => '413430b9-8f04-49d8-93ef-953b68835d50'
  );
  $patterns->create(
    packname  => 'perl-Mojolicious',
    pattern   => 'Licensed under the Apache License, Version 2.0',
    license   => 'Apache-2.0',
    unique_id => '413430b9-8f04-49d8-93ef-953b68835d51'
  );
  $patterns->create(
    pattern   => 'License: Artistic-2.0',
    license   => 'Artistic-2.0',
    unique_id => '413430b9-8f04-49d8-93ef-953b68835d52'
  );
  $patterns->create(
    pattern   => 'powerful web development toolkit',
    license   => 'SUSE-NotALicense',
    unique_id => '413430b9-8f04-49d8-93ef-953b68835d53'
  );
  $patterns->create(pattern => 'the terms',        unique_id => '413430b9-8f04-49d8-93ef-953b68835d54');
  $patterns->create(pattern => 'copyright notice', unique_id => '413430b9-8f04-49d8-93ef-953b68835d55');

  $app->pg->db->query('UPDATE license_patterns SET spdx = $1 WHERE license = $1', $_) for qw(Apache-2.0 Artistic-2.0);
}

sub components_fixtures ($self, $app) {
  $self->no_fixtures($app);

  # Obscured paths require content-based component detection.
  my @src       = ('vendored', 'da39a3ee5e6b4b0d3255bfef95601890');
  my $checkout  = $self->checkout_dir->child(@src)->make_path;
  my $legal_bot = path(__FILE__)->dirname->dirname->dirname->child('legal-bot');
  $_->copy_to($checkout->child($_->basename)) for $legal_bot->child(@src)->list->each;

  # Backfill a component whose metadata omits its license.
  my $patterns = $app->patterns;
  $patterns->create(pattern => 'Permission is hereby granted to use this fixture component', license => 'MIT');
  $app->pg->db->query('UPDATE license_patterns SET spdx = $1 WHERE license = $1', 'MIT');

  my $usr_id = $app->pg->db->insert('bot_users', {login => 'test_bot'}, {returning => 'id'})->hash->{id};
  my $pkgs   = $app->packages;
  my $pkg_id = $pkgs->add(
    name            => 'vendored',
    checkout_dir    => 'da39a3ee5e6b4b0d3255bfef95601890',
    api_url         => 'https://api.opensuse.org',
    requesting_user => $usr_id,
    project         => 'devel:test',
    package         => 'vendored',
    srcmd5          => 'da39a3ee5e6b4b0d3255bfef95601890',
    priority        => 5
  );
  $pkgs->imported($pkg_id);

  return $pkg_id;
}

sub go_vendor_fixtures ($self, $app) {

  # Root-level dependency listings must not be mistaken for primary manifests.
  my @src       = ('go-vendor', 'b6d767d2f8ed5d21a44b0e5886680cb9');
  my $checkout  = $self->checkout_dir->child(@src)->make_path;
  my $legal_bot = path(__FILE__)->dirname->dirname->dirname->child('legal-bot');
  $_->copy_to($checkout->child($_->basename)) for $legal_bot->child(@src)->list->each;

  my $db     = $app->pg->db;
  my $usr_id = $db->select('bot_users', 'id', {login => 'test_bot'})->hash->{id}
    // $db->insert('bot_users', {login => 'test_bot'}, {returning => 'id'})->hash->{id};
  my $pkgs   = $app->packages;
  my $pkg_id = $pkgs->add(
    name            => 'go-vendor',
    checkout_dir    => 'b6d767d2f8ed5d21a44b0e5886680cb9',
    api_url         => 'https://api.opensuse.org',
    requesting_user => $usr_id,
    project         => 'devel:test',
    package         => 'go-vendor',
    srcmd5          => 'b6d767d2f8ed5d21a44b0e5886680cb9',
    priority        => 5
  );
  $pkgs->imported($pkg_id);

  return $pkg_id;
}

sub multiarchive_fixtures ($self, $app) {

  # Multiple top-level archives make a depth-one manifest vendored, not primary.
  my @src       = ('multiarchive', 'c4ca4238a0b923820dcc509a6f75849b');
  my $checkout  = $self->checkout_dir->child(@src)->make_path;
  my $legal_bot = path(__FILE__)->dirname->dirname->dirname->child('legal-bot');
  $_->copy_to($checkout->child($_->basename)) for $legal_bot->child(@src)->list->each;

  my $db     = $app->pg->db;
  my $usr_id = $db->select('bot_users', 'id', {login => 'test_bot'})->hash->{id}
    // $db->insert('bot_users', {login => 'test_bot'}, {returning => 'id'})->hash->{id};
  my $pkgs   = $app->packages;
  my $pkg_id = $pkgs->add(
    name            => 'multiarchive',
    checkout_dir    => 'c4ca4238a0b923820dcc509a6f75849b',
    api_url         => 'https://api.opensuse.org',
    requesting_user => $usr_id,
    project         => 'devel:test',
    package         => 'multiarchive',
    srcmd5          => 'c4ca4238a0b923820dcc509a6f75849b',
    priority        => 5
  );
  $pkgs->imported($pkg_id);

  return $pkg_id;
}

sub no_fixtures ($self, $app) {
  $app->pg->migrations->migrate;

  # Allow Devel::Cover to collect stats for background jobs
  $app->minion->on(
    worker => sub {
      my ($minion, $worker) = @_;
      $worker->on(
        dequeue => sub {
          my ($worker, $job) = @_;
          $job->on(cleanup => sub { Devel::Cover::report() if Devel::Cover->can('report') });
        }
      );
    }
  );
}

sub package_with_snippets_fixtures ($self, $app) {
  $self->no_fixtures($app);

  my $dir = $self->checkout_dir;
  my @src = ('package-with-snippets', '2a0737e27a3b75590e7fab112b06a76fe7573615');
  my $src = $dir->child(@src)->make_path;
  $_->copy_to($src->child($_->basename))
    for path(__FILE__)->dirname->dirname->dirname->child('legal-bot', @src)->list->each;

  my $usr_id = $app->pg->db->insert('bot_users', {login => 'test_bot'}, {returning => 'id'})->hash->{id};
  my $pkgs   = $app->packages;
  my $pkg_id = $pkgs->add(
    name            => 'package-with-snippets',
    checkout_dir    => '2a0737e27a3b75590e7fab112b06a76fe7573615',
    api_url         => 'https://api.opensuse.org',
    requesting_user => $usr_id,
    project         => 'devel:languages:perl',
    package         => 'package-with-snippets',
    srcmd5          => '2a0737e27a3b75590e7fab112b06a76fe7573615',
    priority        => 5
  );
  $pkgs->imported($pkg_id);
  my $patterns = $app->patterns;
  $patterns->create(pattern => 'license');
  $patterns->create(pattern => 'copyright');
  $patterns->create(pattern => 'GPL', license => 'GPL');
  $patterns->create(
    pattern => 'Permission is granted to copy, distribute and/or modify this document
       under the terms of the GNU Free Documentation License, Version 1.1 or any later
       version published by the Free Software Foundation; with no Invariant Sections,
       with no Front-Cover Texts and with no Back-Cover Texts. A copy of the license
       is included in the section entitled "GNU Free Documentation License"',
    license => 'GFDL-1.1-or-later'
  );
}

# Confident, current, low-risk GPL matches must fold into the cached report.
sub snippet_fold_fixtures ($self, $app) {
  $self->package_with_snippets_fixtures($app);
  $app->minion->enqueue(unpack => [1]);
  $app->minion->perform_jobs;

  my $db  = $app->pg->db;
  my $gpl = $db->query("SELECT id FROM license_patterns WHERE license = 'GPL' LIMIT 1")->hash;
  $db->query(
    'UPDATE snippets SET license = TRUE, classified = TRUE, likelyness = 0.99, second_match = 0,
       score_version = ?, like_pattern = ?', SNIPPET_SCORE_VERSION, $gpl->{id}
  );

  # Regenerate the cached report so the fold is reflected in what the UI loads
  $app->minion->enqueue(analyze => [1]);
  $app->minion->perform_jobs;
}

# Zero-margin matches may clear boilerplate but must never assert a license.
sub snippet_clear_fixtures ($self, $app) {
  $self->package_with_snippets_fixtures($app);
  $app->minion->enqueue(unpack => [1]);
  $app->minion->perform_jobs;

  my $db = $app->pg->db;
  my $pattern
    = $app->patterns->create(pattern => 'a unique clearable license marker for the ui', license => 'Clear-Test');
  $db->query(
    'UPDATE snippets SET license = TRUE, classified = TRUE, likelyness = 0.99, second_match = 0.99,
       score_version = ?, like_pattern = ?', SNIPPET_SCORE_VERSION, $pattern->{id}
  );

  # Regenerate the cached report so the clearing is reflected in what the UI loads
  $app->minion->enqueue(analyze => [1]);
  $app->minion->perform_jobs;
}

# Curated overlap may clear unscored legal snippets without similarity resolution.
sub snippet_overlap_fixtures ($self, $app) {
  $self->package_with_snippets_fixtures($app);
  $app->minion->enqueue(unpack => [1]);
  $app->minion->perform_jobs;

  my $db = $app->pg->db;
  $db->query(
    'UPDATE snippets SET license = TRUE, classified = TRUE, likelyness = 0, like_pattern = NULL, score_version = 0');
  my $gpl = $db->query("SELECT id FROM license_patterns WHERE license = 'GPL' LIMIT 1")->hash->{id};
  for my $fs ($db->query('SELECT file, sline FROM file_snippets WHERE package = 1')->hashes->each) {
    $db->insert('pattern_matches',
      {package => 1, file => $fs->{file}, pattern => $gpl, sline => $fs->{sline}, eline => $fs->{sline}, ignored => 0});
  }

  # Regenerate the cached report so the report view reflects the overlap-clear
  $app->minion->enqueue(analyze => [1]);
  $app->minion->perform_jobs;
}

# Controlled fold, clear, and unresolved cases exercise triage filters.
sub snippet_triage_fixtures ($self, $app) {
  $self->package_with_snippets_fixtures($app);
  my $db    = $app->pg->db;
  my $fold  = $app->patterns->create(pattern => 'a folded triage marker for ui', license => 'Triage-Fold', risk => 3);
  my $risky = $app->patterns->create(pattern => 'a high risk folded triage marker for ui', license => 'Triage-Risky',
    risk => 5);

  # A file to anchor the occurrences; the triage filter reads file_snippets.resolution (one row per
  # occurrence), so every snippet needs an occurrence whose resolution resolve_snippets computes below.
  # Reserved characters in the path exercise URL encoding of file links on the Snippets page.
  my $file = $db->insert(
    'matched_files',
    {package   => 1, filename => 'sub dir/ui triage#1.txt', mimetype => 'text/plain'},
    {returning => 'id'}
  )->hash->{id};

  my $n      = 0;
  my $line   = 0;
  my $insert = sub (%o) {
    $n++;
    $line += 100;
    my $sid = $db->insert(
      'snippets',
      {
        hash          => "ui-triage-$n",
        text          => $o{text},
        package       => 1,
        classified    => 1,
        license       => 1,
        approved      => 0,
        confidence    => 100,
        likelyness    => $o{likelyness},
        second_match  => $o{second_match} // 0,
        score_version => SNIPPET_SCORE_VERSION,
        like_pattern  => $o{like_pattern} // $fold->{id}
      },
      {returning => 'id'}
    )->hash->{id};
    $db->insert('file_snippets', {package => 1, file => $file, snippet => $sid, sline => $line, eline => $line + 5});
  };

  $insert->(likelyness => 0.99, second_match => 0.5, text => "fold marker body number $_ with GPL terms") for 1 .. 11;
  $insert->(
    likelyness   => 0.99,
    second_match => 0.5,
    like_pattern => $risky->{id},
    text         => 'high risk fold marker body'
  );
  $insert->(likelyness => 0.99, second_match => 0.5,  text => 'fold marker Non-Commercial use clause body');
  $insert->(likelyness => 0.99, second_match => 0.99, text => 'cleared boilerplate definitions body');
  $insert->(likelyness => 0.99, second_match => 0.99, text => 'overlap notice body');
  $insert->(likelyness => 0.99, second_match => 0.99, text => 'covered fragment body');
  $insert->(likelyness => 0.40, second_match => 0.0,  text => 'unresolved random noise body');

  $app->snippets->resolve_snippets(1);
  $db->query(
    q{UPDATE file_snippets fs SET resolution = 'overlap' FROM snippets s WHERE s.id = fs.snippet AND s.text = ?},
    'overlap notice body');
  $db->query(
    q{UPDATE file_snippets fs SET resolution = 'covered' FROM snippets s WHERE s.id = fs.snippet AND s.text = ?},
    'covered fragment body');
}

sub postgres_url ($self) {
  return Mojo::URL->new($self->{options}{online})
    ->query([search_path => [$self->{options}{schema}, 'public']])
    ->to_unsafe_string;
}

sub spdx_fixtures ($self, $app) {
  $self->mojo_fixtures($app);
  my $patterns = $app->patterns;
  $patterns->create(pattern => 'copyright');
}

# A package whose files the indexer has to post-process before it can scan them, with a license
# declaration placed *after* the point where post-processing shifts the line numbering. The SPDX
# report names the original files, so its line ranges have to be the originals' - the offsets here
# are what distinguishes a translated report from one that just repeats what the indexer stored.
sub spdx_line_shift_fixtures ($self, $app) {
  my $md5 = 'f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0';
  my $dir = $self->checkout_dir->child('line-shift', $md5)->make_path;

  # Line 3 is a minified blob that the line-wrapper breaks in two, so the declaration on line 4
  # is scanned as line 5
  # The trailing notice is appended, not prepended: the line numbers above are what this fixture exists
  # to pin. It repeats verbatim in helper.js below, which is how a header notice behaves in a real tree
  # and what the notices being stored once per package with the files they cover has to survive.
  $dir->child('bundle.js')->spew(<<"JS");
/* generated bundle, do not edit */
var a = 1;
@{['x' x 200]} @{['y' x 50]}
/* Permission is hereby granted under the Cavil Fixture License */
var b = 2;
/* Copyright (c) 2019 Cavil Fixture Authors */
JS

  $dir->child('helper.js')->spew(<<'JS');
/* Copyright (c) 2019 Cavil Fixture Authors */
var c = 3;
JS

  # A non-ASCII filename, in the bytes a real checkout carries. Every lookup between the indexer and the
  # SBOM keys on this name, so decoding it anywhere along the way drops the file out of the document.
  $dir->child("b\xc3\xbccher.c")->spew(<<'JS');
/* Copyright (c) 2019 Umlaut Authors */
/* Permission is hereby granted under the Cavil Fixture License */
JS

  # Markup is stripped to its text, so the declaration on line 6 is scanned as line 2
  $dir->child('page.html')->spew(<<'HTML');
<html>
<head>
<title>Fixture</title>
</head>
<body>
<!-- Permission is hereby granted under the Cavil Fixture License -->
<p>Nothing to see here.</p>
</body>
</html>
HTML

  my $db     = $app->pg->db;
  my $usr_id = $db->select('bot_users', 'id', {login => 'test_bot'})->hash->{id}
    // $db->insert('bot_users', {login => 'test_bot'}, {returning => 'id'})->hash->{id};
  my $pkgs   = $app->packages;
  my $pkg_id = $pkgs->add(
    name            => 'line-shift',
    checkout_dir    => $md5,
    api_url         => 'https://api.opensuse.org',
    requesting_user => $usr_id,
    project         => 'devel:test',
    package         => 'line-shift',
    srcmd5          => $md5,
    priority        => 5
  );
  $pkgs->imported($pkg_id);

  # Deliberately a phrase no other fixture contains, so adding this package cannot change what any
  # other report finds
  $app->patterns->create(
    pattern   => 'Permission is hereby granted under the Cavil Fixture License',
    license   => 'MIT',
    unique_id => '413430b9-8f04-49d8-93ef-953b68835d60'
  );
  $db->query('UPDATE license_patterns SET spdx = $1 WHERE license = $1', 'MIT');

  return $pkg_id;
}

sub ui_fixtures ($self, $app) {
  $app->pg->migrations->migrate;

  $self->mojo_fixtures($app);
  my $pkgs = $app->packages;
  $pkgs->unpack($_) for 1 .. 2;

  # Make sure pagination is needed
  my $usr_id = $app->pg->db->insert('bot_users', {login => 'test_bot'}, {returning => 'id'})->hash->{id};
  for my $i (1 .. 21) {
    my $priority = $i > 10 ? 1 : 5;
    my $pkg_id   = $pkgs->add(
      name            => "perl-UI-Test$i",
      checkout_dir    => 'doesnotexist',
      api_url         => 'https://api.opensuse.org',
      requesting_user => $usr_id,
      project         => 'devel:languages:perl',
      package         => "perl-UI-Test$i",
      srcmd5          => '4041c36647a5d3dd883d490da2140404',
      priority        => $priority
    );
    my $pkg = $pkgs->find($pkg_id);
    $pkg->{external_link} = "test#$i";
    $pkgs->update($pkg);
  }

  # "harbor-helm" example data
  my $pkg_id = $pkgs->add(
    name            => 'harbor-helm',
    checkout_dir    => '4fcfdab0e71b0bebfdf8b5cc3badfec4',
    api_url         => 'https://api.opensuse.org',
    requesting_user => $usr_id,
    project         => 'just:a:test',
    package         => 'harbor-helm',
    srcmd5          => 'abc1c36647a5d356883d490da2140def',
    priority        => 5
  );
  $pkgs->imported($pkg_id);
  my $harbor = $pkgs->find($pkg_id);
  $harbor->{external_link} = 'obs#123456';
  $pkgs->update($harbor);
  $pkgs->unpack($pkg_id);

  # Synthetic package with many unresolved keyword matches. Built from a real
  # tarball and indexed by the regular unpack + analyze pipeline so the
  # missed_files collection is genuine (no bot_reports surgery). Drives the
  # "more previews hidden" indicator on the report UI and is a reusable
  # fixture for any future test that needs a large unresolved set.
  $self->_synthetic_many_unresolved_fixture($app, $usr_id);

  $app->minion->perform_jobs();

  # Inflate the perl-Mojolicious Apache-2.0 risk-5 bucket with 100 fake files
  # so the UI test can verify the per-license file-list cap
  # (min_files_short_report) keeps the in-bucket file list manageable.
  my $db     = $app->pg->db;
  my $row    = $db->select('bot_reports', 'ldig_report', {package => 1})->hash;
  my $report = from_json($row->{ldig_report});

  my $fake_pid = 999999;
  my @fake_ids = 9000 .. 9099;
  $report->{files}{$_} = "fake/lots-of-files/file$_.txt" for @fake_ids;
  $report->{risks}{5}{'Apache-2.0'}{$fake_pid} = [@fake_ids];

  $db->update('bot_reports', {ldig_report => to_json($report)}, {package => 1});

  # Seed notes on perl-Mojolicious so the Notes tab has data the moment
  # the UI test opens either review #1 (mojo#1) or review #2 (mojo#2). The two
  # bot_packages rows share the package name and the notes are stored under
  # the name, so both reports should show the same list. The dummy auth flow
  # creates "tester" only on first login, so all seeds are authored by the
  # existing test_bot user; tests verify admin-delete by logging in as tester
  # and self-delete by writing a new note first.
  my $bot_id = $app->users->find(login => 'test_bot')->{id};
  my $notes  = $app->notes;

  # 25 seeded notes so endless scroll must fetch a second page (default
  # page size is 20). The oldest entry doubles as a lawyer-only fixture so
  # the lawyer-only highlighting + tab-badge tinting always have data when
  # an admin views the second page.
  for my $i (1 .. 25) {
    my $lawyer = $i == 1 ? 1 : 0;
    my $body
      = $i == 25
      ? "Latest review notes.\n\n* check Apache-2.0 obligations\n* verify shipped LICENSE"
      : "Seed note #$i for **perl-Mojolicious**.";
    $notes->add(1, 'perl-Mojolicious', $bot_id, $body, $lawyer, $i == 25 ? 1 : 0);
  }

  # Product codestreams: two annotated to one deliverable (so the listing collapses them and the report
  # for perl-Mojolicious shows a single product name) plus one unannotated codestream (raw-name fallback)
  my $products = $app->products;
  my $mlm1     = $products->find_or_create('SUSE:SLE-15-SP7:Update:Products:MLM51')->{id};
  my $mlm2     = $products->find_or_create('SUSE:SLE-15-SP7:Update:Products:MLM51:Update')->{id};
  my $factory  = $products->find_or_create('openSUSE:Factory')->{id};
  $products->update($mlm1,    [1]);
  $products->update($mlm2,    [2]);
  $products->update($factory, [1]);
  $products->set_annotation('SUSE:SLE-15-SP7:Update:Products:MLM51',        'Multi-Linux Manager');
  $products->set_annotation('SUSE:SLE-15-SP7:Update:Products:MLM51:Update', 'Multi-Linux Manager');

  # A brand-new-license proposal exactly as the cavil-missing-licenses agent files it: an unresolved
  # mojo#2 snippet, researched to a license Cavil does not know yet, at a chosen risk. No web flow creates
  # a new_license action (only the MCP propose path does), so the lawyer's ratify journey on the Missing
  # Licenses page legitimately starts from a seeded proposal.
  my $reported = $db->query(
    'SELECT s.id, s.text FROM file_snippets fs JOIN snippets s ON s.id = fs.snippet
       WHERE fs.package = 2 AND fs.resolution IS NULL AND fs.generation = 0 LIMIT 1'
  )->hash;
  $db->insert(
    'proposed_changes',
    {
      action       => 'new_license',
      token_hexsum => 'uinewlicense00000000000000000001',
      owner        => $bot_id,
      data         => {
        -json => {
          snippet     => $reported->{id},
          pattern     => $reported->{text},
          from        => 'perl-Mojolicious',
          package     => 2,
          license     => 'UI-New-License-1.0',
          risk        => 2,
          ai_assisted => 1,
          reason      => "AI Assistant: **UI New License 1.0 (no SPDX id) - risk 2.** A permissive license.\n\n"
            . "**Risk rationale**\nThe only condition is preserving the attribution notice, so risk 2.\n\n"
            . "**Double-check before accepting**\nNot on the SPDX list; confirm the license name first."
        }
      }
    }
  );
}

# Real pipeline fixture with more distinct unresolved files than the preview cap.
sub _synthetic_many_unresolved_fixture ($self, $app, $usr_id) {
  my $checkout_md5 = 'cafefeed00000000000000000000abcd';
  my $synth_dir    = $self->checkout_dir->child('synthetic-many-unresolved', $checkout_md5)->make_path;

  $synth_dir->child('synthetic-many-unresolved.spec')->spew(<<'SPEC');
Name:           synthetic-many-unresolved
Version:        1.0
Release:        0
Summary:        Synthetic package with many unresolved keyword matches
License:        Artistic-2.0
Group:          Development/Libraries/Perl
Source0:        synthetic-many-unresolved-1.0.tar.gz
BuildArch:      noarch

%description
Each generated source file contains the keyword
"PUDDLE_OF_SYNTHETIC_KEYWORDS appears in this exact spot" which is
registered as a keyword pattern with no license, so every file becomes
an unresolved match after indexing.
SPEC

  # Unique context prevents cross-file snippet deduplication.
  my $stage = tempdir;
  my $src   = $stage->child('synthetic-many-unresolved-1.0')->make_path;
  for my $i (1 .. 110) {
    my $marker = sprintf('UNIQUE_FILE_MARKER_%03d', $i);
    $src->child(sprintf('file_%03d.txt', $i))->spew(<<"FILE");
Synthetic file $i for UI testing.

$marker PUDDLE_OF_SYNTHETIC_KEYWORDS appears in this exact spot.

Trailing padding so the snippet has surrounding context to render.
FILE
  }
  my $tarball = $synth_dir->child('synthetic-many-unresolved-1.0.tar.gz')->to_string;
  system('tar', '-czf', $tarball, '-C', $stage->to_string, 'synthetic-many-unresolved-1.0') == 0
    or die "Failed to create synthetic tarball: $?";

  # Low priority + "zzz_" external_link prefix sort the package to the very
  # end of every open-reviews page so the existing row-index assertions
  # (mojo#1 first, test#6 at row 10, etc.) keep passing.
  my $pkgs   = $app->packages;
  my $pkg_id = $pkgs->add(
    name            => 'synthetic-many-unresolved',
    checkout_dir    => $checkout_md5,
    api_url         => 'https://api.opensuse.org',
    requesting_user => $usr_id,
    project         => 'devel:test',
    package         => 'synthetic-many-unresolved',
    srcmd5          => $checkout_md5,
    priority        => 1
  );
  my $pkg = $pkgs->find($pkg_id);
  $pkg->{external_link} = 'zzz_synth#1';
  $pkgs->update($pkg);
  $pkgs->imported($pkg_id);
  $pkgs->unpack($pkg_id);

  # License-less pattern → every match becomes an unresolved snippet
  $app->patterns->create(
    pattern   => 'PUDDLE_OF_SYNTHETIC_KEYWORDS appears in this exact spot',
    unique_id => '00000000-0000-0000-0000-000000000001'
  );
}

# Two real pipeline versions exercise notice diffs and the five-file display cap.
sub report_notice_fixtures ($self, $app) {
  $app->pg->migrations->migrate;

  my $pkgs   = $app->packages;
  my $usr_id = $app->pg->db->insert('bot_users', {login => 'test_bot'}, {returning => 'id'})->hash->{id};

  # License-less keyword pattern → every match becomes an unresolved snippet
  $app->patterns->create(
    pattern   => 'PUDDLE_OF_SYNTHETIC_KEYWORDS appears in this exact spot',
    unique_id => '00000000-0000-0000-0000-000000000042'
  );

  # A licensed pattern so version 2 can gain a genuinely new license (Apache-2.0)
  $app->patterns->create(
    pattern   => 'report-notice distinctive apache license marker',
    license   => 'Apache-2.0',
    risk      => 5,
    unique_id => '00000000-0000-0000-0000-000000000043'
  );
  $app->pg->db->query('UPDATE license_patterns SET spdx = $1 WHERE license = $1', 'Apache-2.0');

  # Build a synthetic package version on disk and run it through the pipeline.
  # Each numeric marker in @$files becomes one file with one unresolved match;
  # distinct markers keep every snippet hash unique so they count as "new".
  # $extra is an optional map of relative filename => literal content for files
  # that should resolve to a license instead of being unresolved. $name picks
  # the package the version belongs to; closest-match lookups are per name, so
  # a second name is an independent history.
  my $build = sub ($md5, $files, $extra = {}, $name = 'report-notice') {
    my $dir = $self->checkout_dir->child($name, $md5)->make_path;
    $dir->child("$name.spec")->spew(<<"SPEC");
Name:           $name
Version:        1.0
Release:        0
Summary:        Synthetic package for the new unresolved matches notice
License:        Artistic-2.0
Group:          Development/Libraries/Perl
Source0:        $name-1.0.tar.gz
BuildArch:      noarch

%description
Synthetic package with unresolved keyword matches for UI testing.
SPEC

    my $stage = tempdir;
    my $src   = $stage->child("$name-1.0")->make_path;
    for my $i (@$files) {
      my $marker = sprintf 'UNIQUE_FILE_MARKER_%03d', $i;
      $src->child(sprintf 'file_%03d.txt', $i)->spew(<<"FILE");
Synthetic file $i for UI testing.

$marker PUDDLE_OF_SYNTHETIC_KEYWORDS appears in this exact spot.

Trailing padding so the snippet has surrounding context to render.
FILE
    }
    $src->child($_)->spew($extra->{$_}) for sort keys %$extra;
    my $tarball = $dir->child("$name-1.0.tar.gz")->to_string;
    system('tar', '-czf', $tarball, '-C', $stage->to_string, "$name-1.0") == 0
      or die "Failed to create synthetic tarball: $?";

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
    $pkgs->unpack($pkg_id);
    $app->minion->perform_jobs;
    return $pkg_id;
  };

  # Only accepted versions qualify as comparison baselines.
  my $v1   = $build->('a0000000000000000000000000000001', [1, 2]);
  my $pkg1 = $pkgs->find($v1);
  $pkg1->{reviewing_user}   = $usr_id;
  $pkg1->{result}           = 'Reviewed ok';
  $pkg1->{state}            = 'acceptable';
  $pkg1->{review_timestamp} = 1;
  $pkgs->update($pkg1);

  # Version 2 adds eight unresolved files and one license.
  $build->(
    'b0000000000000000000000000000002',
    [101 .. 108],
    {'LICENSE-APACHE.txt' => "report-notice distinctive apache license marker\n"}
  );

  # A separate name isolates the no-significant-difference history.
  my $other = 'report-notice-same';
  my $same1 = $build->('c0000000000000000000000000000003', [1, 2], {}, $other);
  my $pkg3  = $pkgs->find($same1);
  $pkg3->{reviewing_user}   = $usr_id;
  $pkg3->{result}           = 'Reviewed ok';
  $pkg3->{state}            = 'acceptable';
  $pkg3->{review_timestamp} = 1;
  $pkgs->update($pkg3);
  $build->('d0000000000000000000000000000004', [1], {}, $other);
}

# Two files that both exceed the (test-lowered) max_file_browser_size, so the standalone file browser
# shows only their top and appends the end-of-file marker. "top-heavy.txt" keeps its one license match
# in the shown header (marker reassures: no matches below); "hidden-match.txt" repeats the match well
# past the cut (marker warns: one match below). The wrapper sets max_file_browser_size to 2000 bytes.
sub large_file_fixtures ($self, $app) {
  $app->pg->migrations->migrate;

  my $pkgs   = $app->packages;
  my $usr_id = $app->pg->db->insert('bot_users', {login => 'test_bot'}, {returning => 'id'})->hash->{id};

  # A distinctive licensed marker so each occurrence is a real risk-3 pattern match
  $app->patterns->create(
    pattern   => 'large file lab license marker',
    license   => 'MIT',
    risk      => 3,
    unique_id => '00000000-0000-0000-0000-0000000000aa'
  );
  $app->pg->db->query('UPDATE license_patterns SET spdx = $1 WHERE license = $1', 'MIT');

  my $md5 = 'aa00000000000000000000000000aa01';
  my $dir = $self->checkout_dir->child('large-file', $md5)->make_path;

  # ~46 bytes per filler line, so both files clear 2000 bytes many times over. The header marker sits in
  # the shown window; hidden-match repeats it at line 82 (~3.7 KB in), comfortably past the 2000 byte cut.
  my $filler = sub {
    join '', map { sprintf "large file lab filler line %03d padding padding\n", $_ } $_[0] .. $_[1];
  };
  $dir->child('top-heavy.txt')->spew("large file lab license marker\n" . $filler->(1, 150));
  $dir->child('hidden-match.txt')
    ->spew(
    "large file lab license marker\n" . $filler->(1, 80) . "large file lab license marker\n" . $filler->(81, 150));

  my $pkg_id = $pkgs->add(
    name            => 'large-file',
    checkout_dir    => $md5,
    api_url         => 'https://api.opensuse.org',
    requesting_user => $usr_id,
    project         => 'devel:test',
    package         => 'large-file',
    srcmd5          => $md5,
    priority        => 5
  );
  $pkgs->imported($pkg_id);
  $pkgs->unpack($pkg_id);
  $app->minion->perform_jobs;

  return $pkg_id;
}

sub compatibility_fixtures ($self, $app) {
  $app->pg->migrations->migrate;

  my $pkgs   = $app->packages;
  my $usr_id = $app->pg->db->insert('bot_users', {login => 'test_bot'}, {returning => 'id'})->hash->{id};

  # SPDX-tag patterns for two licenses the OSADL matrix marks incompatible in both directions, so the
  # report gains a real license compatibility sub-matrix with a hard ("No") conflict.
  for my $license ('Apache-2.0', 'GPL-2.0-only') {
    $app->patterns->create(pattern => "SPDX-License-Identifier: $license", license => $license);
  }
  $app->pg->db->query('UPDATE license_patterns SET spdx = license WHERE license IN (?, ?)',
    'Apache-2.0', 'GPL-2.0-only');

  my $name = 'license-compat';
  my $md5  = 'c0000000000000000000000000000001';
  my $dir  = $self->checkout_dir->child($name, $md5)->make_path;
  $dir->child("$name.spec")->spew(<<"SPEC");
Name:           $name
Version:        1.0
Release:        0
Summary:        Synthetic package with incompatible licenses for UI testing
License:        Artistic-2.0
Group:          Development/Libraries/Perl
Source0:        $name-1.0.tar.gz
BuildArch:      noarch

%description
Synthetic package pairing Apache-2.0 with GPL-2.0-only for the compatibility matrix.
SPEC

  my $stage = tempdir;
  my $src   = $stage->child("$name-1.0")->make_path;
  $src->child('apache_file.txt')->spew("# SPDX-License-Identifier: Apache-2.0\n\nA permissively licensed helper.\n");
  $src->child('gpl2_file.txt')->spew("# SPDX-License-Identifier: GPL-2.0-only\n\nA strong copyleft component.\n");
  my $tarball = $dir->child("$name-1.0.tar.gz")->to_string;
  system('tar', '-czf', $tarball, '-C', $stage->to_string, "$name-1.0") == 0
    or die "Failed to create synthetic tarball: $?";

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
  $pkgs->unpack($pkg_id);
  $app->minion->perform_jobs;
  return $pkg_id;
}

sub legal_documents_fixtures ($self, $app) {
  $app->pg->migrations->migrate;

  my $pkgs   = $app->packages;
  my $usr_id = $app->pg->db->insert('bot_users', {login => 'test_bot'}, {returning => 'id'})->hash->{id};

  for my $license ('MIT', 'Apache-2.0', 'ISC') {
    $app->patterns->create(pattern => "SPDX-License-Identifier: $license", license => $license);
  }
  $app->pg->db->query('UPDATE license_patterns SET spdx = license WHERE license IN (?, ?, ?)',
    'MIT', 'Apache-2.0', 'ISC');

  # A body pattern, so a fully recognised document can be longer than a one-line SPDX stub
  my $mit_body = <<'MIT';
Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above permission notice shall be included in all copies or substantial
portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
MIT
  $app->patterns->create(pattern => $mit_body, license => 'MIT');

  # A package carrying one of each thing the documents list has to get right: a LICENSE whose terms are
  # only partly recognised, a vendored dependency's own license that must not bury it, and a Go source
  # file named after a license word that is not a document at all.
  my $name = 'legal-docs';
  my $md5  = 'd0000000000000000000000000000001';
  my $dir  = $self->checkout_dir->child($name, $md5)->make_path;
  $dir->child("$name.spec")->spew(<<"SPEC");
Name:           $name
Version:        1.0
Release:        0
Summary:        Synthetic package with a partly unrecognised license file for UI testing
License:        MIT
Group:          Development/Libraries/Perl
Source0:        $name-1.0.tar.gz
BuildArch:      noarch

%description
Synthetic package whose LICENSE carries terms Cavil does not recognise.
SPEC

  my $stage = tempdir;
  my $src   = $stage->child("$name-1.0")->make_path;
  $src->child('LICENSE')->spew(<<'LICENSE');
SPDX-License-Identifier: MIT

You may not use this software for evil.
You may not use this software commercially without a separate agreement.
Contact sales@example.com for enterprise terms.
LICENSE

  # A second, much longer document, so the list has two rows whose counts differ in width. The panel
  # aligns its numbers into a column and a single-row fixture could never show that.
  $src->child('COPYING')->spew(join "\n", '# SPDX-License-Identifier: Apache-2.0',
    '', (map {"Clause $_ of some unrecognised terms."} 1 .. 119), '');

  # Lines over 115 characters trip the line-wrapper, so Cavil indexes its own COPYRIGHT.processed copy
  # and the report has a name carrying that marker. Only the keyword pattern matches it, and keywords are
  # not recognition, so it is also the document with nothing recognised in it at all.
  $app->patterns->create(pattern => 'a distinctly unrecognised clause');
  $src->child('COPYRIGHT')->spew(('a distinctly unrecognised clause ' x 12) . "\n");

  # Nothing left over, and between two documents that have some, where a collapsing slot would show
  $src->child('LICENSE.MIT')->spew($mit_body);

  # The case the whole panel exists for: a couple of novel lines on an otherwise stock license body
  $src->child('LICENSE.enterprise')
    ->spew($mit_body
      . "\nYou may not use this software commercially without a separate agreement.\n"
      . "Contact sales\@example.com for enterprise terms.\n");

  # Buried the way TeX Live buries them, so the list has a path long enough for the directory to recede
  $src->child('fonts', 'tex-gyre', 'META-INF')->make_path->child('LICENSE')
    ->spew("# SPDX-License-Identifier: Apache-2.0\n\nTerms nobody recognises.\n");

  # The only ISC in the package, so the license list can say it is vendored and nothing else
  $src->child('vendor', 'helper')->make_path->child('LICENSE')
    ->spew("# SPDX-License-Identifier: ISC\n\nA bundled dependency's own terms.\n");
  $src->child('src')->make_path->child('license.go')->spew("# SPDX-License-Identifier: MIT\n\npackage main\n");

  my $tarball = $dir->child("$name-1.0.tar.gz")->to_string;
  system('tar', '-czf', $tarball, '-C', $stage->to_string, "$name-1.0") == 0
    or die "Failed to create synthetic tarball: $?";

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
  $pkgs->unpack($pkg_id);

  # A package of its own, because a panel with no remainder anywhere is a different panel
  my $clean_name = 'legal-docs-clean';
  my $clean_md5  = 'd0000000000000000000000000000002';
  my $clean_dir  = $self->checkout_dir->child($clean_name, $clean_md5)->make_path;
  $clean_dir->child("$clean_name.spec")->spew(<<"SPEC");
Name:           $clean_name
Version:        1.0
Release:        0
Summary:        Synthetic package whose license files Cavil fully recognises
License:        MIT
Group:          Development/Libraries/Perl
Source0:        $clean_name-1.0.tar.gz
BuildArch:      noarch

%description
Synthetic package carrying nothing but stock license text.
SPEC

  my $clean_stage = tempdir;
  my $clean_src   = $clean_stage->child("$clean_name-1.0")->make_path;
  $clean_src->child('COPYING')->spew($mit_body);
  $clean_src->child('LICENSE')->spew("SPDX-License-Identifier: MIT\n");
  my $clean_tarball = $clean_dir->child("$clean_name-1.0.tar.gz")->to_string;
  system('tar', '-czf', $clean_tarball, '-C', $clean_stage->to_string, "$clean_name-1.0") == 0
    or die "Failed to create synthetic tarball: $?";

  my $clean_id = $pkgs->add(
    name            => $clean_name,
    checkout_dir    => $clean_md5,
    api_url         => 'https://api.opensuse.org',
    requesting_user => $usr_id,
    project         => 'devel:test',
    package         => $clean_name,
    srcmd5          => $clean_md5,
    priority        => 5
  );
  $pkgs->imported($clean_id);
  $pkgs->unpack($clean_id);

  # More documents than the panel lists, so the count of what it leaves out has something to report
  my $many_name = 'legal-docs-many';
  my $many_md5  = 'd0000000000000000000000000000003';
  my $many_dir  = $self->checkout_dir->child($many_name, $many_md5)->make_path;
  $many_dir->child("$many_name.spec")->spew(<<"SPEC");
Name:           $many_name
Version:        1.0
Release:        0
Summary:        Synthetic package with more license files than the list shows
License:        MIT
Group:          Development/Libraries/Perl
Source0:        $many_name-1.0.tar.gz
BuildArch:      noarch

%description
Synthetic package carrying one license file per bundled component.
SPEC

  my $many_stage = tempdir;
  my $many_src   = $many_stage->child("$many_name-1.0")->make_path;
  $many_src->child(sprintf 'LICENSE.%02d', $_)->spew("SPDX-License-Identifier: MIT\n") for 1 .. 30;
  my $many_tarball = $many_dir->child("$many_name-1.0.tar.gz")->to_string;
  system('tar', '-czf', $many_tarball, '-C', $many_stage->to_string, "$many_name-1.0") == 0
    or die "Failed to create synthetic tarball: $?";

  my $many_id = $pkgs->add(
    name            => $many_name,
    checkout_dir    => $many_md5,
    api_url         => 'https://api.opensuse.org',
    requesting_user => $usr_id,
    project         => 'devel:test',
    package         => $many_name,
    srcmd5          => $many_md5,
    priority        => 5
  );
  $pkgs->imported($many_id);
  $pkgs->unpack($many_id);

  $app->minion->perform_jobs;
  return $pkg_id;
}

sub obligations_fixtures ($self, $app) {
  $app->pg->migrations->migrate;

  my $pkgs   = $app->packages;
  my $usr_id = $app->pg->db->insert('bot_users', {login => 'test_bot'}, {returning => 'id'})->hash->{id};

  # Apache-2.0 has a rich OSADL obligation checklist (two delivery use cases, YOU MUST / YOU MUST NOT,
  # patent hints); the expression "MIT OR BSD-3-Clause" exercises per-constituent decomposition (two
  # named sections); and "BSD-2-Clause AND Beerware" is an expression where only one constituent is
  # OSADL-known (Beerware has no checklist, only SPDX flags), so the panel must still name BSD-2-Clause
  # to attribute the obligations it does show.
  $app->patterns->create(pattern => 'SPDX-License-Identifier: Apache-2.0',          license => 'Apache-2.0');
  $app->patterns->create(pattern => 'SPDX-License-Identifier: MIT OR BSD-3-Clause', license => 'MIT OR BSD-3-Clause');
  $app->patterns->create(
    pattern => 'SPDX-License-Identifier: BSD-2-Clause AND Beerware',
    license => 'BSD-2-Clause AND Beerware'
  );

  # A "WITH <exception>" license: obligations show the base license (GPL-2.0-or-later) and the panel flags
  # the exception, since OSADL's checklist covers the base license only.
  $app->patterns->create(
    pattern => 'SPDX-License-Identifier: GPL-2.0-or-later WITH Classpath-exception-2.0',
    license => 'GPL-2.0-or-later WITH Classpath-exception-2.0'
  );

  # Two licenses OSADL publishes no checklist for, where SPDX classification is all there is: the panel
  # labels itself "Details" instead of "Obligations". CC-BY-4.0 is the plain case (not OSI approved, but
  # FSF libre); MPL-1.0 is the one the FSF has never ruled on, so its panel must show no FSF row at all.
  $app->patterns->create(pattern => 'SPDX-License-Identifier: CC-BY-4.0', license => 'CC-BY-4.0');
  $app->patterns->create(pattern => 'SPDX-License-Identifier: MPL-1.0',   license => 'MPL-1.0');

  $app->pg->db->query(
    'UPDATE license_patterns SET spdx = license WHERE license IN (?, ?, ?, ?, ?, ?)',
    'Apache-2.0',
    'MIT OR BSD-3-Clause',
    'BSD-2-Clause AND Beerware',
    'GPL-2.0-or-later WITH Classpath-exception-2.0',
    'CC-BY-4.0', 'MPL-1.0'
  );

  my $name = 'license-obligations';
  my $md5  = 'd0000000000000000000000000000001';
  my $dir  = $self->checkout_dir->child($name, $md5)->make_path;
  $dir->child("$name.spec")->spew(<<"SPEC");
Name:           $name
Version:        1.0
Release:        0
Summary:        Synthetic package for obligation checklist UI testing
License:        Apache-2.0
Group:          Development/Libraries/Perl
Source0:        $name-1.0.tar.gz
BuildArch:      noarch

%description
Synthetic package pairing Apache-2.0 with a "MIT OR BSD-3-Clause" expression for the obligations panel.
SPEC

  my $stage = tempdir;
  my $src   = $stage->child("$name-1.0")->make_path;
  $src->child('apache_file.txt')->spew("# SPDX-License-Identifier: Apache-2.0\n\nA permissively licensed helper.\n");
  $src->child('expr_file.txt')
    ->spew("# SPDX-License-Identifier: MIT OR BSD-3-Clause\n\nEither license may be chosen.\n");
  $src->child('partial_file.txt')
    ->spew("# SPDX-License-Identifier: BSD-2-Clause AND Beerware\n\nOne constituent is unknown to OSADL.\n");
  $src->child('exception_file.txt')
    ->spew("# SPDX-License-Identifier: GPL-2.0-or-later WITH Classpath-exception-2.0\n\nBase plus an exception.\n");
  $src->child('details_file.txt')->spew("# SPDX-License-Identifier: CC-BY-4.0\n\nDocumentation, not code.\n");
  $src->child('no_fsf_file.txt')->spew("# SPDX-License-Identifier: MPL-1.0\n\nThe FSF never ruled on this one.\n");
  my $tarball = $dir->child("$name-1.0.tar.gz")->to_string;
  system('tar', '-czf', $tarball, '-C', $stage->to_string, "$name-1.0") == 0
    or die "Failed to create synthetic tarball: $?";

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
  $pkgs->unpack($pkg_id);
  $app->minion->perform_jobs;
  return $pkg_id;
}

sub unpack_fixtures ($self, $app) {
  $self->no_fixtures($app);

  my $dir       = $self->checkout_dir;
  my $legal_bot = path(__FILE__)->dirname->dirname->dirname->child('legal-bot');
  my $good      = $dir->child('buildah-synthetic-good', 'c7cfdab0e71b0bebfdf8b2dc3badfecf')->make_path;
  $_->copy_to($good->child($_->basename)) for $legal_bot->child('buildah-synthetic-good')->list->each;
  my $good_too = $dir->child('buildah-synthetic-good-too', 'c7cfdab0e71b0bebfdf8b2dc3badfedf')->make_path;
  $_->copy_to($good_too->child($_->basename)) for $legal_bot->child('buildah-synthetic-good')->list->each;
  my $broken = $dir->child('buildah-synthetic-broken', 'da3e32a3cce8bada03c6a9d63c08cd59')->make_path;
  $_->copy_to($broken->child($_->basename)) for $legal_bot->child('buildah-synthetic-broken')->list->each;

  my $usr_id = $app->pg->db->insert('bot_users', {login => 'test_bot'}, {returning => 'id'})->hash->{id};
  my $pkgs   = $app->packages;
  my $pkg_id = $pkgs->add(
    name            => 'buildah-synthetic-good',
    checkout_dir    => 'c7cfdab0e71b0bebfdf8b2dc3badfecf',
    api_url         => 'https://api.opensuse.org',
    requesting_user => $usr_id,
    project         => 'devel:whatever',
    package         => 'buildah-synthetic-good',
    srcmd5          => 'bd91c36647a5d3dd883d490da2140402',
    priority        => 5
  );
  $pkgs->imported($pkg_id);
  my $pkg2_id = $pkgs->add(
    name            => 'buildah-synthetic-good-too',
    checkout_dir    => 'c7cfdab0e71b0bebfdf8b2dc3badfedf',
    api_url         => 'https://api.opensuse.org',
    requesting_user => $usr_id,
    project         => 'devel:whatever',
    package         => 'buildah-synthetic-good-too',
    srcmd5          => 'bd91c36647a5d3dd883d490da2140402',
    priority        => 5
  );
  $pkgs->imported($pkg2_id);
  my $pkg3_id = $pkgs->add(
    name            => 'buildah-synthetic-broken',
    checkout_dir    => 'da3e32a3cce8bada03c6a9d63c08cd59',
    api_url         => 'https://api.opensuse.org',
    requesting_user => 1,
    project         => 'devel:whatever',
    package         => 'buildah-synthetic-broken',
    srcmd5          => 'da3e32a3cce8bada03c6a9d63c08cd59',
    priority        => 5
  );
  $pkgs->imported($pkg3_id);
  my $patterns = $app->patterns;
  $patterns->create(pattern => 'You may obtain a copy of the License at', license => 'Apache-2.0');
  $patterns->create(pattern => 'License: Artistic-2.0',                   license => 'Artistic-2.0');
  $patterns->create(pattern => 'copyright');
}

# PostgreSQL's "CREATE EXTENSION IF NOT EXISTS" is not safe under concurrency: parallel test files
# can all see the extension missing and then race to insert it, tripping a duplicate-key error on
# pg_extension_name_index. Create the extensions the migrations need once, in the shared public schema
# (so they survive per-test schema drops), serialized by a transaction advisory lock. Every later
# migration then finds them present and its own CREATE EXTENSION is a harmless no-op.
sub _ensure_extensions ($self) {
  my $db = $self->{pg}->db;
  my $tx = $db->begin;
  $db->query('SELECT pg_advisory_xact_lock(742019)');
  $db->query('CREATE EXTENSION IF NOT EXISTS "pgcrypto" WITH SCHEMA public');
  $db->query('CREATE EXTENSION IF NOT EXISTS "pg_trgm" WITH SCHEMA public');
  $tx->commit;
}

sub _prepare_schema ($self, $name) {

  # Isolate tests
  my $pg = $self->{pg};
  $pg->db->query("drop schema if exists $name cascade");
  $pg->db->query("create schema $name");

  # Clean up once we are done
  return scope_guard sub { $pg->db->query("drop schema $name cascade") };
}

1;
