# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package Cavil::Command::exclusions;
use Mojo::Base 'Mojolicious::Command', -signatures;

use Mojo::File qw(path);
use Mojo::Util qw(getopt);

has description => 'Import excluded files from an old cavil.exclude file';
has usage       => sub ($self) { $self->extract_usage };

sub run ($self, @args) {
  getopt \@args, 'import=s' => \my $file, 'user=s' => \my $login;
  die $self->usage unless $file && $login;

  my $app = $self->app;
  die qq{User "$login" does not exist\n} unless $app->pg->db->select('bot_users', 'id', {login => $login})->rows;

  my $exclusions = $app->unpack_exclusions;
  my ($reason, $added, $skipped) = ('', 0, 0);
  for my $line (split /\n/, path($file)->slurp('UTF-8')) {
    if    ($line =~ /^\s*#\s*(.*?)\s*$/) { $reason = $1 }
    elsif ($line =~ /^\s*(\S+?)\s*:\s*(\S+)/) {
      my $rule = {package_glob => $1, file => $2, reason => $reason};
      if    (my $error = $exclusions->invalid($rule)) { say "Skipped $rule->{package_glob}: $rule->{file} ($error)" }
      elsif ($exclusions->add($rule, $login))         { $added++ }
      else                                            { $skipped++ }
    }
  }
  say "Imported $added excluded files, skipped $skipped that already existed";
}

1;

=encoding utf8

=head1 NAME

Cavil::Command::exclusions - Cavil command to import excluded files

=head1 SYNOPSIS

  Usage: APPLICATION exclusions --import FILE --user LOGIN

    # Import an old cavil.exclude file, each "# comment" becomes the reason for the rules below it
    script/cavil exclusions --import /etc/cavil/cavil.exclude --user admin

  Options:
        --import <file>   Old "package-glob : filename" exclude file to import
        --user <login>    User the imported rules are recorded for

=head1 DESCRIPTION

Import excluded files from an old cavil.exclude file. Existing rules are skipped, so it is safe to run again.

=cut
