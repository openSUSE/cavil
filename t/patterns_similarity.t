# Copyright (C) 2026 SUSE LLC
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

use Mojo::Base -strict;

use Test::More;
use Cavil::Model::Patterns;
use Cavil::Util qw(text_shingles);

# Scorer is pure w.r.t. $self (no DB needed); build a synthetic two-license context by hand the
# same way similarity_context() derives its index + IDF from signatures.
my $patterns = Cavil::Model::Patterns->new;

my $mit = 'Permission is hereby granted, free of charge, to any person obtaining a copy of this '
  . 'software and associated documentation files to deal in the Software without restriction';
my $bsd = 'Redistribution and use in source and binary forms, with or without modification, are '
  . 'permitted provided that the following conditions are met';

my %signatures;
$signatures{MIT}{$_}            = 1 for keys %{text_shingles($mit)};
$signatures{'BSD-3-Clause'}{$_} = 1 for keys %{text_shingles($bsd)};

my %index;
for my $license (keys %signatures) { $index{$_}{$license} = 1 for keys %{$signatures{$license}} }
my $total = keys %signatures;
my %idf;
for my $shingle (keys %index) {
  my $df = keys %{$index{$shingle}};
  $idf{$shingle} = log(($total + 1) / ($df + 1)) + 1;
}

# distinctive_idf 0 keeps the required-phrase gate out of the way for the basic scoring tests (this
# 2-license fixture has only low IDF values); a dedicated subtest exercises the gate below.
my $ctx = {
  signatures      => \%signatures,
  representative  => {MIT => 1, 'BSD-3-Clause' => 2},
  index           => \%index,
  idf             => \%idf,
  distinctive_idf => 0
};

subtest 'matches the right license' => sub {
  my $r = $patterns->best_license_for('Permission is hereby granted, free of charge, to any person obtaining', $ctx);
  is $r->{license}, 'MIT', 'snippet identified as MIT';
  is $r->{pattern}, 1,     'returns representative pattern id';
  ok $r->{match} > 0.5,          'high containment for a real fragment';
  ok $r->{match} > $r->{second}, 'winner beats runner-up (margin)';

  my $b = $patterns->best_license_for('Redistribution and use in source and binary forms, with or without', $ctx);
  is $b->{license}, 'BSD-3-Clause', 'snippet identified as BSD';
};

subtest 'unrelated text scores low' => sub {
  my $r = $patterns->best_license_for('the quick brown fox jumps over the lazy dog', $ctx);
  ok $r->{match} < 0.3, 'no real license match';
};

subtest 'required-phrase gate rejects boilerplate-only matches' => sub {

  # With an impossibly high distinctiveness floor no shingle qualifies, so even a perfect-looking
  # containment match is dropped to no-confidence (the safe direction).
  my $strict = {%$ctx, distinctive_idf => 99};
  my $r = $patterns->best_license_for('Permission is hereby granted, free of charge, to any person obtaining', $strict);
  is $r->{license}, undef, 'no confident match without a distinctive shared shingle';
  is $r->{match},   0,     'match downgraded to zero';

  # Requiring an impossible number of distinctive shingles also drops an otherwise-good match
  # (this is the gate that kills tiny one-token header fragments on real data).
  my $few = {%$ctx, min_distinctive => 99};
  my $g   = $patterns->best_license_for('Permission is hereby granted, free of charge, to any person obtaining', $few);
  is $g->{license}, undef, 'too few distinctive shingles -> no fold';
};

subtest 'empty / tiny text is safe' => sub {
  my $r = $patterns->best_license_for('', $ctx);
  is $r->{match},   0,     'empty text scores 0';
  is $r->{license}, undef, 'no license';
};

done_testing;
