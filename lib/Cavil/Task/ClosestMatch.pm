# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

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

  # Cache filenames track the active engine's format.
  my $bagfile = $app->patterns->bag_cache_file;
  my $cache   = $bagfile->sibling($bagfile->basename . '.new.' . $job->id);
  $bag->dump($cache);
  rename($cache, $bagfile->to_string);
}

1;
