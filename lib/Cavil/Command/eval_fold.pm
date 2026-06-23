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

package Cavil::Command::eval_fold;
use Mojo::Base 'Mojolicious::Command', -signatures;

use Cavil::Util  qw(normalize_license_expr text_shingles weighted_containment);
use Getopt::Long qw(GetOptionsFromArray);

has description => 'Calibrate snippet fold-in thresholds against the pattern corpus';
has usage       => sub ($self) { $self->extract_usage };

# Held-out evaluation of the similarity scorer using the curated corpus as ground truth: split the
# patterns into a reference set (builds the signatures) and a disjoint probe set (stand-ins for
# snippets), then measure how often best_license_for recovers a probe's true license at each
# similarity threshold. Reports precision (correct among accepted) and recall (accepted overall)
# so a threshold can be chosen for the desired precision before enabling fold-in.
sub run ($self, @args) {
  my $folds       = 5;
  my $min_margin  = 0.15;
  my $k           = 3;
  my $distinctive = 4.0;
  my $min_dist    = 2;
  GetOptionsFromArray(
    \@args,
    'folds=i'           => \$folds,
    'min-margin=f'      => \$min_margin,
    'k=i'               => \$k,
    'distinctive=f'     => \$distinctive,
    'min-distinctive=i' => \$min_dist
  );
  say "Parameters: k=$k distinctive=$distinctive min_distinctive=$min_dist min_margin=$min_margin folds=$folds";

  my $app  = $self->app;
  my $rows = $app->pg->db->select('license_patterns', 'id,license,pattern')->hashes;

  # Reference set builds per-license signatures; probe set is held out (id %% folds == 0)
  my (%signatures, %representative, @probes);
  for my $row (@$rows) {
    my $license = $row->{license};
    next unless defined $license && length $license;
    if ($row->{id} % $folds == 0) { push @probes, $row; next }
    my $shingles = text_shingles($row->{pattern}, $k);
    $signatures{$license}{$_} = 1 for keys %$shingles;
    $representative{$license} //= $row->{id};
  }

  my %index;
  for my $license (keys %signatures) { $index{$_}{$license} = 1 for keys %{$signatures{$license}} }
  my $total = keys %signatures;
  my %idf;
  for my $shingle (keys %index) {
    my $df = keys %{$index{$shingle}};
    $idf{$shingle} = log(($total + 1) / ($df + 1)) + 1;
  }
  my $ctx = {
    signatures      => \%signatures,
    representative  => \%representative,
    index           => \%index,
    idf             => \%idf,
    k               => $k,
    distinctive_idf => $distinctive,
    min_distinctive => $min_dist
  };

  my $patterns = $app->patterns;
  my @buckets  = (0.80, 0.85, 0.90, 0.92, 0.95, 0.97, 0.99);
  my (%accepted, %correct);
  my $scored = 0;
  for my $probe (@probes) {

    # Only probe licenses the reference set can actually represent
    next unless $signatures{$probe->{license}};
    my $best = $patterns->best_license_for($probe->{pattern}, $ctx);
    $scored++;

    # Mirror the production gate: require the winner to beat the runner-up by the margin, and treat
    # a prediction as correct when it matches the true license up to SPDX normalisation (so e.g.
    # "GPL-2.0+" and "GPL-2.0-or-later" are the same answer, while v2-only stays distinct).
    next unless ($best->{match} - ($best->{second} // 0)) >= $min_margin;
    my $hit = defined $best->{license}
      && normalize_license_expr($best->{license}) eq normalize_license_expr($probe->{license});
    for my $threshold (@buckets) {
      next unless $best->{match} >= $threshold;
      $accepted{$threshold}++;
      $correct{$threshold}++ if $hit;
    }
  }

  say sprintf 'Probes scored: %d (of %d held out)', $scored, scalar @probes;
  say sprintf '%-10s %-10s %-12s %-10s', 'threshold', 'accepted', 'precision', 'recall';
  for my $threshold (@buckets) {
    my $acc = $accepted{$threshold} // 0;
    my $cor = $correct{$threshold}  // 0;
    say sprintf '%-10.2f %-10d %-12s %-10s', $threshold, $acc, ($acc ? sprintf('%.1f%%', 100 * $cor / $acc) : '-'),
      ($scored ? sprintf('%.1f%%', 100 * $acc / $scored) : '-');
  }
}

1;

=encoding utf8

=head1 NAME

Cavil::Command::eval_fold - Calibrate snippet fold-in thresholds

=head1 SYNOPSIS

  Usage: APPLICATION eval_fold [OPTIONS]

    script/cavil eval_fold
    script/cavil eval_fold --folds 10 --distinctive 4 --min-margin 0.15

  Options:
        --folds <n>            Hold out every n-th pattern as a probe (default: 5)
        --min-margin <f>       Minimum winner/runner-up score gap to accept (default: 0.15)
        --k <n>                Tokens per shingle (default: 3)
        --distinctive <f>      Required-phrase IDF floor for a shared shingle (default: 4.0)
        --min-distinctive <n>  Minimum number of distinctive shared shingles (default: 2)
    -h, --help                 Show this summary of available options

=cut
