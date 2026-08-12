# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package Cavil::Command::sync;
use Mojo::Base 'Mojolicious::Command', -signatures;

use Mojo::Util 'getopt';

has description => 'Import and export license patterns';
has usage       => sub ($self) { $self->extract_usage };

sub run ($self, @args) {
  getopt \@args,
    'e|export=s' => \my $export,
    'i|import=s' => \my $import;

  my $sync = $self->app->sync;
  return $sync->store($export) if $export;
  return $sync->load($import)  if $import;
}

1;

=encoding utf8

=head1 NAME

Cavil::Command::sync - Cavil sync command

=head1 SYNOPSIS

  Usage: APPLICATION sync

    script/cavil sync -i lib/Cavil/resources/license_patterns.jsonl
    script/cavil sync -e lib/Cavil/resources/license_patterns.jsonl

  Options:
    -e, --export <file>   Export license patterns to JSONL file
    -i, --import <file>   Import license patterns from JSONL file
    -h, --help            Show this summary of available options

=cut
