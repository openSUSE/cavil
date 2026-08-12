# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package Cavil::Command::eval_fold;
use Mojo::Base 'Mojolicious::Command', -signatures;

use Cavil::Util  qw(normalize_license_expr text_shingle_ids);
use Getopt::Long qw(GetOptionsFromArray);

has description => 'Calibrate snippet fold-in thresholds against the pattern corpus';
has usage       => sub ($self) { $self->extract_usage };

# Calibrate fold thresholds by held-out evaluation against the curated corpus.
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

  # Use production shingle IDs so evaluation exercises the same scorer context.
  my (%signatures, %min_pid, @probes);
  for my $row (@$rows) {
    my $license = $row->{license};
    next unless defined $license && length $license;
    if ($row->{id} % $folds == 0) { push @probes, $row; next }
    my $shingles = text_shingle_ids($row->{pattern}, $k);
    $signatures{$license}{$_} = 1 for keys %$shingles;
    $min_pid{$license} = $row->{id} if !defined $min_pid{$license} || $row->{id} < $min_pid{$license};
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
    min_pid         => \%min_pid,
    index           => \%index,
    idf             => \%idf,
    distinctive_idf => $distinctive,
    min_distinctive => $min_dist
  };

  my $patterns = $app->patterns;
  my @buckets  = (0.80, 0.85, 0.90, 0.92, 0.95, 0.97, 0.99);
  my (%accepted, %correct);
  my $scored = 0;
  for my $probe (@probes) {

    next unless $signatures{$probe->{license}};
    my $best = $patterns->best_license([keys %{text_shingle_ids($probe->{pattern}, $k)}], $ctx);
    $scored++;

    # Normalize equivalent SPDX spellings when evaluating the production margin gate.
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
