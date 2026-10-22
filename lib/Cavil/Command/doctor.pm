# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package Cavil::Command::doctor;
use Mojo::Base 'Mojolicious::Command', -signatures;

use Mojo::Util qw(tablify);

has description => 'Check the instance for common problems';
has usage       => sub ($self) { $self->extract_usage };

sub run ($self, @args) {
  my $checks = $self->app->status->checks;
  print tablify [map { [@$_{qw(level name message)}] } @$checks];
  STDOUT->flush;
  die "Some checks found errors, see above\n" if grep { $_->{level} eq 'error' } @$checks;
}

1;

=encoding utf8

=head1 NAME

Cavil::Command::doctor - Cavil doctor command

=head1 SYNOPSIS

  Usage: APPLICATION doctor

    script/cavil doctor

  Runs the same checks as the Status section of the Settings page, and exits with a non-zero status if any of them
  found an error.

  Options:
    -h, --help   Show this summary of available options

=cut
