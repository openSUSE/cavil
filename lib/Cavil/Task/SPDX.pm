# Copyright (C) 2023 SUSE LLC
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

package Cavil::Task::SPDX;
use Mojo::Base 'Mojolicious::Plugin', -signatures;

use Cavil::Checkout;
use Mojo::Util qw(scope_guard);

sub register ($self, $app, $config) {
  $app->minion->add_task(spdx_report => \&_spdx_report);
}

sub _spdx_report ($job, $id) {
  my $app    = $job->app;
  my $minion = $app->minion;
  my $pkgs   = $app->packages;
  my $spdx   = $app->spdx;

  # Protect from race conditions
  my $spdx_guard = scope_guard sub { $minion->unlock("spdx_$id") };
  return $job->finish("Package $id is already being processed")
    unless my $pkg_guard = $minion->guard("processing_pkg_$id", 172800);
  return $job->fail("Package $id is not indexed yet") unless $pkgs->is_indexed($id);

  # Placeholder
  $pkgs->remove_spdx_report($id);
  my $path = $pkgs->spdx_report_path($id);
  $spdx->generate_to_file($id, $path);
}

1;
