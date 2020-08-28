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
use Mojo::Base 'Mojolicious::Plugin';

use Cavil::Licenses 'lic';
use Mojo::File 'path';
use Mojo::JSON 'to_json';
use Mojo::Util qw(decode md5_sum xml_escape);

sub register {
  my ($self, $app) = @_;

  $app->helper('chart_data'                  => \&_chart_data);
  $app->helper('checksum'                    => \&_checksum);
  $app->helper('current_user'                => \&_current_user);
  $app->helper('current_user_has_role'       => \&_current_user_has_role);
  $app->helper('current_package'             => \&_current_package);
  $app->helper('format_link'                 => \&_format_link);
  $app->helper('highlight_line'              => \&_highlight_line);
  $app->helper('lic'                         => sub { shift; lic(@_) });
  $app->helper('maybe_utf8'                  => sub { decode('UTF-8', $_[1]) // $_[1] });
  $app->helper('package_checkout_dir'        => \&_pkg_checkout_dir);
  $app->helper('reply.json_validation_error' => \&_json_validation_error);
  $app->helper('format_file'                 => \&_format_file);
}

sub _chart_data {
  my ($c, $hash) = @_;

  my @licenses;
  my @num_files;
  my @colours;

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

sub _checksum {
  my ($c, $specfile, $report) = @_;

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

sub _current_package { shift->stash('package') }

sub _current_user { shift->session('user') }

sub _current_user_has_role {
  my ($c, $role) = @_;
  return undef unless my $user = $c->helpers->current_user;
  return $c->users->has_role($user, $role);
}

sub _format_link {
  my ($c, $link) = @_;
  if ($link =~ /^obs#(.*)$/) {
    return $c->link_to($link => "https://build.opensuse.org/request/show/$1" => (target => '_blank'));
  }
  if ($link =~ /^ibs#(.*)$/) {
    return $c->link_to($link => "https://build.suse.de/request/show/$1" => (target => '_blank'));
  }
  return $link;
}

sub _highlight_line {
  my ($c, $line, $pattern) = @_;
  my $oline = $line;
  $line = xml_escape($line);
  $line =~ s,(\Q$pattern\E),<span class='lkw'>$1</span>,gi;
  return Mojo::ByteStream->new($line);
}

sub _json_validation_error {
  my $c = shift;

  my $failed = join ', ', @{$c->validation->failed};
  $c->render(json => {error => "Invalid request parameters ($failed)"}, status => 400);
}

sub _pkg_checkout_dir {
  my ($c, $id) = @_;
  my $app = $c->app;
  my $pkg = $app->packages->find($id);
  return path($app->config->{checkout_dir}, $pkg->{name}, $pkg->{checkout_dir});
}

1;
