# Copyright (C) 2018 SUSE Linux GmbH
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

package Cavil::Command::updatespooky;
use Mojo::Base 'Mojolicious::Command', -signatures;

has description => 'Update Spooky::Patterns::XS indeces';
has usage       => sub ($self) { $self->extract_usage };

sub run ($self, @args) {
  my $app = $self->app;
  my $db  = $app->pg->db;

  my %sums;

  # reset all
  my $tx = $db->begin;

  my $conflicts;

  # reset the hexsums to avoid the unique index to be deferrable
  $db->query('update license_patterns set token_hexsum=id');
  my $patterns = $db->query('select * from license_patterns order by id');
  while (my $row = $patterns->hash) {
    $row->{packname} ||= '';
    my $hex = $app->patterns->checksum($row->{pattern});
    if (defined $sums{$hex}) {
      print STDERR
        "http://legaldb.suse.de/licenses/edit_pattern/$row->{id} ($row->{license},$row->{packname}) and http://legaldb.suse.de/licenses/edit_pattern/$sums{$hex}->{id} ($sums{$hex}->{license},$sums{$hex}->{packname}) collide\n";

#system("xdg-open http://legaldb.suse.de/licenses/edit_pattern/$row->{id}");
#system("xdg-open http://legaldb.suse.de/licenses/edit_pattern/$sums{$hex}->{id}");
      $conflicts = 1;
      next;
    }
    $sums{$hex} = $row;
    $app->log->info("$row->{id} -> $hex");
    $db->update('license_patterns', {token_hexsum => $hex}, {id => $row->{id}});
  }
  exit(1) if $conflicts;
  $tx->commit;
}

1;

=encoding utf8

=head1 NAME

Cavil::Command::updatespooky - Cavil updatespooky command

=head1 SYNOPSIS

  Usage: APPLICATION updatespooky

    script/cavil updatespooky

  Options:
    -h, --help   Show this summary of available options

=cut
