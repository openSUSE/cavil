# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package Cavil::Status;
use Mojo::Base -base, -signatures;

use Cavil::Checkout;
use Cavil::Classifier;
use IPC::Cmd qw(can_run);
use IPC::Run qw(run);
use Mojo::UserAgent;

has 'app';

our @SCHEDULES = (
  [weekly_reindexing        => '0 20 * * 5' => 'reindex_all'],
  [daily_cleanup            => '0 1 * * *'  => 'obsolete'],
  [hourly_sweep             => '25 * * * *' => 'sweep_builds'],
  [hourly_ephemeral_cleanup => '15 * * * *' => 'cleanup_ephemeral']
);

sub busy ($self) {
  my $minion = $self->app->minion;
  my $stats  = $minion->stats;
  my $workers
    = $self->app->pg->db->query(q{SELECT COUNT(*) FROM minion_workers WHERE notified > NOW() - ? * INTERVAL '1 second'},
    $minion->missing_after)->array->[0];
  return {jobs => $stats->{active_jobs} + $stats->{inactive_jobs}, workers => $workers};
}

sub checks ($self) {
  my $app    = $self->app;
  my $config = $app->config;
  my $db     = $app->pg->db;
  my @checks;
  my $check = sub ($name, $level, $message) { push @checks, {name => $name, level => $level, message => $message} };
  my $try   = sub ($name, $cb) {
    return if eval { $cb->(); 1 };
    $check->($name, 'error', 'Check failed: ' . (split /\n/, $@)[0]);
  };

  $try->(
    'Database' => sub {
      my ($active, $latest) = ($app->pg->migrations->active, $app->pg->migrations->latest);
      if    ($active == $latest) { $check->('Database', 'ok',    'Schema is up to date') }
      elsif ($active < $latest)  { $check->('Database', 'error', 'Schema is outdated, run "script/cavil setup"') }
      else { $check->('Database', 'error', "Schema version $active is newer than this version of Cavil ($latest)") }
    }
  );

  $try->(
    'License patterns' => sub {
      my $patterns = $db->query('SELECT COUNT(*) FROM license_patterns')->array->[0];
      return $check->('License patterns', 'error', 'No patterns loaded, run "script/cavil setup"') unless $patterns;
      my $unknown = $app->sync->pending($app->sync->shipped);
      $check->(
        'License patterns',
        'ok', "$patterns patterns" . ($unknown ? ", $unknown shipped patterns are not part of this instance" : '')
      );
    }
  );

  $try->(
    'Workers' => sub {
      my $busy = $self->busy;
      return $check->('Workers', 'error', 'No worker is running, packages will not be processed')
        unless $busy->{workers};
      my $failed  = $app->minion->stats->{failed_jobs};
      my $message = "$busy->{workers} running, $busy->{jobs} jobs queued or active";
      return $check->('Workers', 'ok', $message) unless $failed;
      $check->('Workers', 'warning', "$message, $failed failed jobs (see the Minion Dashboard)");
    }
  );

  $try->(
    'Maintenance' => sub {
      my @names     = map { $_->[0] } @SCHEDULES;
      my $found     = $app->minion->list_schedules(0, scalar @names, {names => \@names})->{schedules};
      my %schedules = map  { $_->{name} => $_ } @$found;
      my @missing   = grep { !$schedules{$_} } @names;
      my @paused    = grep { $schedules{$_} && $schedules{$_}{paused} } @names;
      if    (@missing) { $check->('Maintenance', 'warning', "Missing schedules: @missing, run \"script/cavil setup\"") }
      elsif (@paused)  { $check->('Maintenance', 'warning', "Paused schedules: @paused") }
      else             { $check->('Maintenance', 'ok',      'All maintenance tasks are scheduled') }
    }
  );

  $try->(
    'Classifier' => sub {
      my $classifier = $app->classifier;
      return $check->('Classifier', 'error',
        'Not configured, but required to resolve the scanner noise in real packages')
        unless my $url = $classifier->url;

      my $waiting = $db->query(
        'SELECT COUNT(*) FROM snippets s LEFT JOIN bot_packages bp ON (s.package = bp.id)
         WHERE NOT classified AND NOT approved AND (NOT bp.embargoed OR s.package IS NULL)'
      )->array->[0];
      my $backlog = $waiting ? ", $waiting snippets waiting for classification" : '';

      my $ua = Mojo::UserAgent->new(connect_timeout => 3, inactivity_timeout => 30);
      my $probe
        = Cavil::Classifier->new(type => $classifier->type, url => $url, token => $classifier->token, ua => $ua);
      my $res = eval { $probe->classify('SPDX-License-Identifier: MIT') };
      if (ref $res eq 'HASH' && defined $res->{license} && defined $res->{confidence}) {
        $check->('Classifier', 'ok', "Answering at $url$backlog");
      }
      elsif (my $err = $@) { $check->('Classifier', 'error', "Not answering at $url: " . (split /\n/, $err)[0]) }
      else {
        my $type = $classifier->type;
        $check->(
          'Classifier', 'error', qq{Unexpected answer from $url, check the token and that it is a "$type" classifier}
        );
      }
    }
  );

  $try->(
    'Unpack tools' => sub {
      my @tools = grep { !-x $_ } @{Cavil::Checkout::unpack_tools()};
      if (my $git = $config->{git}) {
        push @tools, grep { !can_run($_) } $git->{bin} || 'git', map { $_->[0] } @{$git->{extra_commands} // []};
      }
      if   (@tools) { $check->('Unpack tools', 'warning', "Missing: @tools") }
      else          { $check->('Unpack tools', 'ok',      'All tools are installed') }
    }
  );

  $try->(
    'Storage' => sub {
      for my $writable (grep {defined} @$config{qw(checkout_dir tmp_dir cache_dir)}) {
        return $check->('Storage', 'error', "$writable is not a writable directory") unless -d $writable && -w _;
      }
      my $dir = $config->{checkout_dir};
      run ['df', '-Pk', $dir], \undef, \my $out, \my $err;
      my (undef, $size, undef, $free, $used) = split /\s+/, (split /\n/, $out // '')[-1] // '';
      return $check->('Storage', 'ok', "$dir is writable") unless defined $used && $used =~ /^(\d+)%$/;
      my $message = sprintf '%.1f GiB free in %s (%s used)', $free / 1024**2, $dir, $used;
      $check->('Storage', $1 >= 100 ? 'error' : $1 >= 90 ? 'warning' : 'ok', $message);
    }
  );

  my $secrets = $config->{secrets} // [];
  if (!@$secrets || grep { $_ eq 'this_is_not_secure' } @$secrets) {
    $check->('Secrets', 'error', 'Session cookies are signed with the shipped default, set "secrets"');
  }
  else { $check->('Secrets', 'ok', 'Custom secrets are set') }

  $try->(
    'SBOM' => sub {
      my $namespace = $config->{spdx}{namespace} // '';
      if (!$namespace || $namespace =~ /example\.com/) {
        $check->('SBOM', 'warning', 'Set "spdx.namespace" to the address of this instance to generate SBOMs');
      }
      elsif (!$app->settings->value('sbom_creator_name')) {
        $check->('SBOM', 'warning', 'Enter the name of your organisation in the SBOM settings');
      }
      else { $check->('SBOM', 'ok', "Identifiers start with $namespace") }
    }
  );

  if ($config->{openid}) { $check->('Login', 'ok', 'OpenID Connect') }
  else {
    $check->(
      'Login',
      $app->mode eq 'production' ? 'error' : 'warning',
      'No OpenID Connect configured, everyone who logs in is an admin'
    );
  }

  return \@checks;
}


1;
