# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package Cavil::Command::sync;
use Mojo::Base 'Mojolicious::Command', -signatures;

use Mojo::Util 'getopt';

has description => 'Export and update license patterns';
has usage       => sub ($self) { $self->extract_usage };

sub run ($self, @args) {
  getopt \@args,
    'e|export=s' => \my $export,
    'u|update=s' => \my $update;

  my $sync = $self->app->sync;
  return $sync->store($export) if $export;
  return unless $update;

  my $added = $sync->update($update);
  my %licenses;
  $licenses{$_->{license}}++ for @$added;
  say "$licenses{$_} x $_"   for sort keys %licenses;
  say 'Added ' . @$added . ' license patterns';
}

1;

=encoding utf8

=head1 NAME

Cavil::Command::sync - Cavil sync command

=head1 SYNOPSIS

  Usage: APPLICATION sync

    script/cavil sync -e lib/Cavil/resources/license_patterns.jsonl
    script/cavil sync -u lib/Cavil/resources/license_patterns.jsonl

  Updating adds only the patterns this instance has never seen, skipping patterns that were deliberately removed or
  edited, and lists what it added for review. Removals made before the audit log existed cannot be recognized. An
  empty instance is seeded with "script/cavil setup", which can also restore an export.

  Options:
    -e, --export <file>   Export license patterns to JSONL file
    -u, --update <file>   Import only license patterns this instance has never seen
    -h, --help            Show this summary of available options

=cut
