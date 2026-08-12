# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Mojo::Base -strict;

use Test::More;

subtest 'cleanup' => sub {
  require Cavil::Command::cleanup;
  my $cmd = Cavil::Command::cleanup->new;
  ok $cmd->description, 'has a description';
  like $cmd->usage, qr/cleanup/, 'has usage information';
};

subtest 'git' => sub {
  require Cavil::Command::git;
  my $cmd = Cavil::Command::git->new;
  ok $cmd->description, 'has a description';
  like $cmd->usage, qr/git/, 'has usage information';
};

subtest 'migrate' => sub {
  require Cavil::Command::migrate;
  my $cmd = Cavil::Command::migrate->new;
  ok $cmd->description, 'has a description';
  like $cmd->usage, qr/migrate/, 'has usage information';
};

subtest 'obs' => sub {
  require Cavil::Command::obs;
  my $cmd = Cavil::Command::obs->new;
  ok $cmd->description, 'has a description';
  like $cmd->usage, qr/obs/, 'has usage information';
};

subtest 'patterns' => sub {
  require Cavil::Command::patterns;
  my $cmd = Cavil::Command::patterns->new;
  ok $cmd->description, 'has a description';
  like $cmd->usage, qr/patterns/, 'has usage information';
};

subtest 'rindex' => sub {
  require Cavil::Command::rindex;
  my $cmd = Cavil::Command::rindex->new;
  ok $cmd->description, 'has a description';
  like $cmd->usage, qr/rindex/, 'has usage information';
};

subtest 'sync' => sub {
  require Cavil::Command::sync;
  my $cmd = Cavil::Command::sync->new;
  ok $cmd->description, 'has a description';
  like $cmd->usage, qr/sync/, 'has usage information';
};

subtest 'unpack' => sub {
  require Cavil::Command::unpack;
  my $cmd = Cavil::Command::unpack->new;
  ok $cmd->description, 'has a description';
  like $cmd->usage, qr/unpack/, 'has usage information';
};

subtest 'user' => sub {
  require Cavil::Command::user;
  my $cmd = Cavil::Command::user->new;
  ok $cmd->description, 'has a description';
  like $cmd->usage, qr/user/, 'has usage information';
};

done_testing();
