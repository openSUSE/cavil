# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package Cavil::Command::matcher_diff;
use Mojo::Base 'Mojolicious::Command', -signatures;

use Mojo::File qw(path);
use Mojo::Util qw(getopt);

has description => 'Compare the "spooky" and "cavil" pattern matching engines on the same files';
has usage       => sub ($self) { $self->extract_usage };

sub run ($self, @args) {
  getopt \@args, 'package|p=i' => \my $package, 'quiet|q' => \my $quiet;
  my $app = $self->app;

  # matcher-diff needs both engines side by side, so it loads them directly rather than through the
  # configured switch.
  eval { require Spooky::Patterns::XS; 1 } or die "Spooky::Patterns::XS is not available: $@";
  eval { require Cavil::Matcher;       1 } or die "Cavil::Matcher is not available: $@";

  # Load every global pattern into both engines (parse_tokens is engine-independent, so parse once).
  my $spooky = Spooky::Patterns::XS::init_matcher();
  my $cavil  = Cavil::Matcher::init_matcher();
  my $rows   = $app->pg->db->select('license_patterns', ['id', 'pattern'], {packname => ''});
  my $loaded = 0;
  while (my $row = $rows->array) {
    my ($id, $pattern) = @$row;
    my $tokens = Spooky::Patterns::XS::parse_tokens($pattern);
    $spooky->add_pattern($id, $tokens);
    $cavil->add_pattern($id, $tokens);
    $loaded++;
  }
  say "Loaded $loaded global patterns into both engines";

  # Files to compare: an unpacked package checkout, or explicit paths.
  my @files;
  if ($package) {
    my $dir = $app->packages->pkg_checkout_dir($package)->child('.unpacked');
    die "Package $package has no unpacked checkout at $dir\n" unless -d $dir;
    @files = grep { -f $_ } @{$dir->list_tree->to_array};
  }
  else {
    @files = map { path($_) } @args;
  }
  die "Nothing to compare - give file paths or --package <id>\n" unless @files;

  my ($scanned, $diffs) = (0, 0);
  for my $file (@files) {
    $scanned++;
    my $a = $spooky->find_matches("$file");
    my $b = $cavil->find_matches("$file");
    next if _same($a, $b);
    $diffs++;
    say "DIFF $file";
    unless ($quiet) {
      say '  spooky: ' . _format($a);
      say '  cavil:  ' . _format($b);
    }
  }

  say $diffs == 0
    ? "OK - $scanned file(s) compared, engines agree on every match"
    : "MISMATCH - $diffs of $scanned file(s) differ between engines";
}

sub _format ($matches) {
  return '(none)' unless @$matches;
  return join ' ', map {"[$_->[0]:$_->[1]-$_->[2]]"} @$matches;
}

# Order-sensitive comparison: the engines are expected to return identical, identically-ordered matches.
sub _same ($a, $b) {
  return 0 unless @$a == @$b;
  for my $i (0 .. $#$a) {
    return 0 unless $a->[$i][0] == $b->[$i][0] && $a->[$i][1] == $b->[$i][1] && $a->[$i][2] == $b->[$i][2];
  }
  return 1;
}

1;

=encoding utf8

=head1 NAME

Cavil::Command::matcher_diff - Compare the two pattern matching engines

=head1 SYNOPSIS

  Usage: APPLICATION matcher-diff [OPTIONS] [FILE ...]

    script/cavil matcher-diff path/to/file.c another/file.h
    script/cavil matcher-diff --package 12345
    script/cavil matcher-diff --package 12345 --quiet

  Options:
    -p, --package <id>   Compare every file of a package's unpacked checkout
    -q, --quiet          Only list files that differ, without the matches
    -h, --help           Show this summary of available options

  Loads all global license patterns into both the "spooky" (Spooky::Patterns::XS) and "cavil"
  (Cavil::Matcher) engines and reports any file whose resolved matches differ. Read-only; it does not
  touch caches, the database, or reports. Both engines must be installed.

=cut
