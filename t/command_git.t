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

use Mojo::Base -strict;

use FindBin;
use lib "$FindBin::Bin/lib";

use Test::More;
use Test::Mojo;
use Cavil::Test;
use Cavil::Util qw(run_cmd);
use Mojo::File  qw(tempdir);

plan skip_all => 'set TEST_ONLINE to enable this test' unless $ENV{TEST_ONLINE};

my $cavil_test = Cavil::Test->new(online => $ENV{TEST_ONLINE}, schema => 'command_git_test');
my $config     = $cavil_test->default_config;
my $t          = Test::Mojo->new(Cavil => $config);
my $app        = $t->app;
$cavil_test->no_fixtures($app);

subtest 'Git' => sub {
  subtest 'Create package with command' => sub {
    my $buffer = '';
    {
      open my $handle, '>', \$buffer;
      local *STDOUT = $handle;
      $app->start(
        'git',              'https://src.opensuse.org/pool/perl-Mojolicious.git',
        'perl-Mojolicious', '242511548e0cdcf17b6321738e2d8b6a3b79d41775c4a867f03b384a284d9168',
        '-i'
      );
    }
    like $buffer, qr/Triggered git_import job 1/, 'package info';
  };

  subtest 'Import local package' => sub {
    my $src_dir = tempdir;
    my $git     = $t->app->git;
    $git->git_cmd($src_dir, ['init']);
    my $file = $src_dir->child('test.txt')->spew('one');
    $git->git_cmd($src_dir, ['add', '.']);
    $git->git_cmd($src_dir, ['commit', '-m', 'commit one']);
    my $hash = run_cmd($src_dir, ['git', 'rev-parse', 'HEAD'])->{stdout};
    chomp $hash;

    my $headers = {Authorization => "Token $config->{tokens}[0]"};
    $t->get_ok('/package/1', $headers)->status_is(200)->json_is('/state' => 'new')->json_is('/imported' => undef);

    my $minion = $t->app->minion;
    my $args   = $minion->jobs({ids => [1]})->next->{args};
    $args->[1]{url}  = "$src_dir";
    $args->[1]{hash} = $hash;
    $t->app->pg->db->update('minion_jobs', {args => {-json => $args}}, {id => 1});
    my $worker = $minion->worker->register;
    ok my $job = $worker->dequeue(0, {id => $1}), 'job dequeued';
    is $job->execute, undef, 'no error';
    $worker->unregister;

    $t->get_ok('/package/1', $headers)->status_is(200)->json_is('/state' => 'new')->json_like('/imported' => qr/\d/);
  };
};

done_testing();
