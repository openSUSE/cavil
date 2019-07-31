# Copyright (C) 2018 SUSE Linux GmbH
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

package Cavil::Task::Import;
use Mojo::Base 'Mojolicious::Plugin';

use Cavil::Checkout;
use Mojo::File 'path';

sub register {
  my ($self, $app) = @_;
  $app->minion->add_task(obs_import => \&_obs);
  $app->minion->add_task(reimport   => \&_reimport);
}

sub _reimport {
  my ($job, $id) = @_;

  my $app = $job->app;
  my $log = $app->log;

  $app->packages->cleanup($id);
  $app->pg->db->update('bot_packages', {indexed => undef}, {id => $id});
  $app->pg->db->delete('bot_reports', {package => $id});
  $app->packages->reimport($id);
}

sub _obs {
  my ($job, $id, $data) = @_;

  my $app          = $job->app;
  my $log          = $app->log;
  my $pkgs         = $app->packages;
  my $checkout_dir = $app->config->{checkout_dir};
  my ($srcpkg, $verifymd5, $api, $project, $pkg, $srcmd5, $priority)
    = @{$data}{qw(srcpkg verifymd5 api project pkg srcmd5 priority)};
  die "Missing args" unless $srcpkg && $verifymd5;
  my $dir = path($checkout_dir, $srcpkg, $verifymd5);

  my $obs = $app->obs;
  eval { $obs->download_source($api, $project, $pkg, $dir, {rev => $srcmd5}) };
  if ($@) {
    $dir->remove_tree;
    die $@;
  }
  chmod 0755, $dir;
  chmod 0644, $_ for $dir->list->each;
  $pkgs->imported($id);
  $log->info("[$id] Imported $dir");

  # Next step
  $pkgs->unpack($id, $priority, [$job->id]);
}

1;
