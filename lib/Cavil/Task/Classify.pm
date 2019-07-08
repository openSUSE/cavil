# Copyright (C) 2019 SUSE Linux GmbH
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

package Cavil::Task::Classify;
use Mojo::Base 'Mojolicious::Plugin';

use Cavil::Checkout;
use Mojo::File 'path';

sub register {
  my ($self, $app) = @_;
  $app->minion->add_task(classify => \&_classify);
}

sub _classify {
  my ($job, $id, $data) = @_;

  my $app        = $job->app;
  my $log        = $app->log;
  my $db         = $app->pg->db;
  my $classifier = $app->classifier;

  my $results = $db->select('snippets', ['id', 'text'], {classified => 0});
  while (my $next = $results->hash) {
    my $res = $classifier->classify($next->{text});
    if ($res->{license}) {
      say "$next->{id} license with confidence $res->{confidence}";
    }
    else {
      say "$next->{id} not a license with confidence $res->{confidence}";
    }
    $db->update(
      'snippets',
      {
        classified => 1,
        license    => $res->{license},
        confidence => int($res->{confidence} + 0.5)
      },
      {id => $next->{id}}
    );
  }
  $results->finish();
}

1;
