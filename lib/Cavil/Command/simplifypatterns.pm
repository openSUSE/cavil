# Copyright (C) 2019 SUSE Linux GmbH
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

package Cavil::Command::simplifypatterns;
use Mojo::Base 'Mojolicious::Command', -signatures;

use Spooky::Patterns::XS;
use Text::Diff;
use Term::ReadKey;

has description => 'Checks and simplifies the pattern texts';
has usage       => sub ($self) { $self->extract_usage };

sub _normalize_pattern ($text) {
  my $spooky = Spooky::Patterns::XS::normalize($text);
  my $prev_line;
  $text = '';
  for my $row (@$spooky) {
    my ($line, $word, $token) = @$row;
    if (!$prev_line) {

    }
    elsif ($prev_line == $line) {
      $text .= " ";
    }
    else {
      for (my $i = $prev_line; $i < $line; $i++) {
        $text .= "\n";
      }

    }
    $prev_line = $line;
    $text .= $word;

  }
  return $text;
}

sub _strip_beginning ($text) {
  $text =~ s/^\s+//;
  $text =~ s/^copyright \$skip\d+\s+//;
  $text =~ s/^c\s+//;
  $text =~ s/^copyright c \$skip\d+\s+//;
  $text =~ s/^(this|the) (software|project|file|library|program|script|code|class)\s+//;
  $text =~ s/^(this|the) \$skip\d+\s+//;
  $text =~ s/^is\s+//;
  $text =~ s/^may be\s+//;
  $text =~ s/^can be\s+//;
  $text =~ s/^this is\s+//;
  $text =~ s/^\$skip\d+\s+//;
  $text =~ s/^< - -\+//;
  $text =~ s/^< para\s+//;
  $text =~ s/^[.="-]\s+//;
  $text =~ s/^\/\/\s+//;
  $text =~ s/^\/\/\/\s+//;
  $text =~ s/^rem //;
  return $text;
}

sub _remove_start ($text) {
  my $normalized_text = _normalize_pattern($text);
  my $new_text        = $normalized_text;
  do {
    $normalized_text = $new_text;
    $new_text        = _strip_beginning($normalized_text);
  } while ($new_text ne $normalized_text);

# first strip all until we match
  my $new_pattern = $text;
  while ($normalized_text ne _normalize_pattern($new_pattern)) {
    $new_pattern = substr($new_pattern, 1);
  }

# now try to remove even more (possibly eaten by tokenizer)
  while (1) {
    my $new_text = _normalize_pattern(substr($new_pattern, 1));
    last if $new_text ne $normalized_text;
    $new_pattern = substr($new_pattern, 1);
  }
  return $new_pattern;
}

sub _strip_ending ($text) {
  $text =~ s/[.=-]$//;
  $text =~ s/\s+$//;
  $text =~ s/\$skip\d+$//;
  $text =~ s/foundation inc$/foundation/;
  $text =~ s/675\smass\save\scambridge\sma\s02139\susa$//;
  $text =~ s/59\stemple\splace\ssuite\s330\sboston\sma\s02111\s-\s1307\susa$//;
  $text =~ s/59\stemple\splace\s-\ssuite\s330\sboston\sma\s02111\s-\s1307\susa$//;
  $text =~ s/51\sfranklin\sstreet\sfifth\sfloor\sboston\sma\s02110\s-\s1301\susa$//;
  $text =~ s/51 franklin st fifth floor boston ma 02110 - 1301 usa$//;
  $text =~ s/59 temple place - suite 330\sboston ma 02111 - 1307 usa$//;
  $text =~ s/51 franklin street\sboston ma 02110 - 1301 usa$//;
  $text =~ s/51 franklin st - fifth floor boston ma 02110 - 1301 usa$//;
  $text =~ s/444 castro street suite 900 mountain view california 94041 usa$//;
  return $text;
}

sub _remove_end ($text) {
  my $normalized_text = _normalize_pattern($text);
  my $new_text        = $normalized_text;
  do {
    $normalized_text = $new_text;
    $new_text        = _strip_ending($normalized_text);
  } while ($new_text ne $normalized_text);

  # first strip all until we match
  my $new_pattern = $text;
  while ($normalized_text ne _normalize_pattern($new_pattern)) {
    $new_pattern = substr($new_pattern, 0, length($new_pattern) - 1);
  }

  # now try to remove even more (possibly eaten by tokenizer)
  while (1) {
    my $new_text = _normalize_pattern(substr($new_pattern, 0, length($new_pattern) - 1));
    last if $new_text ne $normalized_text;
    $new_pattern = substr($new_pattern, 0, length($new_pattern) - 1);
  }

  return $new_pattern;

}

sub _find_matching_packages ($db, $pid, $touched) {
  my $package = $db->query('select distinct package from pattern_matches where pattern = ?', $pid);
  for my $row ($package->hashes->each) {
    $touched->{$row->{package}} = 1;
  }
}

sub run ($self, @args) {
  my $app = $self->app;

  my %touched;

  ReadMode 4;
  Spooky::Patterns::XS::init_matcher;
  my $db = $app->pg->db;
  for my $pattern ($db->select('license_patterns', '*', {}, {order_by => 'id'})->hashes->each) {
    my $new_pattern = _remove_start($pattern->{pattern});
    $new_pattern = _remove_end($new_pattern);
    my $t1 = $pattern->{pattern} . "\n";
    my $t2 = $new_pattern . "\n";
    next if $t1 eq $t2;
    say "Simplifying pattern $pattern->{id}";
    say diff \$t1, \$t2;

    $pattern->{pattern} = $new_pattern;
    my $result = $app->patterns->update($pattern->{id}, %$pattern);
    if ($result->{conflict}) {
      my $cattern = $app->patterns->find($result->{conflict});
      say "After simplification there are is now a conflict";

      $pattern->{packname} = "''" unless $pattern->{packname};
      $cattern->{packname} = "''" unless $cattern->{packname};
      say
        "Pattern 1: #$cattern->{id} ($cattern->{license} package: $cattern->{packname} risk: $cattern->{risk} trademark: $cattern->{trademark})";
      say
        "Pattern 2: #$pattern->{id} ($pattern->{license} package: $pattern->{packname} risk: $pattern->{risk} trademark: $pattern->{trademark})";
      my $t1 = $pattern->{pattern} . "\n";
      my $t2 = $cattern->{pattern} . "\n";

      my $todelete;
      my $diff = ($cattern->{license} ne $pattern->{license} || $cattern->{packname} ne $pattern->{packname});
      for my $key (qw(risk trademark)) {
        $diff = 1 if $cattern->{$key} != $pattern->{$key};
      }
      if ($t1 ne $t2) {
        say "Diff between the texts:";
        say diff \$t1, \$t2;
        $diff = 1;
      }
      else {
        say "No diff between the texts";
      }
      if ($diff) {
        say "";
        say "Which one to pick? Press 1/2/c!";
        my $buf = ReadKey 0;
        if ($buf eq '1') {
          $todelete = $pattern->{id};
        }
        elsif ($buf eq '2') {
          $todelete = $cattern->{id};
        }
        else {
          say "Bye!";
          last;
        }
      }
      else {
        $todelete = $pattern->{id};
      }
      _find_matching_packages($db, $todelete, \%touched);
      $app->patterns->remove($todelete);
    }
    else {
      _find_matching_packages($db, $pattern->{id}, \%touched);
    }
  }
  ReadMode 0;
  say "Marking affected packages...";

  my $minion = $app->minion;
  for my $id (keys %touched) {
    my $pkg  = $app->packages->find($id);
    my $prio = $pkg->{priority};
    $prio = 1 if $pkg->{state} ne 'new';
    $app->packages->reindex($pkg->{id}, $prio);
  }
  $app->patterns->expire_cache;
  $app->minion->enqueue(pattern_stats => [] => {priority => 9});
}

1;

=encoding utf8

=head1 NAME

Cavil::Command::simplifypatterns - Cavil classify command

=head1 SYNOPSIS

  Usage: APPLICATION simplifypatterns

    script/cavil simplifypatterns

  Options:
    -h, --help   Show this summary of available options

=cut
