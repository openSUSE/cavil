# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Mojo::Base -strict, -signatures;

use Test::More;
use Mojo::File qw(curfile tempdir);
use Cavil::Checkout;
use Cavil::Declarations qw(is_root_file single_root);

my $TMP = tempdir;

sub fixture ($name) {
  my ($from) = curfile->sibling('legal-bot', $name)->list({dir => 1})->each;
  my $target = $TMP->child('fixtures', $name, $from->basename)->make_path;
  $_->copy_to($target->child($_->basename)) for $from->list({hidden => 1})->each;
  if (-d (my $debian = $from->child('debian'))) {
    my $to = $target->child('debian')->make_path;
    $_->copy_to($to->child($_->basename)) for $debian->list->each;
  }
  Cavil::Checkout->new($target)->unpack;
  return Cavil::Declarations->new->detect($target);
}

# An already unpacked tree, laid out as {path => content}
sub tree ($name, $files) {
  my $dir = $TMP->child('trees', $name, 'hash');
  $dir->child('.unpacked', split '/')->tap(sub { $_->dirname->make_path })->spew($files->{$_}) for keys %$files;
  return Cavil::Declarations->new->detect($dir);
}

sub summary ($info) {
  return [map { join ' ', $_->{format}, $_->{file}, $_->{name} // '-', $_->{license} // '-' } @{$info->{declarations}}];
}

subtest 'Spec with subpackages' => sub {
  my $info = fixture('kmod');
  is_deeply summary($info),
    [
    'spec kmod.spec kmod LGPL-2.1+ and GPL-2.0+',
    'spec kmod.spec kmod-compat GPL-2.0+',
    'spec kmod.spec libkmod1 LGPL-2.1+'
    ],
    'one declaration per distinct license';
  my $main = $info->{declarations}[0];
  is $main->{version}, '3',                                                 'right version';
  is $main->{summary}, 'Utilities to load modules into the kernel',         'right summary';
  is $main->{url},     'http://www.politreco.com/2011/12/announce-kmod-2/', 'right url';
  is_deeply $info->{incomplete_checkout}, [], 'complete checkout';
};

subtest 'Spec macros' => sub {
  my $main = fixture('MozillaFirefox')->{declarations}[0];
  is $main->{name},    'MozillaFirefox', 'right name';
  is $main->{version}, '140.13.0',       'macro chain expanded';
  is $main->{license}, 'MPL-2.0',        'right license';
};

subtest 'Kiwi' => sub {
  is_deeply fixture('ceph-image')->{declarations},
    [
    {
      format  => 'kiwi',
      file    => 'ceph-image.kiwi',
      name    => 'ceph-image',
      version => '1.0.0',
      license => 'SUSE-Permissive',
      summary => 'Ceph base container image',
      url     => 'https://bugs.opensuse.org'
    }
    ],
    'right declaration';
  is_deeply summary(fixture('error-invalid-xml-kiwi')), ['kiwi error-invalid-xml-kiwi.kiwi - -'], 'broken XML';
};

subtest 'Dockerfiles' => sub {
  my $info = fixture('go1.16-devel-container');
  is_deeply summary($info),
    [
    'dockerfile Dockerfile - BSD-3-Clause AND MIT',
    'dockerfile Dockerfile.custom - BSD-3-Clause',
    'dockerfile dummy.Dockerfile - BSD-3-Clause'
    ],
    'plain, flavored and named Dockerfiles';
  is $info->{declarations}[0]{version},           '%%PKG_VERSION%%.%RELEASE%', 'version verbatim';
  is scalar @{$info->{declarations}[0]{notices}}, 1,                           'legal review notice';
};

subtest 'Helm' => sub {
  my $info = fixture('harbor-helm');
  is_deeply summary($info), ['helm Chart.yaml harbor MIT'], 'right declaration';
  is $info->{declarations}[0]{version}, '1.2.3',               'right version';
  is $info->{declarations}[0]{url},     'https://goharbor.io', 'right url';
  is_deeply summary(fixture('error-invalid-yaml-helm')), ['helm Chart.yaml - MIT'], 'license survives broken YAML';
};

subtest 'Debian' => sub {
  my $info = fixture('libfsverity0');
  is_deeply summary($info), ['debian debian/copyright fsverity-utils MIT'], 'license from the copyright file';
  is $info->{declarations}[0]{url}, 'https://git.kernel.org/pub/scm/linux/kernel/git/ebiggers/fsverity-utils.git',
    'right url';

  $info = tree(
    'debian',
    {
      'debian/control'   => "Source: demo\nStandards-Version: 4.6.0\n",
      'debian/copyright' => "Files: *\nLicense: GPL-2+\n\nFiles: lib/*\nLicense: MIT\n",
      'debian/changelog' => "demo (1.2-3) unstable; urgency=medium\n\n  * Initial\n\ndemo (1.1-1) unstable\n"
    }
  );
  is_deeply summary($info), ['debian debian/copyright demo GPL-2+'], 'first license';
  is $info->{declarations}[0]{version}, '1.2-3', 'version from the changelog, not the policy version';

  is_deeply tree('debian-bare', {'debian/copyright' => "License: MIT\n"})->{declarations},
    [{format => 'debian', file => 'debian/copyright', license => 'MIT'}], 'no control or changelog';
};

subtest 'ObsPrj' => sub {
  is_deeply summary(fixture('PackageHub')), ['obsprj workflow.config - -'], 'product without a license';
  is_deeply tree('not-obsprj',     {'workflow.config' => '{"foo": 1}'})->{declarations}, [], 'other workflow.config';
  is_deeply tree('obsprj-partial', {'workflow.config' => '{"Workflows": []}'})->{declarations}, [], 'no project name';
  is_deeply tree('obsprj-list',    {'workflow.config' => '[1]'})->{declarations},               [], 'not an object';
};

subtest 'Mixed formats' => sub {
  my $info = fixture('mixed');
  is_deeply summary($info),
    [
    'spec mixed.spec - MIT AND BSD-3-Clause',
    'spec mixed-more.spec - MIT',
    'debian debian/copyright mixed Apache-2.0',
    'kiwi mixed.kiwi ceph-image LicenseRef-SUSE-Permissive',
    'kiwi mixed-more.kiwi ceph-image Apache-2.0',
    'dockerfile mixed.Dockerfile - MIT',
    'dockerfile Dockerfile - BSD-2-Clause',
    'dockerfile mixed-more.Dockerfile - BSD-3-Clause',
    'helm Chart.yaml mixed MIT'
    ],
    'packaging order, named file first within a format';
  is scalar(map { @{$_->{notices} // []} } @{$info->{declarations}}), 4, 'notices from every file';
};

subtest 'Licenses are verbatim' => sub {
  is_deeply summary(fixture('error-no-spdx')),         ['spec error-no-spdx.spec - MPLv2.0'],           'no aliasing';
  is_deeply summary(fixture('error-invalid-license')), ['spec error-invalid-license.spec - (Artistic'], 'no parsing';
};

subtest 'Incomplete checkout' => sub {
  is_deeply fixture('error-incomplete-checkout')->{incomplete_checkout},
    [{name => 'download_files', mode => 'trylocal'}], 'remote service';
};

subtest 'Packaging and upstream side by side' => sub {
  my $info = fixture('vendored');
  is_deeply summary($info),
    [
    'spec vendored.spec vendored MIT',
    'npm vendored-1.0/package.json my-app MIT',
    'pypi vendored-1.0/selfpkg.egg-info/PKG-INFO selfpkg MIT'
    ],
    'root manifests of the single wrapper are declarations, vendored ones are not';
  is $info->{declarations}[1]{version}, '1.0.0', 'upstream version';
};

subtest 'Upstream project without packaging' => sub {
  my $info = tree(
    'cli',
    {
      'demo-1.0/Dockerfile'                  => "FROM scratch\n",
      'demo-1.0/package.json'                => '{"name": "demo", "version": "1.0.0", "license": "Apache-2.0"}',
      'demo-1.0/node_modules/a/package.json' => '{"name": "a", "version": "2.0.0", "license": "MIT"}'
    }
  );
  is_deeply summary($info), ['npm demo-1.0/package.json demo Apache-2.0', 'dockerfile demo-1.0/Dockerfile - -'],
    'wrapper directory is the root, first licensed declaration is primary';

  $info = tree('multi', {'a/demo.spec' => "License: MIT\n", 'b/package.json' => '{"name": "b", "version": "1"}'});
  is_deeply $info->{declarations}, [], 'nothing below several top-level directories';

  $info = tree('plain', {'src/main.c' => "int main() {}\n"});
  is_deeply $info, {declarations => [], incomplete_checkout => []}, 'plain source';

  is_deeply(
    Cavil::Declarations->new->detect($TMP->child('not-unpacked')->make_path),
    {declarations => [], incomplete_checkout => []},
    'not unpacked'
  );
};

subtest 'Hostile values' => sub {
  my $long = 'x' x 600;
  my $info = tree(
    'hostile',
    {
      'hostile.spec'           => "Name: hostile\nVersion: 1\x01\nSummary: $long\nLicense:   MIT  \n",
      'hostile.processed.spec' => "License: GPL\n",
      'Chart.yaml'             => "name: [1, 2]\ndescription: |\n  two\n  lines\n"
    }
  );
  is_deeply summary(tree('huge', {'huge.spec' => "License: MIT\n" . ('#' x 4_000_000)})), [], 'oversized file ignored';

  is_deeply [
    map {
      { %$_, notices => undef }
    } @{$info->{declarations}}
    ],
    [
    {
      format     => 'spec',
      file       => 'hostile.spec',
      name       => 'hostile',
      license    => 'MIT',
      '%doc'     => [],
      '%license' => [],
      notices    => undef
    },
    {format => 'helm', file => 'Chart.yaml', summary => 'two lines', notices => undef}
    ],
    'unusable values dropped, whitespace collapsed, processed copy ignored';
};

subtest 'Copied files' => sub {
  my $info = tree('copied', {'copied.spec' => "%files\n%license COPYING\n%doc README NEWS\n%doc AUTHORS\n"});
  is_deeply $info->{declarations}[0]{'%doc'},     [qw(README NEWS AUTHORS)], 'documentation';
  is_deeply $info->{declarations}[0]{'%license'}, ['COPYING'],               'licenses';
};

subtest 'Subpackage naming' => sub {
  my $info = tree(
    'sub',
    {
      'sub.spec' =>
        "Name: sub\nLicense: GPL-2.0-only\n%package devel\nLicense: MIT\n%package -n libsub\nLicense: LGPL-2.1\n"
    }
  );
  is_deeply summary($info),
    ['spec sub.spec sub GPL-2.0-only', 'spec sub.spec sub-devel MIT', 'spec sub.spec libsub LGPL-2.1'], 'right names';

  $info = tree(
    'first',
    {
          'first.spec' => "Name: first\nName: second\nVersion: 1\nVersion: 2\nURL: https://one\nUrl: https://two\n"
        . "License: MIT\nLicense: GPL-2.0-only\n%package doc\nSummary: Docs\n%package -n tool\n"
        . "License: Apache-2.0\nLicense: BSD-3-Clause\n"
    }
  );
  is_deeply summary($info), ['spec first.spec first MIT', 'spec first.spec tool Apache-2.0'],
    'first tag wins, subpackage without a license is no declaration';
  is $info->{declarations}[0]{version}, '1',           'first version';
  is $info->{declarations}[0]{url},     'https://one', 'first url';
  is $info->{declarations}[0]{summary}, undef,         'subpackage summary is not the main one';

  is_deeply summary(tree('nameless', {'nameless.spec' => "License: MIT\n%package devel\nLicense: GPL-2.0-only\n"})),
    ['spec nameless.spec - MIT', 'spec nameless.spec -devel GPL-2.0-only'], 'no main name';
};

subtest 'Package root' => sub {
  ok is_root_file('foo.spec',                       0), 'top level';
  ok is_root_file('debian/copyright',               0), 'Debian packaging';
  ok is_root_file('foo.egg-info/PKG-INFO',          0), 'Python metadata';
  ok is_root_file('foo-1.0/package.json',           1), 'single wrapper directory';
  ok is_root_file('foo-1.0/foo.dist-info/METADATA', 1), 'Python metadata in the wrapper';
  ok !is_root_file('foo-1.0/package.json',          0), 'one of several top-level directories';
  ok !is_root_file('foo-1.0/lib/package.json',      1), 'below the wrapper';
  ok !is_root_file('lib/debian/copyright',          0), 'Debian packaging below the root';

  my $dir = $TMP->child('roots');
  ok !single_root($dir->child('missing')), 'no tree';
  $dir->child('one', 'foo-1.0')->make_path;
  $dir->child('one', 'README')->spew('hi');
  ok single_root($dir->child('one')), 'one directory next to plain files';
  $dir->child('two', $_)->make_path for qw(a b);
  ok !single_root($dir->child('two')), 'two directories';
};

done_testing;
