# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package Cavil::Command::component;
use Mojo::Base 'Mojolicious::Command', -signatures;

use Mojo::Util qw(getopt);
use Mojo::JSON qw(encode_json);

has description => 'Export detected vendored components';
has usage       => sub ($self) { $self->extract_usage };

sub run ($self, @args) {
  getopt \@args, 'export' => \my $export;
  return print $self->usage unless $export;

  # One JSON object per line (JSON Lines): streamable and pipe-friendly for a large daily export. A
  # package shipped in one or more products emits its product name; one with no product mapping (e.g. a
  # fresh devel request) carries its external_link instead, with the other field left empty.
  $self->app->packages->export_components(
    sub ($row) {
      my $in_product = defined $row->{product} && length $row->{product};
      say encode_json(
        {
          product       => $in_product ? $row->{product} : '',
          external_link => $in_product ? ''              : ($row->{external_link} // ''),
          package       => $row->{package},
          source        => $row->{source},
          component     => $row->{component},
          version       => $row->{version} // ''
        }
      );
    }
  );
}

1;

=encoding utf8

=head1 NAME

Cavil::Command::component - Cavil component command

=head1 SYNOPSIS

  Usage: APPLICATION component [OPTIONS]

    script/cavil component --export
    script/cavil component --export > components.jsonl

  Options:
        --export   Stream every detected vendored component as JSON Lines (one object per line), with
                   its product (or external_link when the package is in no product), package name,
                   ecosystem (source), component name and version. Embargoed and obsolete packages are
                   excluded.
    -h, --help     Show this summary of available options

=cut
