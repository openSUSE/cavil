# SPDX-FileCopyrightText: 2026 SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Mojo::Base -strict, -signatures;

use Test::More;
use Cavil::Model::Patterns;
use Cavil::Util qw(text_shingle_ids);

# best_license is pure w.r.t. $self (no DB needed); build a synthetic two-license context by hand the
# same way score_snippets derives its index + IDF from the working-set slice. Shingles are the same
# 60-bit ids the DB scorer stores, so this exercises the exact production scorer.
my $patterns = Cavil::Model::Patterns->new;

my $mit = 'Permission is hereby granted, free of charge, to any person obtaining a copy of this '
  . 'software and associated documentation files to deal in the Software without restriction';
my $bsd = 'Redistribution and use in source and binary forms, with or without modification, are '
  . 'permitted provided that the following conditions are met';

my %signatures;
$signatures{MIT}{$_}            = 1 for keys %{text_shingle_ids($mit)};
$signatures{'BSD-3-Clause'}{$_} = 1 for keys %{text_shingle_ids($bsd)};

my %index;
for my $license (keys %signatures) { $index{$_}{$license} = 1 for keys %{$signatures{$license}} }
my $total = keys %signatures;
my %idf;
for my $shingle (keys %index) {
  my $df = keys %{$index{$shingle}};
  $idf{$shingle} = log(($total + 1) / ($df + 1)) + 1;
}

# distinctive_idf 0 / min_distinctive 1 keeps the required-phrase gate out of the way for the basic
# scoring tests (this 2-license fixture has only low IDF values); a dedicated subtest exercises the gate.
my $ctx = {
  signatures      => \%signatures,
  min_pid         => {MIT => 1, 'BSD-3-Clause' => 2},
  index           => \%index,
  idf             => \%idf,
  distinctive_idf => 0,
  min_distinctive => 1
};

my $ids = sub ($text) { [keys %{text_shingle_ids($text)}] };

subtest 'matches the right license' => sub {
  my $r
    = $patterns->best_license($ids->('Permission is hereby granted, free of charge, to any person obtaining'), $ctx);
  is $r->{license}, 'MIT', 'snippet identified as MIT';
  ok $r->{match} > 0.5,          'high containment for a real fragment';
  ok $r->{match} > $r->{second}, 'winner beats runner-up (margin)';

  my $b = $patterns->best_license($ids->('Redistribution and use in source and binary forms, with or without'), $ctx);
  is $b->{license}, 'BSD-3-Clause', 'snippet identified as BSD';
};

subtest 'unrelated text scores low' => sub {
  my $r = $patterns->best_license($ids->('the quick brown fox jumps over the lazy dog'), $ctx);
  ok $r->{match} < 0.3, 'no real license match';
};

subtest 'required-phrase gate rejects boilerplate-only matches' => sub {

  # With an impossibly high distinctiveness floor no shingle qualifies, so even a perfect-looking
  # containment match is dropped to no-confidence (the safe direction).
  my $strict = {%$ctx, distinctive_idf => 99};
  my $r
    = $patterns->best_license($ids->('Permission is hereby granted, free of charge, to any person obtaining'), $strict);
  is $r->{license}, undef, 'no confident match without a distinctive shared shingle';
  is $r->{match},   0,     'match downgraded to zero';

  # Requiring an impossible number of distinctive shingles also drops an otherwise-good match
  # (this is the gate that kills tiny one-token header fragments on real data).
  my $few = {%$ctx, min_distinctive => 99};
  my $g
    = $patterns->best_license($ids->('Permission is hereby granted, free of charge, to any person obtaining'), $few);
  is $g->{license}, undef, 'too few distinctive shingles -> no fold';
};

subtest 'empty / tiny text is safe' => sub {
  my $r = $patterns->best_license($ids->(''), $ctx);
  is $r->{match},   0,     'empty text scores 0';
  is $r->{license}, undef, 'no license';
};

done_testing;
