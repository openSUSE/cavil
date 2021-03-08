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

package Cavil::Command::check;
use Mojo::Base 'Mojolicious::Command', -signatures;

use Spooky::Patterns::XS;
use Cavil::Checkout;
use Time::HiRes 'time';
use Mojo::Util 'md5_sum';
use Cavil::Licenses 'lic';
use Text::Diff;
use Data::Dumper;

has description => 'Show license changes from previous reviews';
has usage       => sub ($self) { $self->extract_usage };

sub run ($self, @args) {
  my $app = $self->app;
  my $db  = $app->pg->db;

  my $id   = $args[0];
  my $name = $db->select('bot_packages', 'name', {id => $id})->hash->{name};
  my $new  = _checksum($db, $app->reports, $id);

  #print "NEW\n$new\n";
  my $pkgs = $db->select('bot_packages', '*', {state => [qw(acceptable correct)], name => $name});
  while (my $row = $pkgs->hash) {
    print "Row $row->{state}: $row->{id}\n";
    my $old = _checksum($db, $app->reports, $row->{id});

    #print "$old\n";
    print Dumper(diff \$old, \$new);
  }
}

sub _checksum ($db, $reports, $id) {
  my $specfile = $reports->specfile_report($id);

  my $canon_license = lic($specfile->{main}{license})->canonicalize->to_string;
  $canon_license ||= "Unknown";
  my $text = "RPM-License $canon_license\n";

  my $matches = $db->query(
    'select distinct l.name, p.opinion, p.patent, p.trademark
     from pattern_matches m left join license_patterns p on m.pattern = p.id
       left join licenses l on p.license = l.id
     where package = ? and ignored = false
     order by name, p.patent, p.opinion, p.trademark', $id
  );

  while (my $row = $matches->hash) {
    $text .= "LID:$row->{name}";
    for my $flag (qw(patent trademark opinion)) {
      if ($row->{$flag}) {
        $text .= ":$flag";
      }
    }
    $text .= "\n";
  }

  return $text;
}

1;

=encoding utf8

=head1 NAME

Cavil::Command::cleanup - Cavil check command

=head1 SYNOPSIS

  Usage: APPLICATION check ID

    script/cavil check 110848

  Options:
    -h, --help   Show this summary of available options

=cut
