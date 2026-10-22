# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Mojo::Base -strict, -signatures;

use FindBin;
use lib "$FindBin::Bin/lib";

use Test::More;
use Test::Mojo;
use Cavil::Test;
use Mojo::File qw(tempdir);
use Mojo::JSON qw(encode_json);

plan skip_all => 'set TEST_ONLINE to enable this test' unless $ENV{TEST_ONLINE};

my $cavil_test = Cavil::Test->new(online => $ENV{TEST_ONLINE}, schema => 'command_setup_test');
my $t          = Test::Mojo->new(Cavil => $cavil_test->default_config);
my $app        = $t->app;
my $migrations = $app->pg->migrations;
my $minion     = $app->minion;

my $tempdir = tempdir;
my $file    = $tempdir->child('license_patterns.jsonl');
$file->spew(join '', map { encode_json({license => "Setup-$_", pattern => "Setup fixture $_ terms"}) . "\n" } 1 .. 3);

# The progress bar and the unpacker restore the selected handle by name, which would keep pointing at the first buffer
my $output;
my $run = sub (@args) {
  my $selected = select;
  my $ok;
  $output = '';
  {
    open my $handle, '>', \$output;
    local *STDOUT = $handle;
    local *STDERR = $handle;
    $ok = eval { $app->start(@args); 1 };
  }
  select $selected;
  die $@ unless $ok;
  return $output;
};
my $setup     = sub (@args) { $run->('setup', '-p', $file, @args) };
my $schedules = sub {
  return {map { $_->{name} => $_ } @{$minion->list_schedules(0, 100)->{schedules}}};
};

subtest 'Doctor before setup' => sub {
  eval { $run->('doctor') };
  like $@, qr/Some checks found errors/, 'doctor fails';
  my $buffer = $output;
  like $buffer, qr/error\s+Database\s+Schema is outdated, run "script\/cavil setup"/, 'tells to run setup';
  like $buffer, qr/error\s+License patterns\s+Check failed/,                          'failed check reported';
  like $buffer, qr/Secrets\s+Custom secrets are set/,                                 'other checks still run';
};

subtest 'Fresh instance' => sub {
  is $migrations->active, 0, 'empty database';
  my $output = $setup->();
  like $output, qr/Updated database from version 0 to @{[$migrations->latest]}/,     'migrated';
  like $output, qr/Imported 3 license patterns/,                                     'patterns imported';
  like $output, qr/Scheduled "reindex_all" as "weekly_reindexing" \(0 20 \* \* 5\)/, 'reindexing scheduled';
  is $migrations->active, $migrations->latest,                                    'latest version is active';
  is $app->pg->db->query('SELECT COUNT(*) FROM license_patterns')->array->[0], 3, 'three patterns';
  is_deeply [sort keys %{$schedules->()}], [qw(daily_cleanup hourly_ephemeral_cleanup hourly_sweep weekly_reindexing)],
    'four schedules';
  is $schedules->()->{hourly_sweep}{task}, 'sweep_builds', 'right task';
};

subtest 'Nothing to do' => sub {
  my $output = $setup->();
  like $output, qr/Database is up to date/,               'no migration';
  like $output, qr/License patterns are up to date/,      'no patterns imported';
  like $output, qr/Maintenance schedules are up to date/, 'nothing scheduled';
  is $app->pg->db->query('SELECT COUNT(*) FROM license_patterns')->array->[0], 3, 'still three patterns';
};

subtest 'Disabled and removed schedules' => sub {
  $minion->pause_schedule('weekly_reindexing');
  $minion->unschedule('hourly_sweep');
  my $output = $setup->();
  like $output,   qr/Scheduled "sweep_builds" as "hourly_sweep"/, 'removed schedule is back';
  unlike $output, qr/weekly_reindexing/,                          'paused schedule left alone';
  ok $schedules->()->{weekly_reindexing}{paused}, 'still paused';
};

subtest 'Shipped patterns that are not part of the instance' => sub {
  $file->spew($file->slurp . encode_json({license => 'Setup-4', pattern => 'Setup fixture 4 terms'}) . "\n");
  like $setup->(), qr/1 shipped license patterns are not part of this instance/, 'reported';
  is $app->pg->db->query('SELECT COUNT(*) FROM license_patterns')->array->[0], 3, 'but not imported';
};

subtest 'Refuses to migrate while work is pending' => sub {
  my $jobs = $minion->jobs;
  while (my $info = $jobs->next) { $minion->job($info->{id})->remove }
  $migrations->migrate($migrations->latest - 1);
  my $before = $migrations->active;

  my $id = $minion->enqueue('obsolete');
  eval { $setup->() };
  like $@, qr/Refusing to update the database .* 0 workers are running and\s+1 jobs are queued/s, 'queued job';
  is $migrations->active, $before, 'not migrated';
  $minion->job($id)->remove;

  my $worker = $minion->worker->register;
  eval { $setup->() };
  like $@, qr/Refusing to update the database .* 1 workers are running and\s+0 jobs/s, 'running worker';
  is $migrations->active, $before, 'not migrated';
  $worker->unregister;

  like $setup->(), qr/Updated database from version $before to @{[$migrations->latest]}/, 'migrated once idle';
};

done_testing();
