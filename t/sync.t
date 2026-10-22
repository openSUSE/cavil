# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Mojo::Base -strict;

use FindBin;
use lib "$FindBin::Bin/lib";

use Test::More;
use Test::Mojo;
use Cavil::Test;
use Cavil::Model::AuditLog qw(audit_event);
use Mojolicious::Lite;
use Mojo::File qw(tempdir);
use Mojo::JSON qw(decode_json encode_json);

plan skip_all => 'set TEST_ONLINE to enable this test' unless $ENV{TEST_ONLINE};

my $cavil_test = Cavil::Test->new(online => $ENV{TEST_ONLINE}, schema => 'sync_test');
my $config     = $cavil_test->default_config;
$config->{classifier} = {url => 'http://127.0.0.1:5000', token => 'TEST:TOKEN:12345'};
my $t = Test::Mojo->new(Cavil => $config);
$cavil_test->mojo_fixtures($t->app);

my $sync     = $t->app->sync->silent(1);
my $patterns = $t->app->patterns;
my $tempdir  = tempdir;
my $path     = $tempdir->child('license_patterns.jsonl');

subtest 'Export license patterns' => sub {
  ok $sync->store($path) > 0, 'multiple license patterns stored';
  my $licenses = [map { length $_ ? decode_json($_) : () } split "\n", $path->slurp];

  my $apache = $patterns->find(1);
  is $apache->{license},  'Apache-2.0', 'right license';
  is $apache->{packname}, '',           'no packname';
  ok $apache->{pattern}, 'has pattern';
  ok my $uuid = $apache->{unique_id}, 'has UUID';
  my $hash = $licenses->[0];
  is $hash->{license},   'Apache-2.0', 'right license';
  is $hash->{packname},  '',           'no packname';
  is $hash->{unique_id}, $uuid,        'same UUID';

  $apache = $patterns->find(2);
  is $apache->{license},  'Apache-2.0',       'right license';
  is $apache->{packname}, 'perl-Mojolicious', 'right packname';
  ok $uuid = $apache->{unique_id}, 'has UUID';
  $hash = $licenses->[1];
  is $hash->{license},   'Apache-2.0',       'right license';
  is $hash->{packname},  'perl-Mojolicious', 'right packname';
  is $hash->{unique_id}, $uuid,              'same UUID';

  my $artistic = $patterns->find(3);
  is $artistic->{license}, 'Artistic-2.0', 'right license';
  ok $artistic->{pattern}, 'has pattern';
  ok $uuid = $artistic->{unique_id}, 'has UUID';
  $hash = $licenses->[2];
  is $hash->{license},   'Artistic-2.0', 'right license';
  is $hash->{unique_id}, $uuid,          'same UUID';
};

subtest 'Import license patterns' => sub {
  is $sync->load($path), 0, 'no new patterns to import yet';
  my $apache = $patterns->find(1);
  ok my $apache_uuid = $apache->{unique_id}, 'has UUID';
  my $artistic = $patterns->find(3);
  ok my $artistic_uuid = $apache->{unique_id}, 'has UUID';

  my $db = $t->app->pg->db;
  $db->delete('license_patterns', {id => $apache->{id}});
  is $db->select('license_patterns', '*', {unique_id => $apache_uuid})->rows, 0, 'pattern with UUID deleted';
  $db->delete('license_patterns', {id => $artistic->{id}});
  is $db->select('license_patterns', '*', {unique_id => $artistic_uuid})->rows, 0, 'pattern with UUID deleted';

  is $sync->load($path), 2, 'two new patterns imported';
  is $db->select('license_patterns', '*', {unique_id => $apache_uuid})->rows,   1, 'pattern with UUID exists again';
  is $db->select('license_patterns', '*', {unique_id => $artistic_uuid})->rows, 1, 'pattern with UUID exists again';
};

subtest 'catch_all round-trips through export/import' => sub {
  my $db = $t->app->pg->db;

  # create() derives catch_all from the license name for a brand-new license
  my $any = $patterns->create(pattern => 'a distinct sync any permissive marker', license => 'Any Permissive');
  is $any->{catch_all}, 1, 'a grab-bag "Any ..." license is flagged catch_all on create';
  is $db->query("SELECT catch_all FROM license_patterns WHERE license = 'Apache-2.0' LIMIT 1")->hash->{catch_all}, 0,
    'a concrete license (Apache-2.0) is not catch_all';

  my $tmp = $tempdir->child('roundtrip.jsonl');
  $sync->store($tmp);
  my ($exported) = grep { $_->{license} eq 'Any Permissive' } map { length $_ ? decode_json($_) : () } split "\n",
    $tmp->slurp;
  ok $exported,              'the catch_all license is exported';
  ok $exported->{catch_all}, 'catch_all is present and true in the export';

  # Deleting and re-importing restores the flag from the JSONL
  my $uuid = $any->{unique_id};
  $db->delete('license_patterns', {id => $any->{id}});
  is $sync->load($tmp), 1, 'the catch_all pattern is re-imported';
  is $db->select('license_patterns', 'catch_all', {unique_id => $uuid})->hash->{catch_all}, 1,
    'catch_all survived the export/import round-trip';
};

subtest 'An import cannot smuggle in a flag the license name contradicts' => sub {
  my $db = $t->app->pg->db;

  my $lying = $tempdir->child('lying.jsonl');
  $lying->spew(
    encode_json(
      {license => 'Any Permissive', pattern => 'an imported grab-bag claiming otherwise', catch_all => 0, risk => 5}
      )
      . "\n"
      . encode_json(
      {
        license   => 'Apache-2.0',
        pattern   => 'an imported concrete license claiming otherwise',
        catch_all => 1,
        risk      => 5
      }
      )
      . "\n"
  );

  is $sync->load($lying), 2, 'both patterns are imported';
  is $db->query('SELECT catch_all FROM license_patterns WHERE pattern = ?', 'an imported grab-bag claiming otherwise')
    ->hash->{catch_all}, 1, 'the grab-bag is flagged from its name, not from the file';
  is $db->query('SELECT catch_all FROM license_patterns WHERE pattern = ?',
    'an imported concrete license claiming otherwise')->hash->{catch_all}, 0,
    'and the concrete license is left unflagged';
};

subtest 'Update license patterns' => sub {
  my $db = $t->app->pg->db;
  my %id = map { $_ => $patterns->create(pattern => "Update fixture $_ terms", license => "Update-$_")->{id} }
    qw(kept edited removed legacy reworded unaudited);
  my $shipped = $tempdir->child('shipped.jsonl');
  $sync->store($shipped);
  my $new = {unique_id => '6f1c0f4e-0d6b-4c8e-9a51-6a5d0c1b2e3f', license => 'Update-new', pattern => 'Update new'};
  $shipped->spew($shipped->slurp . encode_json($new) . "\n");

  $patterns->update($id{edited}, pattern => 'Update fixture edited terms, revised', license => 'Update-edited');
  $patterns->remove($id{removed});

  # Removed before removals recorded the unique_id, one of them after an edit
  my $legacy = $patterns->find($id{legacy});
  $db->delete('license_patterns', {id => $id{legacy}});
  audit_event($db, type => 'pattern.removed', data => {pattern => $id{legacy}, text => $legacy->{pattern}});
  $patterns->update($id{reworded}, pattern => 'Update fixture reworded terms, revised', license => 'Update-reworded');
  $db->delete('license_patterns', {id => $id{reworded}});
  audit_event(
    $db,
    type => 'pattern.removed',
    data => {pattern => $id{reworded}, text => 'Update fixture reworded terms, revised'}
  );

  # Removed before the audit log existed, there is no trace left
  $db->delete('license_patterns', {id => $id{unaudited}});

  is $sync->pending($shipped), 2, 'the new pattern and the untraceable removal';
  is_deeply [sort map { $_->{license} } @{$sync->update($shipped)}], ['Update-new', 'Update-unaudited'],
    'only those are added';
  is $db->select('license_patterns', 'id', {unique_id => $new->{unique_id}})->rows, 1, 'new pattern exists';
  is $db->select('license_patterns', 'id', {license => "Update-$_"})->rows, 0, "$_ pattern stays removed"
    for qw(removed legacy reworded);
  is_deeply $db->select('license_patterns', 'pattern', {license => 'Update-edited'})->arrays->to_array,
    [['Update fixture edited terms, revised']], 'the edit stands, the shipped text does not return';
  is $sync->pending($shipped), 0, 'nothing pending';
  is_deeply $sync->update($shipped), [], 'nothing added';
};

done_testing;
