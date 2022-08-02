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

use Mojo::File qw(path tempdir);
use Mojo::Pg;
use Mojo::URL;
use Mojo::Util qw(scope_guard);

sub new ($class, %options) {

  # Database
  my $self = $class->SUPER::new(options => \%options);
  $self->{pg}       = Mojo::Pg->new($options{online});
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
    secrets                => ['just_a_test'],
    checkout_dir           => $self->checkout_dir,
    cache_dir              => $self->cache_dir,
    tokens                 => ['test_token'],
    pg                     => $self->postgres_url,
    acceptable_risk        => 3,
    index_bucket_average   => 100,
    cleanup_bucket_average => 50,
    min_files_short_report => 20,
    max_email_url_size     => 26,
    max_task_memory        => 5_000_000_000,
    max_worker_rss         => 100000,
    max_expanded_files     => 100
  };
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
  $patterns->create(pattern => 'You may obtain a copy of the License at', license => 'Apache-2.0');
  $patterns->create(
    packname => 'perl-Mojolicious',
    pattern  => 'Licensed under the Apache License, Version 2.0',
    license  => 'Apache-2.0'
  );
  $patterns->create(pattern => 'License: Artistic-2.0',            license => 'Artistic-2.0');
  $patterns->create(pattern => 'powerful web development toolkit', license => 'SUSE-NotALicense');
  $patterns->create(pattern => 'the terms');
  $patterns->create(pattern => 'copyright notice');
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

sub postgres_url ($self) {
  return Mojo::URL->new($self->{options}{online})->query([search_path => [$self->{options}{schema}, 'public']])
    ->to_unsafe_string;
}

sub ui_fixtures ($self, $app) {
  $app->pg->migrations->migrate;

  $self->mojo_fixtures($app);
  my $pkgs = $app->packages;
  $pkgs->unpack($_) for 1 .. 2;

  # Make sure paging is needed
  my $usr_id = $app->pg->db->insert('bot_users', {login => 'test_bot'}, {returning => 'id'})->hash->{id};
  for my $i (1 .. 21) {
    my $pkg_id = $pkgs->add(
      name            => "perl-UI-Test$i",
      checkout_dir    => 'doesnotexist',
      api_url         => 'https://api.opensuse.org',
      requesting_user => $usr_id,
      project         => 'devel:languages:perl',
      package         => "perl-UI-Test$i",
      srcmd5          => '4041c36647a5d3dd883d490da2140404',
      priority        => 5
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

  $app->minion->perform_jobs();
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

sub _prepare_schema ($self, $name) {

  # Isolate tests
  my $pg = $self->{pg};
  $pg->db->query("drop schema if exists $name cascade");
  $pg->db->query("create schema $name");

  # Clean up once we are done
  return scope_guard sub { $pg->db->query("drop schema $name cascade") };
}

1;
