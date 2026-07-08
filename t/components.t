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

subtest 'composer' => sub {
  my $v2 = detect('app/vendor/composer/installed.json', 'composer/installed-v2.json');
  is_deeply [sort map { $_->{purl} } @$v2], ['pkg:composer/monolog/monolog@2.9.1', 'pkg:composer/psr/log@1.1.4'],
    'installed.json lists every vendored package';
  my ($monolog) = grep { $_->{name} eq 'monolog/monolog' } @$v2;
  is $monolog->{type},    'composer', 'ecosystem recorded';
  is $monolog->{version}, '2.9.1',    'version from installed.json';
  is $monolog->{license}, 'MIT',      'license from installed.json';

  my $v1 = detect('vendor/composer/installed.json', 'composer/installed-v1.json');
  is $v1->[0]{purl},    'pkg:composer/symfony/console@v3.4.0', 'Composer 1 bare-array format parsed';
  is $v1->[0]{license}, 'MIT OR Apache-2.0',                   'multiple licenses joined';
};

subtest 'nuget' => sub {
  is_deeply detect('x/Newtonsoft.Json.13.0.3.nupkg/Newtonsoft.Json.nuspec', 'nuget/expression.nuspec'),
    [
    {
      type    => 'nuget',
      name    => 'Newtonsoft.Json',
      version => '13.0.3',
      purl    => 'pkg:nuget/Newtonsoft.Json@13.0.3',
      license => 'MIT',
      source  => 'x/Newtonsoft.Json.13.0.3.nupkg/Newtonsoft.Json.nuspec'
    }
    ],
    'id, version and SPDX license expression';

  is detect('a/legacy.nuspec', 'nuget/licenseurl.nuspec')->[0]{license}, undef,
    'a licenseUrl-only nuspec leaves the license for backfill';

  # A .nuspec is also a build template; source trees ship it with unresolved $token$ placeholders
  is_deeply detect('antlr4/runtime/Cpp/runtime/nuget/ANTLR4.Runtime.cpp.static.nuspec', 'nuget/template.nuspec'), [],
    'a nuspec template with placeholder id/version is not a component';
};

subtest 'rubygems' => sub {
  is_deeply detect('vendor/bundle/ruby/3.1.0/specifications/net-http-0.3.2.gemspec', 'rubygems/net-http.gemspec'),
    [
    {
      type    => 'gem',
      name    => 'net-http',
      version => '0.3.2',
      purl    => 'pkg:gem/net-http@0.3.2',
      license => 'MIT OR Ruby',
      source  => 'vendor/bundle/ruby/3.1.0/specifications/net-http-0.3.2.gemspec'
    }
    ],
    'installed gemspec: hyphenated name split correctly, licenses from body';

  # A cached gem: Cavil unpacks the .gem and drops the extension, so the metadata is at <name-version>/metadata;
  # identity comes from its content (a YAML gemspec)
  my $cached = detect('vendor/cache/rack-3.0.0/metadata', 'rubygems/metadata');
  is $cached->[0]{purl},    'pkg:gem/rack@3.0.0', 'cached gem metadata parsed by content';
  is $cached->[0]{license}, 'MIT',                'license from the YAML metadata';

  my $junk = "foo: bar\nbaz: 1\n";
  is_deeply $registry->detect_file('x/metadata', \$junk), [], 'a non-gem "metadata" file is ignored';
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
