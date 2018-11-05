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

  # Unpack the package
  my $app = $job->app;
  my $log = $app->log;
  my $dir = $app->package_checkout_dir($id);
  Cavil::Checkout->new($dir)->unpack;
  my $pkgs = $app->packages;
  $pkgs->unpacked($id);
  $log->info("[$id] Unpacked $dir");

  # Next step
  $pkgs->index($id, $job->info->{priority} + 1, [$job->id]);
}

1;
