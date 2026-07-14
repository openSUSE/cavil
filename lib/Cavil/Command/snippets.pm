# Copyright (C) 2026 SUSE LLC
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

package Cavil::Command::snippets;
use Mojo::Base 'Mojolicious::Command', -signatures;

use Getopt::Long qw(GetOptionsFromArray);

has description => 'Snippet maintenance tasks';
has usage       => sub ($self) { $self->extract_usage };

sub run ($self, @args) {
  my $batch   = 5000;
  my $rescore = undef;    # start id when the option is given
  my $resolve = 0;
  GetOptionsFromArray(\@args, 'rescore:i' => \$rescore, 'resolve' => \$resolve, 'batch=i' => \$batch);

  return $self->_rescore($rescore, $batch) if defined $rescore;
  return $self->_resolve($batch)           if $resolve;

  say $self->usage;
}

# Re-score snippets (likelyness / like_pattern / second_match / score_version) with the current
# similarity model. Needed after deploying a scorer change, because existing snippets keep their old
# scores. Pure CPU (no classifier / LLM); iterates by id so it is safe to stop and resume.
sub _rescore ($self, $start, $batch) {
  my $app      = $self->app;
  my $db       = $app->pg->db;
  my $patterns = $app->patterns;
  my $ctx      = $patterns->similarity_context;
  die "No similarity signatures found - run 'cavil pattern_stats' first.\n" unless $ctx;

  my $last = $start;
  my $done = 0;
  while (1) {
    my $rows = $db->query('SELECT id, text FROM snippets WHERE id > ? ORDER BY id LIMIT ?', $last, $batch)->hashes;
    last unless $rows->size;

    for my $snippet ($rows->each) {
      $db->update('snippets', $patterns->score_text($snippet->{text}, $ctx), {id => $snippet->{id}});
      $last = $snippet->{id};
    }

    $done += $rows->size;
    say "Re-scored $done snippets (through id $last)";
  }
  say "Done.";
}

# Recompute the stored fold/clear/overlap/covered resolution (file_snippets.resolution) for every package.
# Kept separate from --rescore on purpose: it is expensive at production scale (tens of thousands of
# packages) and only needs running after a snippet_fold config or scorer change. Routine rescoring to
# track license-pattern edits does not require it. Iterates by package id, so it is safe to resume.
sub _resolve ($self, $batch) {
  my $app      = $self->app;
  my $db       = $app->pg->db;
  my $snippets = $app->snippets;

  my $last = 0;
  my $done = 0;
  while (1) {
    my $pkgs
      = $db->query('SELECT DISTINCT package FROM file_snippets WHERE package > ? ORDER BY package LIMIT ?', $last,
      $batch)->hashes;
    last unless $pkgs->size;

    for my $p ($pkgs->each) {
      $snippets->resolve_snippets($p->{package});
      $last = $p->{package};
    }
    $done += $pkgs->size;
    say "Re-resolved $done packages (through id $last)";
  }
  say "Done.";
}

1;

=encoding utf8

=head1 NAME

Cavil::Command::snippets - Snippet maintenance tasks

=head1 SYNOPSIS

  Usage: APPLICATION snippets [OPTIONS]

    # Re-score every snippet with the current similarity model
    script/cavil snippets --rescore
    # Resume a re-score after snippet id 120000, 2000 rows per batch
    script/cavil snippets --rescore 120000 --batch 2000
    # Recompute the stored fold/clear/overlap/covered resolution for every package
    script/cavil snippets --resolve

  Options:
        --rescore [id]   Re-score snippets, optionally resuming after the given id (default: 0)
        --resolve        Recompute every package's stored snippet resolution
                         (fold/clear/overlap/covered). Expensive; only needed after a snippet_fold
                         config or scorer change, not for routine pattern-edit rescoring.
        --batch <n>      Snippets per batch (default: 5000)
    -h, --help           Show this summary of available options

=cut
