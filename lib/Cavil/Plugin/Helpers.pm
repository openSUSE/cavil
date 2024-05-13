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

package Cavil::Plugin::Helpers;
use Mojo::Base 'Mojolicious::Plugin', -signatures;

use Cavil::Licenses 'lic';
use Mojo::File 'path';
use Mojo::JSON 'to_json';
use Mojo::Util qw(decode md5_sum xml_escape);

sub register ($self, $app, $config) {
  $app->helper('chart_data'                  => \&_chart_data);
  $app->helper('checksum'                    => \&_checksum);
  $app->helper('current_user'                => \&_current_user);
  $app->helper('current_user_has_role'       => \&_current_user_has_role);
  $app->helper('current_package'             => \&_current_package);
  $app->helper('lic'                         => sub { shift; lic(@_) });
  $app->helper('maybe_utf8'                  => sub { decode('UTF-8', $_[1]) // $_[1] });
  $app->helper('reply.json_validation_error' => \&_json_validation_error);
  $app->helper('format_file'                 => \&_format_file);
}

sub _chart_data ($c, $hash) {
  my (@licenses, @num_files, @colours);

  my @codes = ('#117864', '#85c1e9', '#9b59b6', '#ec7063', '#a3e4d7', '#c39bd3', '#c0392b');

  my @sorted_keys = sort { $hash->{$b} <=> $hash->{$a} } keys %$hash;
  while (@sorted_keys) {
    my $first = shift @sorted_keys;
    push(@licenses,  "$first: $hash->{$first} files");
    push(@num_files, $hash->{$first});
    push(@colours,   shift @codes);
    delete $hash->{$first};
    last unless @codes;
  }

  my $rest = 0;

  # TODO - we will count files multiple times
  for my $lic (@sorted_keys) {
    $rest += $hash->{$lic};
  }
  if ($rest) {
    push(@licenses,  "Misc: $rest files");
    push(@num_files, $rest);
    push(@colours,   'grey');
  }
  return {licenses => to_json(\@licenses), 'num-files' => to_json(\@num_files), colours => to_json(\@colours)};
}

sub _checksum ($c, $specfile, $report) {
  my $canon_license = lic($specfile->{main}{license})->canonicalize->to_string;
  $canon_license ||= "Unknown";
  my $text = "RPM-License $canon_license\n";

  for my $license (sort { $a cmp $b } keys %{$report->{licenses}}) {
    next if $report->{licenses}{$license}{risk} == 0;
    $text .= "LIC:$license";
    for my $flag (@{$report->{licenses}{$license}{flags}}) {
      $text .= ":$flag";
    }
    $text .= "\n";
  }

  return md5_sum $text;
}

sub _current_package ($c) { $c->stash('package') }

sub _current_user ($c) { $c->session('user') }

sub _current_user_has_role ($c, $role) {
  return undef unless my $user = $c->helpers->current_user;
  return $c->users->has_role($user, $role);
}

sub _json_validation_error ($c) {
  my $failed = join ', ', @{$c->validation->failed};
  $c->render(json => {error => "Invalid request parameters ($failed)"}, status => 400);
}

1;
