# Copyright (C) 2025 SUSE LLC
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

my $cavil_test = Cavil::Test->new(online => $ENV{TEST_ONLINE}, schema => 'command_unpack_test');
my $config     = $cavil_test->default_config;
my $t          = Test::Mojo->new(Cavil => $config);
my $app        = $t->app;
$cavil_test->mojo_fixtures($app);

my $minion = $app->minion;
$minion->enqueue('unpack', [2]);
$minion->perform_jobs;

subtest 'Unpack' => sub {
  subtest 'Re-unpack package' => sub {
    is $app->minion->jobs({tasks => ['unpack']})->total, 1, 'one unpack job';
    my $buffer = '';
    {
      open my $handle, '>', \$buffer;
      local *STDOUT = $handle;
      $app->start('unpack', '2');
    }
    unlike $buffer, qr/Releasing locks/,      'no locks released';
    like $buffer,   qr/Triggered unpack job/, 'unpack job triggered';
    is $app->minion->jobs({tasks => ['unpack']})->total, 2, 'two unpack jobs';
  };

  subtest 'Unpacking in progress' => sub {
    my $buffer = '';
    {
      open my $handle, '>', \$buffer;
      local *STDOUT = $handle;
      $app->start('unpack', '2');
    }
    like $buffer, qr/Unpacking already in progress/, 'in progress';
    is $app->minion->jobs({tasks => ['unpack']})->total, 2, 'two unpack jobs';
  };

  my $worker = $app->minion->worker->register;
  my $job    = $worker->dequeue(0);
  $job->fail('Something went wrong');

  subtest 'Unlock failed prior attempt' => sub {
    is $app->minion->jobs({tasks => ['unpack']})->total, 2, 'two unpack jobs';
    $minion->lock('processing_pkg_2', 172800);
    my $buffer = '';
    {
      open my $handle, '>', \$buffer;
      local *STDOUT = $handle;
      $app->start('unpack', '2');
    }
    like $buffer, qr/Releasing locks for package 2/, 'package locks released';
    like $buffer, qr/Triggered unpack job/,          'unpack job triggered';
    is $app->minion->jobs({tasks => ['unpack']})->total, 3, 'three unpack jobs';
  };

  subtest 'Re-unpack clears indexed timestamp for progress bar' => sub {
    my $pkg = $app->packages->find(2);
    ok $pkg->{imported}, 'imported timestamp set';
    ok $pkg->{unpacked}, 'unpacked timestamp set';
    ok $pkg->{indexed},  'indexed timestamp set';

    my $worker = $minion->worker->register;
    my $job    = $worker->dequeue(0);
    is $job->task,    'unpack', 'right task';
    is $job->execute, undef,    'no error';
    $worker->unregister;

    $pkg = $app->packages->find(2);
    ok $pkg->{unpacked}, 'unpacked timestamp set again';
    is $pkg->{indexed}, undef, 'indexed timestamp cleared';
  };
};

subtest 'Paced re-unpack batches (--rebatch)' => sub {
  my $pkgs = $app->packages;

  my $add = sub ($tag) {
    my $hash = $tag . ('0' x (32 - length $tag));
    my $id   = $pkgs->add(
      name            => "rebatch-$tag",
      checkout_dir    => $hash,
      api_url         => 'https://api.opensuse.org',
      requesting_user => 1,
      project         => 'test',
      package         => "rebatch-$tag",
      srcmd5          => $hash,
      priority        => 5
    );
    $pkgs->imported($id);
    return $id;
  };

  # Three fresh packages; the middle one obsolete so it must be skipped.
  my $a = $add->('aaaa');
  my $b = $add->('bbbb');
  my $c = $add->('cccc');
  $app->pg->db->update('bot_packages', {obsolete => 1}, {id => $b});

  my $run = sub (@args) {
    my $buffer = '';
    open my $handle, '>', \$buffer;
    local *STDOUT = $handle;
    $app->start('unpack', @args);
    return $buffer;
  };

  subtest 'First batch skips the obsolete package and reports the next offset' => sub {
    my $out = $run->('--rebatch', $a - 1, '--batch', 2, '--priority', 3);
    like $out, qr/Enqueued 2 re-unpack job\(s\) at priority 3/, 'two jobs enqueued at the requested priority';
    like $out, qr/Next offset: $c/,                             'offset advances past the batch (obsolete skipped)';

    ok $minion->jobs({tasks => ['unpack'], notes => ["pkg_$a"]})->total, "unpack enqueued for $a";
    ok $minion->jobs({tasks => ['unpack'], notes => ["pkg_$c"]})->total, "unpack enqueued for $c";
    is $minion->jobs({tasks => ['unpack'], notes => ["pkg_$b"]})->total, 0, "obsolete $b was skipped";

    my $info = $minion->jobs({tasks => ['unpack'], notes => ["pkg_$a"]})->next;
    is $info->{priority}, 3, 'enqueued job carries the low priority';
  };

  subtest 'Resuming from the last offset reports caught up' => sub {
    my $out = $run->('--rebatch', $c);
    like $out, qr/Caught up/, 'nothing left after the newest package';
  };
};

done_testing();
