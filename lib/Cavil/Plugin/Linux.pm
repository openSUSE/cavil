# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package Cavil::Plugin::Linux;
use Mojo::Base 'Mojolicious::Plugin', -signatures;

use BSD::Resource;
use Mojo::File 'path';
use Mojo::IOLoop;

sub register ($self, $app, $config) {
  my $cfg = $app->config;

  # Make OOMKiller kill job processes before the worker (only decreasing the
  # value requires root), so the default for the worker process should be below
  # 200 (it is usually 0)
  $app->minion->on(
    worker => sub ($minion, $worker) {
      $worker->on(
        dequeue => sub ($worker, $job) {
          $job->on(start => sub { path('/proc', $$, 'oom_score_adj')->spew('200') });
        }
      );
    }
  );

  # Kill "analyze" jobs once they reach a certain size
  my $mem = $cfg->{max_task_memory};
  $app->hook(before_task_analyze     => sub { _task_limit($mem) });
  $app->hook(before_task_index_batch => sub { _task_limit($mem) });

  # Stop prefork workers gracefully once they reach a certain size
  my $parent = $$;
  Mojo::IOLoop->next_tick(
    sub {
      Mojo::IOLoop->recurring(
        5 => sub {
          my $rss = (getrusage())[2];
          my $max = $cfg->{max_worker_rss};
          return unless $rss > $max;
          $app->log->warn(qq{Worker exceeded RSS limit "$rss > $max", restarting});
          Mojo::IOLoop->stop_gracefully;
        }
      ) if $parent ne $$;
    }
  );
}

sub _task_limit ($mem) {
  setrlimit(get_rlimits()->{RLIMIT_VMEM}, $mem, -1) or die "Can't change rlimits: $!";
}

1;
