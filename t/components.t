# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Mojo::Base -strict, -signatures;

use FindBin;
use Test::More;
use Mojo::File qw(path);
use Cavil::Bom::Registry;

my $registry = Cavil::Bom::Registry->new;
my $bom      = path($FindBin::Bin, 'bom');

# Detect components from a fixture file, as if it were found at $path in an unpacked tree
sub detect ($path, $fixture) {
  my $content = $bom->child(split '/', $fixture)->slurp;
  return $registry->detect_file($path, \$content);
}

subtest 'Basename matching (path-independent)' => sub {
  ok $registry->matches('a/b/c/package.json'),                       'npm package.json';
  ok $registry->matches('deep/node_modules.obscpio._/x/Cargo.toml'), 'cargo Cargo.toml under obscured dir';
  ok !$registry->matches('src/README.md'),                           'ignores unrelated files';
  ok !$registry->matches('src/package.json.bak'),                    'anchored to the real basename';
};

subtest 'npm' => sub {
  is_deeply detect('node_modules/left-pad/package.json', 'npm/normal.json'),
    [
    {
      type    => 'npm',
      name    => 'left-pad',
      version => '1.3.0',
      purl    => 'pkg:npm/left-pad@1.3.0',
      license => 'WTFPL',
      source  => 'node_modules/left-pad/package.json'
    }
    ],
    'name, version, license and purl';

  my $scoped = detect('x/node_modules/@babel/core/package.json', 'npm/scoped.json');
  is $scoped->[0]{purl},    'pkg:npm/%40babel/core@7.24.0', 'scoped package purl encodes the scope';
  is $scoped->[0]{license}, 'MIT',                          'scoped package license';

  is detect('a/package.json', 'npm/legacy.json')->[0]{license}, 'MIT', 'legacy licenses array';
  is_deeply detect('a/package.json', 'npm/nameless.json'), [], 'no name/version -> not a component';

  # gx reuses package.json to describe vendored Go modules; these are not npm components
  is_deeply detect('vendor/github.com/blang/semver/package.json', 'npm/gx-go.json'), [],
    'gx/Go package.json is not detected as an npm component';
};

subtest 'cargo' => sub {
  is_deeply detect('vendor/serde/Cargo.toml', 'cargo/crate.toml'),
    [
    {
      type    => 'cargo',
      name    => 'serde',
      version => '1.0.197',
      purl    => 'pkg:cargo/serde@1.0.197',
      license => 'MIT OR Apache-2.0',
      source  => 'vendor/serde/Cargo.toml'
    }
    ],
    'name, version, license and purl';

  is_deeply detect('Cargo.toml', 'cargo/workspace.toml'), [], 'workspace manifest (no [package]) -> nothing';
};

subtest 'pypi' => sub {
  is_deeply detect('site-packages/requests-2.31.0.dist-info/METADATA', 'pypi/METADATA'),
    [
    {
      type    => 'pypi',
      name    => 'requests',
      version => '2.31.0',
      purl    => 'pkg:pypi/requests@2.31.0',
      license => 'Apache-2.0',
      source  => 'site-packages/requests-2.31.0.dist-info/METADATA'
    }
    ],
    'name, version, license (License field, body ignored)';

  my $classified = detect('x/Some_Package-3.4.5.egg-info/PKG-INFO', 'pypi/classifier.PKG-INFO');
  is $classified->[0]{purl},    'pkg:pypi/some-package@3.4.5', 'name normalized in the purl';
  is $classified->[0]{license}, 'MIT License',                 'license falls back to the OSI classifier';
};

subtest 'maven' => sub {
  is_deeply detect('BOOT-INF/lib/guava.jar/META-INF/maven/com.google.guava/guava/pom.properties',
    'maven/pom.properties'),
    [
    {
      type    => 'maven',
      name    => 'com.google.guava:guava',
      version => '33.0.0-jre',
      purl    => 'pkg:maven/com.google.guava/guava@33.0.0-jre',
      license => undef,
      source  => 'BOOT-INF/lib/guava.jar/META-INF/maven/com.google.guava/guava/pom.properties'
    }
    ],
    'group/artifact/version (license left for backfill)';
};

subtest 'go' => sub {
  my $mods = detect('vendor/modules.txt', 'go/modules.txt');
  is scalar(@$mods), 2, 'one component per module entry (## and bare lines skipped)';
  is_deeply [sort map { $_->{purl} } @$mods],
    ['pkg:golang/github.com/gorilla/mux@v1.8.1', 'pkg:golang/golang.org/x/sys@v0.16.0'],
    'module paths kept verbatim in the purl';

  # "replace" directives: a versioned replacement wins; a local replace keeps the original identity
  my $txt = "# a.com/orig v1.0.0 => b.com/fork v2.0.0\n# c.com/local v3.0.0 => ./vendored\n";
  is_deeply [map { $_->{purl} } @{$registry->detect_file('vendor/modules.txt', \$txt)}],
    ['pkg:golang/b.com/fork@v2.0.0', 'pkg:golang/c.com/local@v3.0.0'],
    'replace directives resolved to the vendored identity';
};

subtest 'Identity comes from content, not path' => sub {
  my $obscured = detect('node_modules.obscpio._/package._1/package.json', 'npm/normal.json');
  is $obscured->[0]{name},    'left-pad',               'obscured directory names are irrelevant';
  is $obscured->[0]{version}, '1.3.0',                  'version from content';
  is $obscured->[0]{purl},    'pkg:npm/left-pad@1.3.0', 'purl from content';
};

subtest 'Malformed input never dies' => sub {
  my $broken = '{ this is not valid json';
  is_deeply $registry->detect_file('x/package.json', \$broken), [], 'malformed metadata yields no components';
};

subtest 'Broken metadata is handled gracefully' => sub {
  my %case = (
    'wrong type (name is an object)' => '{"name": {"nested": 1}, "version": "1.0.0"}',
    'invalid UTF-8 encoding'         => qq({"name": "x", "version": "1.0.0", "license": "\xff\xfe"}),
    'control characters in name'     => qq({"name": "ev\x01il", "version": "1.0.0"}),
    'absurdly long name'             => '{"name": "' . ('a' x 600) . '", "version": "1.0.0"}',
  );
  for my $desc (sort keys %case) {
    my $content = $case{$desc};
    is_deeply $registry->detect_file('x/package.json', \$content), [], "no component: $desc";
  }

  # A broken *license* only drops the license, not the whole component
  my $long = '{"name": "keepme", "version": "1.0.0", "license": "' . ('L' x 600) . '"}';
  my $c    = $registry->detect_file('x/package.json', \$long);
  is scalar(@$c),      1,        'component with an unusable license is still kept';
  is $c->[0]{name},    'keepme', 'identity preserved';
  is $c->[0]{license}, undef,    'unusable license dropped';
};

done_testing;
