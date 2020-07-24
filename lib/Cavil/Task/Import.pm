# Copyright (C) 2018-2020 SUSE LLC
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
}

sub _obs {
  my ($job, $id, $data) = @_;

  my $app    = $job->app;
  my $minion = $app->minion;
  my $log    = $app->log;
  my $pkgs   = $app->packages;

  # Protect from race conditions
  return $job->finish("Package $id is already being processed")
    unless my $guard = $minion->guard("processing_pkg_$id", 172800);

  my $checkout_dir = $app->config->{checkout_dir};
  my ($srcpkg, $verifymd5, $api, $project, $pkg, $srcmd5, $priority)
    = @{$data}{qw(srcpkg verifymd5 api project pkg srcmd5 priority)};
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
  $pkgs->unpack($id, 8, [$job->id]);
}

1;
