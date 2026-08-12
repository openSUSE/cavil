# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package Cavil::Command::checkouts;
use Mojo::Base 'Mojolicious::Command', -signatures;

use Mojo::Util qw(getopt);
use Mojo::File qw(path);

has description => 'Checkout management';
has usage       => sub ($self) { $self->extract_usage };

sub run ($self, @args) {
  getopt \@args, 'check-abandoned' => \my $check_abandoned;

  my $root = path($self->app->config->{checkout_dir});

  return $self->_check_abandoned($root) if $check_abandoned;

  my $count = $root->list({dir => 1})->size;
  say qq{Checkouts stored in "$root": $count};
}

sub _check_abandoned ($self, $root) {
  my $db = $self->app->pg->db;

  for my $dir ($root->list({dir => 1})->each) {
    my $name    = $dir->basename;
    my $results = $db->query('SELECT checkout_dir FROM bot_packages WHERE name = ? AND OBSOLETE = FALSE', $name);
    my $xpected = {map { $_->{checkout_dir} => 1 } $results->hashes->each};
    for my $checkout ($dir->list({dir => 1})->each) {
      my $checkout_dir = $checkout->basename;
      next if $xpected->{$checkout_dir};
      next if !!$db->query(
        'SELECT id FROM bot_packages
         WHERE name = ? AND checkout_dir = ? AND cleaned IS NULL', $name, $checkout_dir
      )->rows;
      say "$name/$checkout_dir";
    }
  }
}

1;

=encoding utf8

=head1 NAME

Cavil::Command::checkouts - Cavil command to manage checkouts

=head1 SYNOPSIS

  Usage: APPLICATION checkouts

    # Check for abandoned checkouts
    script/cavil checkouts --check-abandoned

  Options:
        --check-abandoned   Check for abandoned checkouts

=cut
