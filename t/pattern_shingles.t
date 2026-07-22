# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Mojo::Base -strict, -signatures;

use FindBin;
use lib "$FindBin::Bin/lib";

use Test::More;
use Test::Mojo;
use Cavil::Test;
use Cavil::Util qw(text_shingle_ids);

plan skip_all => 'set TEST_ONLINE to enable this test' unless $ENV{TEST_ONLINE};

my $cavil_test = Cavil::Test->new(online => $ENV{TEST_ONLINE}, schema => 'pattern_shingles_test');
my $config     = $cavil_test->default_config;
my $t          = Test::Mojo->new(Cavil => $config);
$cavil_test->mojo_fixtures($t->app);

my $app      = $t->app;
my $db       = $app->pg->db;
my $patterns = $app->patterns;

sub shingle_count ($id) {
  $db->query('SELECT COUNT(*) AS c FROM pattern_shingles WHERE pattern_id = ?', $id)->hash->{c};
}

sub sl_count ($license) {
  $db->query('SELECT COUNT(*) AS c FROM shingle_license WHERE license = ?', $license)->hash->{c};
}

my $mit = 'Permission is hereby granted, free of charge, to any person obtaining a copy of this software';
my $bsd = 'Redistribution and use in source and binary forms are permitted provided these conditions are met';

subtest 'create populates the pattern shingles incrementally' => sub {
  my $p = $patterns->create(pattern => $mit, license => 'MIT-Shingle-Test', risk => 5);
  ok $p->{id}, 'pattern created';
  my $expect = scalar keys %{text_shingle_ids($mit)};
  ok $expect > 0, "text has shingles ($expect)";
  is shingle_count($p->{id}), $expect, 'exactly the pattern shingles are stored';
};

subtest 'update regenerates the shingles for the new text' => sub {
  my $id = $db->query("SELECT id FROM license_patterns WHERE license = 'MIT-Shingle-Test'")->hash->{id};
  $patterns->update($id, pattern => $bsd, license => 'MIT-Shingle-Test', risk => 5);
  is shingle_count($id), scalar keys %{text_shingle_ids($bsd)}, 'shingles match the updated text, not the old';
};

subtest 'delete removes the shingles via ON DELETE CASCADE' => sub {
  my $id = $db->query("SELECT id FROM license_patterns WHERE license = 'MIT-Shingle-Test'")->hash->{id};
  ok shingle_count($id) > 0, 'has shingles before delete';
  $db->query('DELETE FROM license_patterns WHERE id = ?', $id);
  is shingle_count($id), 0, 'shingles gone after the pattern is deleted';
};

# shingle_license is the license-level inverted index, kept in sync by triggers on pattern_shingles - it
# is what df / candidate gathering / containment read, so its maintenance matters as much as the base table.
subtest 'shingle_license mirrors pattern_shingles via triggers' => sub {
  my $p = $patterns->create(pattern => $mit, license => 'SL-Trigger-Test', risk => 5);
  ok sl_count('SL-Trigger-Test') > 0, 'insert trigger populated the license-level index';
  is sl_count('SL-Trigger-Test'), shingle_count($p->{id}),
    'one row per distinct shingle of the (single-pattern) license';

  $db->query('DELETE FROM license_patterns WHERE id = ?', $p->{id});
  is sl_count('SL-Trigger-Test'), 0, 'cascade delete trigger cleaned up the license-level index';
};

subtest 'backfill repopulates both tables from all patterns' => sub {
  $db->query('DELETE FROM pattern_shingles');
  is $db->query('SELECT COUNT(*) AS c FROM pattern_shingles')->hash->{c}, 0, 'base table emptied';
  is $db->query('SELECT COUNT(*) AS c FROM shingle_license')->hash->{c},  0, 'license index emptied (via triggers)';

  $patterns->backfill_pattern_shingles;
  my $rows     = $db->query('SELECT COUNT(*) AS c FROM pattern_shingles')->hash->{c};
  my $sl       = $db->query('SELECT COUNT(*) AS c FROM shingle_license')->hash->{c};
  my $patterns = $db->query('SELECT COUNT(*) AS c FROM license_patterns')->hash->{c};
  ok $rows > 0, "backfill produced pattern_shingles rows ($rows for $patterns patterns)";
  ok $sl > 0,   "backfill rebuilt shingle_license ($sl rows)";
};

done_testing;
