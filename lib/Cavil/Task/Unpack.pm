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

package Cavil::Task::Unpack;
use Mojo::Base 'Mojolicious::Plugin';

use Cavil::Checkout;

sub register {
  my ($self, $app) = @_;
  $app->minion->add_task(unpack => \&_unpack);
}

sub _unpack {
  my ($job, $id) = @_;

  my $app    = $job->app;
  my $minion = $app->minion;
  my $log    = $app->log;
  my $pkgs   = $app->packages;

  # Protect from race conditions
  return $job->finish("Package $id is already being processed")
    unless my $guard = $minion->guard("processing_pkg_$id", 172800);
  return $job->fail("Package $id is not imported yet") unless $pkgs->is_imported($id);

  # Unpack the package
  my $dir = $app->package_checkout_dir($id);
  Cavil::Checkout->new($dir)->unpack;
  $pkgs->unpacked($id);
  $log->info("[$id] Unpacked $dir");

  # Next step
  $pkgs->index($id, $job->info->{priority} + 1, [$job->id]);
}

1;
