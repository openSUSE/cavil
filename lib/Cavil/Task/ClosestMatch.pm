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

package Cavil::Task::ClosestMatch;
use Mojo::Base 'Mojolicious::Plugin', -signatures;

use Cavil::PatternEngine;
use Mojo::File qw(path);

sub register ($self, $app, $config) {
  $app->minion->add_task(pattern_stats => \&_pattern_stats);
}

sub _pattern_stats ($job) {
  my $app = $job->app;
  my $db  = $app->pg->db;

  my $rows = $db->select('license_patterns', 'id,pattern')->hashes;

  my $bag = Cavil::PatternEngine::init_bag_of_patterns;
  my %patterns;
  $patterns{$_->{id}} = $_->{pattern} for $rows->each;
  $bag->set_patterns(\%patterns);

  # Publish under the active engine's bag filename (formats differ between engines)
  my $bagfile = $app->patterns->bag_cache_file;
  my $cache   = $bagfile->sibling($bagfile->basename . '.new.' . $job->id);
  $bag->dump($cache);
  rename($cache, $bagfile->to_string);

  # Rebuild the per-license similarity signatures (an extension of the bag) used for snippet scoring.
  # The snippets themselves are scored lazily in analyze (Patterns::score_package_snippets) and, for a
  # corpus-wide refresh after pattern changes, by "cavil snippets --rescore" - this task only publishes
  # the artifacts both of those read.
  $app->patterns->rebuild_similarity_data;
}

1;
