# Copyright (C) 2021 SUSE LLC
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

use Test::More;

subtest 'classify' => sub {
  require Cavil::Command::classify;
  my $cmd = Cavil::Command::classify->new;
  ok $cmd->description, 'has a description';
  like $cmd->usage, qr/classify/, 'has usage information';
};

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
