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
      overlap_guard   => 0.9
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

  # Create checkout directory
  my $dir       = $self->checkout_dir;
  my @src       = ('perl-Mojolicious', 'c7cfdab0e71b0bebfdf8b2dc3badfecd');
  my $mojo      = $dir->child(@src)->make_path;
  my $legal_bot = path(__FILE__)->dirname->dirname->dirname->child('legal-bot');
  $_->copy_to($mojo->child($_->basename)) for $legal_bot->child(@src)->list->each;
  @src  = ('perl-Mojolicious', 'da3e32a3cce8bada03c6a9d63c08cd58');
  $mojo = $dir->child(@src)->make_path;
  $_->copy_to($mojo->child($_->basename)) for $legal_bot->child(@src)->list->each;

  # Create fixtures
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

  # Checkout whose source archive vendors npm and cargo modules under obscured directory names
  my @src       = ('vendored', 'da39a3ee5e6b4b0d3255bfef95601890');
  my $checkout  = $self->checkout_dir->child(@src)->make_path;
  my $legal_bot = path(__FILE__)->dirname->dirname->dirname->child('legal-bot');
  $_->copy_to($checkout->child($_->basename)) for $legal_bot->child(@src)->list->each;

  # A license pattern so Cavil can detect the license of the vendored module whose metadata omits one
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

  # Create checkout directory
  my $dir = $self->checkout_dir;
  my @src = ('package-with-snippets', '2a0737e27a3b75590e7fab112b06a76fe7573615');
  my $src = $dir->child(@src)->make_path;
  $_->copy_to($src->child($_->basename))
    for path(__FILE__)->dirname->dirname->dirname->child('legal-bot', @src)->list->each;

  # Create fixtures
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

# Synthetic fixture for the snippet fold-in UI test: index a package, make every snippet a
# confident, current-version GPL match, and regenerate the report so it folds. Requires the app to
# be built with snippet_fold enabled.
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

# Synthetic fixture for the boilerplate-clear UI test: index a package, then make every snippet a
# high-containment but zero-margin match of a synthetic license so it can only *clear* (never fold).
# The synthetic license cannot appear from any real match, so its absence proves clearing asserts
# nothing. Requires the app to be built with snippet_fold clear_threshold enabled.
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

# Synthetic fixture for the overlap-clear UI test: index a package, make every snippet classifier-legal
# but unscored (so similarity can never resolve it), and add a real GPL match on each snippet's first
# line so the snippet's region overlaps a curated license match. Requires snippet_fold overlap_clear on.
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

# Synthetic fixture for the Classify Snippets triage UI test: a controlled mix of snippets with known
# fold/clear status and distinct, searchable text - 12 would-fold (wide margin, one of them a
# Non-Commercial stemming case), 1 would-clear (zero margin), 1 neither (low similarity). Requires the
# app to be built with snippet_fold thresholds (and clear_threshold) set.
sub snippet_triage_fixtures ($self, $app) {
  $self->package_with_snippets_fixtures($app);
  my $db   = $app->pg->db;
  my $fold = $app->patterns->create(pattern => 'a folded triage marker for ui', license => 'Triage-Fold', risk => 3);

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
        like_pattern  => $fold->{id}
      },
      {returning => 'id'}
    )->hash->{id};
    $db->insert('file_snippets', {package => 1, file => $file, snippet => $sid, sline => $line, eline => $line + 5});
  };

  $insert->(likelyness => 0.99, second_match => 0.5,  text => "fold marker body number $_ with GPL terms") for 1 .. 11;
  $insert->(likelyness => 0.99, second_match => 0.5,  text => 'fold marker Non-Commercial use clause body');
  $insert->(likelyness => 0.99, second_match => 0.99, text => 'cleared boilerplate definitions body');
  $insert->(likelyness => 0.40, second_match => 0.0,  text => 'unresolved random noise body');

  $app->snippets->resolve_snippets(1);
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
}

# Builds a real, indexable test package whose files each contain one
# distinctive keyword that matches a license-less pattern. The result is a
# fully analyzed package with one unresolved snippet per file, comfortably
# more than `max_expanded_files`. Generates the tarball + spec on disk so
# the regular unpack pipeline can process it; no bot_reports surgery.
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

  # Each file gets a unique marker adjacent to the keyword so the snippet
  # hash (which includes ~5 words of context around the keyword) is distinct
  # per file. Without this, all 110 files would share one snippet and only
  # one missed-file would be reported.
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

sub unpack_fixtures ($self, $app) {
  $self->no_fixtures($app);

  # Create checkout directory
  my $dir       = $self->checkout_dir;
  my $legal_bot = path(__FILE__)->dirname->dirname->dirname->child('legal-bot');
  my $good      = $dir->child('buildah-synthetic-good', 'c7cfdab0e71b0bebfdf8b2dc3badfecf')->make_path;
  $_->copy_to($good->child($_->basename)) for $legal_bot->child('buildah-synthetic-good')->list->each;
  my $good_too = $dir->child('buildah-synthetic-good-too', 'c7cfdab0e71b0bebfdf8b2dc3badfedf')->make_path;
  $_->copy_to($good_too->child($_->basename)) for $legal_bot->child('buildah-synthetic-good')->list->each;
  my $broken = $dir->child('buildah-synthetic-broken', 'da3e32a3cce8bada03c6a9d63c08cd59')->make_path;
  $_->copy_to($broken->child($_->basename)) for $legal_bot->child('buildah-synthetic-broken')->list->each;

  # Create fixtures
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
