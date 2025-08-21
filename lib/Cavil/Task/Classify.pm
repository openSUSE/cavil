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
use Mojo::Base 'Mojolicious::Plugin', -signatures;

use Cavil::Checkout;
use Mojo::File 'path';
use Mojo::Util qw(dumper);
use Spooky::Patterns::XS;

sub register ($self, $app, $config) {
  $app->minion->add_task(classify => \&_classify);
}

sub _classify ($job) {
  my $minion = $job->minion;

  # One classify job can handle all snippets
  return $job->finish('Classifier is already running')
    unless my $guard = $minion->guard('classify_in_progress', 172800);

  my $app        = $job->app;
  my $db         = $app->pg->db;
  my $classifier = $app->classifier;

  my $cache = $app->home->child('cache', 'cavil.pattern.bag');
  my $bag   = Spooky::Patterns::XS::init_bag_of_patterns;
  $bag->load($cache);

  # Classify in batches to allow for a complete re-evaluation with newer ML models
  my %packages_affected;
  while (1) {

    # Embargoed snippets should be reviewed by humans
    my $results = $db->query(
      'SELECT s.id, s.text FROM snippets s LEFT JOIN bot_packages bp ON (s.package = bp.id)
       WHERE classified = FALSE AND approved = FALSE AND (bp.embargoed = FALSE OR s.package IS NULL)
       ORDER BY s.id DESC LIMIT 100'
    );
    last unless $results->rows;

    for my $next ($results->hashes->each) {
      my $res = $classifier->classify($next->{text});
      die "Unexpected result from classifier: @{[dumper($res)]}"
        unless ref $res eq 'HASH' && defined($res->{license}) && defined($res->{confidence});

      my $best_pattern = $bag->best_for($next->{text}, 1);
      if   (@$best_pattern) { $best_pattern = $best_pattern->[0] }
      else                  { $best_pattern = {match => 0, pattern => undef} }

      $db->update(
        'snippets',
        {
          likelyness   => $best_pattern->{match},
          like_pattern => $best_pattern->{pattern},
          classified   => 1,
          license      => $res->{license},
          confidence   => int($res->{confidence} + 0.5)
        },
        {id => $next->{id}, approved => 0}
      );

      my $packages = $db->query('SELECT DISTINCT(package) FROM file_snippets WHERE snippet = ?', $next->{id});
      $packages_affected{$_->{package}} = 1 for $packages->hashes->each;
    }

  }

  my $pkgs = $app->packages;
  $pkgs->analyze($_) for keys %packages_affected;
}

1;
