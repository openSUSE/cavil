# Copyright (C) 2024 SUSE LLC
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
use Mojo::File  qw(tempdir);
use Cavil::Util qw(run_cmd);
use Cavil::Git;
use Cavil::Test;

plan skip_all => 'set TEST_ONLINE to enable this test' unless $ENV{TEST_ONLINE};

my $git = Cavil::Git->new;

subtest 'Local git' => sub {
  my $src_dir = tempdir;
  $git->git_cmd($src_dir, ['init']);
  my $file = $src_dir->child('test.txt')->spew('one');
  $git->git_cmd($src_dir, ['add', '.']);
  $git->git_cmd($src_dir, ['commit', '-m', 'commit one']);
  my $first_hash = run_cmd($src_dir, ['git', 'rev-parse', 'HEAD'])->{stdout};
  chomp $first_hash;
  $file->spew('two');
  $git->git_cmd($src_dir, ['commit', '-am', 'commit two']);
  my $second_hash = run_cmd($src_dir, ['git', 'rev-parse', 'HEAD'])->{stdout};
  chomp $second_hash;
  $file->spew('three');
  $git->git_cmd($src_dir, ['commit', '-am', 'commit three']);
  my $third_hash = run_cmd($src_dir, ['git', 'rev-parse', 'HEAD'])->{stdout};
  chomp $third_hash;

  subtest 'Download second commit' => sub {
    my $dir = tempdir;
    $git->download_source($src_dir, $dir, {hash => $second_hash});
    my $files = $dir->list_tree({hidden => 1});
    is scalar @$files,                 1,     '1 file in the tree';
    is $dir->child('test.txt')->slurp, 'two', 'right content';
  };

  subtest 'Download first commit' => sub {
    my $dir = tempdir;
    $git->download_source($src_dir, $dir, {hash => $first_hash});
    my $files = $dir->list_tree({hidden => 1});
    is scalar @$files,                 1,     '1 file in the tree';
    is $dir->child('test.txt')->slurp, 'one', 'right content';
  };

  subtest 'Download third commit' => sub {
    my $dir = tempdir;
    $git->download_source($src_dir, $dir, {hash => $third_hash});
    my $files = $dir->list_tree({hidden => 1});
    is scalar @$files,                 1,       '1 file in the tree';
    is $dir->child('test.txt')->slurp, 'three', 'right content';
  };

  subtest 'Bot API (with Minion background jobs)' => sub {
    my $cavil_test = Cavil::Test->new(online => $ENV{TEST_ONLINE}, schema => 'git_import_test');
    my $config     = $cavil_test->default_config;
    my $t          = Test::Mojo->new(Cavil => $config);
    $cavil_test->no_fixtures($t->app);

    my $headers = {Authorization => "Token $config->{tokens}[0]"};

    subtest 'Validation errors' => sub {
      $t->post_ok('/packages')->status_is(403);
      $t->post_ok('/packages', $headers)
        ->status_is(400)
        ->json_is({error => 'Invalid request parameters (api, package, project)'});
      $t->post_ok('/packages', $headers, form => {type => 'git'})
        ->status_is(400)
        ->json_is({error => 'Invalid request parameters (api, package, rev)'});
    };

    subtest 'Standard import' => sub {
      $t->post_ok(
        '/packages' => $headers => form => {
          api     => 'https://src.opensuse.org/pool/perl-Mojolicious.git',
          package => 'perl-Mojolicious',
          rev     => '242511548e0cdcf17b6321738e2d8b6a3b79d41775c4a867f03b384a284d9168',
          type    => 'git'
        }
      )->status_is(200)->json_is('/saved/id' => 1);
      ok !$t->app->packages->is_imported(1), 'not imported yet';
      $t->get_ok('/package/1', $headers)->status_is(200)->json_is('/state' => 'new')->json_is('/imported' => undef);

      my $minion = $t->app->minion;
      my $args   = $minion->jobs({ids => [1]})->next->{args};
      $args->[1]{url}  = "$src_dir";
      $args->[1]{hash} = $second_hash;
      $t->app->pg->db->update('minion_jobs', {args => {-json => $args}}, {id => 1});
      my $worker = $minion->worker->register;
      my $job_id = $minion->jobs({tasks => ['git_import']})->next->{id};
      ok my $job = $worker->dequeue(0, {id => $job_id}), 'job dequeued';
      is $job->execute, undef, 'no error';
      ok $minion->lock('processing_pkg_1', 0), 'lock no longer exists';
      $worker->unregister;
      ok $t->app->packages->is_imported(1), 'imported';

      $t->get_ok('/package/1', $headers)->status_is(200)->json_is('/state' => 'new')->json_like('/imported' => qr/\d/);
      unlike $minion->job($job_id)->info->{result}, qr/Package \d+ is already being processed/, 'no race condition';
    };

    subtest 'Prevent import race condition' => sub {
      my $minion = $t->app->minion;
      my $worker = $minion->worker->register;
      my $job_id = $minion->jobs({tasks => ['git_import']})->next->{id};
      ok $minion->job($job_id)->retry, 'import job retried';
      my $guard = $minion->guard('processing_pkg_1', 172800);
      ok !$minion->lock('processing_pkg_1', 0), 'lock exists';
      $worker->register;
      ok my $job = $worker->dequeue(0, {id => $job_id}), 'job dequeued';
      is $job->execute, undef, 'no error';
      like $minion->job($job_id)->info->{result}, qr/Package \d+ is already being processed/,
        'race condition prevented';
      $worker->unregister;
      undef $guard;
      ok $minion->lock('processing_pkg_1', 0), 'lock no longer exists';
    };
  };
};

subtest 'Live git server tests' => sub {
  plan skip_all => 'set TEST_LIVE to run live tests' unless $ENV{TEST_LIVE};

  subtest 'Source download from GitHub (SSH)' => sub {
    my $dir = tempdir;
    $git->download_source('git@github.com:openSUSE/cavil.git',
      $dir, {hash => 'a1efd571deeb430d03d59075ae9c76a7e79c3988'});
    my $files = $dir->list_tree({hidden => 1});
    is scalar @$files,         300,                 '300 files in the tree';
    is $files->[0]->basename,  '.eslintrc.json',    'first file is .eslintrc.json';
    is $files->[-1]->basename, 'webpack.config.js', 'last file is webpack.config.js';
    like $files->[-1]->slurp, qr/export default config/s, 'right content';
  };

  subtest 'Source download from Gitea (HTTPS)' => sub {
    my $dir = tempdir;
    $git->download_source('https://src.opensuse.org/pool/perl-Mojolicious.git',
      $dir, {hash => '242511548e0cdcf17b6321738e2d8b6a3b79d41775c4a867f03b384a284d9168'});
    my $files = $dir->list_tree({hidden => 1});
    is scalar @$files,         6,                       '6 files in the tree';
    is $files->[0]->basename,  '.gitattributes',        'first file is .gitattributes';
    is $files->[-1]->basename, 'perl-Mojolicious.spec', 'last file is perl-Mojolicious.spec';
    like $files->[-1]->slurp, qr/Version:\s+9\.380\.0/s, 'right content';
  };

  subtest 'Source download from GitHub (bad remote ref)' => sub {
    my $dir = tempdir;
    eval {
      $git->download_source('git@github.com:openSUSE/cavil.git',
        $dir, {hash => 'b1efd571deeb430d03d59075ae9c76a7e79c39899'});
    };
    like $@, qr/Git command "git fetch .+99" failed:.+remote ref b1efd571deeb430d03d59075ae9c76a7e79c39899/s,
      'right error';
  };

  subtest 'Bot API (with Minion background jobs)' => sub {
    my $cavil_test = Cavil::Test->new(online => $ENV{TEST_ONLINE}, schema => 'git_import_live_test');
    my $config     = $cavil_test->default_config;
    my $t          = Test::Mojo->new(Cavil => $config);
    $cavil_test->no_fixtures($t->app);

    my $headers = {Authorization => "Token $config->{tokens}[0]"};

    subtest 'Standard import' => sub {
      $t->post_ok(
        '/packages' => $headers => form => {
          api     => 'https://src.opensuse.org/pool/perl-Mojolicious.git',
          package => 'perl-Mojolicious',
          rev     => '242511548e0cdcf17b6321738e2d8b6a3b79d41775c4a867f03b384a284d9168',
          type    => 'git'
        }
      )->status_is(200)->json_is('/saved/id' => 1);
      ok !$t->app->packages->is_imported(1), 'not imported yet';
      $t->get_ok('/package/1', $headers)->status_is(200)->json_is('/state' => 'new')->json_is('/imported' => undef);

      my $minion = $t->app->minion;
      my $worker = $minion->worker->register;
      my $job_id = $minion->jobs({tasks => ['git_import']})->next->{id};
      ok my $job = $worker->dequeue(0, {id => $job_id}), 'job dequeued';
      is $job->execute, undef, 'no error';
      ok $minion->lock('processing_pkg_1', 0), 'lock no longer exists';
      $worker->unregister;
      ok $t->app->packages->is_imported(1), 'imported';

      $t->get_ok('/package/1', $headers)->status_is(200)->json_is('/state' => 'new')->json_like('/imported' => qr/\d/);
      unlike $minion->job($job_id)->info->{result}, qr/Package \d+ is already being processed/, 'no race condition';
    };
  };
};

done_testing;
