# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package Cavil::Git;
use Mojo::Base -base, -signatures;

use Carp 'croak';
use Cavil::Util qw(run_cmd);
use Mojo::File  qw(path);
use Mojo::Util  qw(dumper);

use constant DEBUG => $ENV{CAVIL_GIT_DEBUG} || 0;

has config => sub { {} };

sub cmd ($self, $dir, $cmd) {
  my $result = run_cmd($dir, $cmd);

  warn dumper({cmd => $cmd, result => $result})                           if DEBUG;
  croak qq/Git command "@{[join(' ', @$cmd)]}" failed: $result->{stderr}/ if !$result->{status} || $result->{exit_code};
}

sub git_cmd ($self, $dir, $args) {
  my $config = $self->config;
  my $git    = $config->{bin} || 'git';

  # Prevent password prompts
  local $ENV{GIT_SSH_COMMAND} = 'ssh -oBatchMode=yes';

  my @cmd = ($git, @$args);
  return $self->cmd($dir, \@cmd);
}

sub download_source ($self, $url, $dir, $options = {}) {
  my $hash = $options->{hash} || 'main';

  my $config     = $self->config;
  my $extra_cmds = $config->{extra_commands} || [];

  # Clean up directory in case of failed previous checkouts
  $dir = path($dir)->remove_tree->make_path;

  $self->git_cmd($dir, ['init',     length($hash) == 64 ? '--object-format=sha256' : ()]);
  $self->git_cmd($dir, ['remote',   'add',     'r', $url]);
  $self->git_cmd($dir, ['fetch',    '--depth', '1', 'r', $hash]);
  $self->git_cmd($dir, ['checkout', $hash]);
  $self->cmd($dir, $_) for @$extra_cmds;

  chmod 0755, $dir;
  chmod 0644, $_ for $dir->list_tree->each;
  $dir->child('.git')->remove_tree;
}

1;
