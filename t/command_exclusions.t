# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Mojo::Base -strict, -signatures;

use FindBin;
use lib "$FindBin::Bin/lib";

use Test::More;
use Test::Mojo;
use Cavil::Test;
use Mojo::File qw(tempdir);

plan skip_all => 'set TEST_ONLINE to enable this test' unless $ENV{TEST_ONLINE};

my $cavil_test = Cavil::Test->new(online => $ENV{TEST_ONLINE}, schema => 'command_exclusions_test');
my $t          = Test::Mojo->new(Cavil => $cavil_test->default_config);
my $app        = $t->app;
$cavil_test->mojo_fixtures($app);
my $db = $app->pg->db;

my $run = sub (@args) {
  my $buffer = '';
  open my $handle, '>', \$buffer;
  local *STDOUT = $handle;
  $app->start('exclusions', @args);
  close $handle;
  return $buffer;
};
my $count = sub { $db->query('SELECT COUNT(*) FROM unpack_exclusions')->array->[0] };

my $dir  = tempdir;
my $file = $dir->child('cavil.exclude')->spew(<<'EOF');
# Endless unpacking
buildah: test.tar
gcc12:   some-broken.tar   # trailing comment

# Zip bombs
SecLists: zip-bomb.zip
gcc*: another.tar.gz
gcc?: specific.zip
gcc1?: huge.bin
broken[: bad.tar
gcc: a|b.tar
EOF

subtest 'Import' => sub {
  $app->unpack_exclusions->add({package_glob => 'gcc1?', file => 'huge.bin', reason => 'Too big'}, 'test_bot');
  my $output = $run->('--import', "$file", '--user', 'test_bot');
  like $output, qr/Imported 5 excluded files, skipped 1 that already existed/,      'imported';
  like $output, qr/Skipped broken\[: bad.tar \(The package pattern is not valid\)/, 'invalid package pattern';
  like $output, qr/Skipped gcc: a\|b.tar \(The file name cannot contain/,           'invalid file name';

  my $exclusions = $app->unpack_exclusions;
  is_deeply $exclusions->for_package('buildah'), ['test.tar'],                                  'single package';
  is_deeply $exclusions->for_package('gcc12'),   [qw(huge.bin some-broken.tar another.tar.gz)], 'several rules';
  is_deeply $exclusions->for_package('gcc9'),    [qw(another.tar.gz specific.zip)],             'globs';
  is_deeply $exclusions->for_package('clang'),   [],                                            'no match';

  my $reason = sub ($file) { $db->select('unpack_exclusions', 'reason', {file => $file})->hash->{reason} };
  is $reason->('test.tar'),        'Endless unpacking', 'comment becomes the reason';
  is $reason->('some-broken.tar'), 'Endless unpacking', 'trailing comment is not part of the rule';
  is $reason->('specific.zip'),    'Zip bombs',         'for every rule below it';
  is $reason->('huge.bin'),        'Too big',           'existing rule untouched';
  is $db->select('unpack_exclusions', 'owner', {file => 'test.tar'})->hash->{owner},
    $db->select('bot_users', 'id', {login => 'test_bot'})->hash->{id}, 'recorded for the user';
  is $db->query(q{SELECT COUNT(*) FROM audit_events WHERE type = 'unpack_exclusion.added' AND actor IS NOT NULL})
    ->array->[0], 6, 'imported rules are audited for the user';
};

subtest 'Running it again is harmless' => sub {
  like $run->('--import', "$file", '--user', 'test_bot'),
    qr/Imported 0 excluded files, skipped 6 that already existed/, 'all skipped';
  is $count->(), 6, 'no duplicates';
};

# Last, a usage error leaves the selected output handle behind, so later output could not be captured anymore
subtest 'Missing options' => sub {
  eval { $run->('--import', "$file") };
  like $@, qr/Usage: APPLICATION exclusions/, 'user is required';
  eval { $run->('--user', 'test_bot') };
  like $@, qr/Usage: APPLICATION exclusions/, 'file is required';
  eval { $run->('--import', "$file", '--user', 'nobody') };
  like $@, qr/User "nobody" does not exist/, 'unknown user';
  is $count->(), 6, 'nothing imported';
};

done_testing;
