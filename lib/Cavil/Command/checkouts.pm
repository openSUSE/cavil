# Copyright (C) 2025 SUSE Linux GmbH
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

package Cavil::Command::checkouts;
use Mojo::Base 'Mojolicious::Command', -signatures;

use Mojo::Util qw(getopt);
use Mojo::File qw(path);

has description => 'Checkout management';
has usage       => sub ($self) { $self->extract_usage };

sub run ($self, @args) {
  getopt \@args, 'check-abandoned' => \my $check_abandoned;

  my $root = path($self->app->config->{checkout_dir});

  # Check for abandoned checkouts
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
