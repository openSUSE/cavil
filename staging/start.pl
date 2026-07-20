use Mojo::Base -strict;

use FindBin;
use lib "$FindBin::Bin/../lib";
use Archive::Tar;
use Cavil::Util qw(SNIPPET_SCORE_VERSION);
use Mojo::File  qw(curfile path);
use Mojo::Pg;
use Mojo::Server;
use Mojo::Util qw(getopt);

my $dir = path(__FILE__)->sibling('do_not_commit');
die "Staging project already exists.\n" if -e $dir;

getopt 'clean' => \my $clean;

die <<'EOF' unless my $postgres = $ARGV[0];
PostgreSQL connection string required. You need an already existing but empty
database, and we will create seed data for you.

    # Staging environment with example reports
    perl staging/start.pl postgresql://tester:testing@/test

    # Staging environment with license patterns but no reports
    perl staging/start.pl postgresql://tester:testing@/test --clean

EOF
my $pg = Mojo::Pg->new($postgres);
$pg->db->query('drop schema if exists cavil_staging cascade');
$pg->db->query('create schema cavil_staging');

$dir->make_path;
my $checkouts = $dir->child('legal-bot')->make_path->realpath;
my $cache     = $dir->child('cache')->make_path->realpath;

my $online = Mojo::URL->new($postgres)->query([search_path => ['cavil_staging', 'public']])->to_unsafe_string;
my $conf   = $dir->child('cavil.conf')->spew(<<"EOF");
{
  secrets               => ['just_a_test'],
  checkout_dir          => '$checkouts',
  cache_dir             => '$cache',
  external_link_sources => [
    {
      pattern => '^obs#(\\d+)\$',
      url     => 'https://build.opensuse.org/request/show/\$1',
      label   => 'external',
      title   => 'Build service request'
    },
    {
      pattern => '^ibs#(\\d+)\$',
      url     => 'https://build.suse.de/request/show/\$1',
      label   => 'internal',
      title   => 'Build service request'
    },
    {
      pattern => '^soo#([^!]+)!(\\d+)\$',
      url     => 'https://src.opensuse.org/\$1/pulls/\$2',
      label   => 'external',
      title   => 'Gitea pull request'
    },
    {
      pattern => '^ssd#([^!]+)!(\\d+)\$',
      url     => 'https://src.suse.de/\$1/pulls/\$2',
      label   => 'internal',
      title   => 'Gitea pull request'
    }
  ],
  tokens               => ['staging:123'],
  pg                   => '$online',
  acceptable_risk      => 4,
  index_bucket_average => 100,
  cleanup_bucket_average => 50,
  days_to_keep_orphaned_packages => 30,
  days_to_keep_orphaned_duplicate_packages => 7,
  min_files_short_report => 20,
  max_email_url_size    => 2048,
  max_task_memory       => 5_000_000_000,
  max_worker_rss        => 100000,
  max_expanded_files    => 100,
  max_file_browser_size => 1000000,
  snippet_fold          => {
    enabled         => 1,
    threshold       => 0.95,
    min_margin      => 0.15,
    max_risk        => 5,
    clear_threshold => 0.97,
    overlap_clear   => 1,
    overlap_guard   => 0.9,
    cover_scope     => 'dir',
    cover_guard     => 0.9
  },
  spdx => {
    namespace => 'http://legaldb.suse.de/spdx/',
    creator => {
      name  => 'SUSE LLC',
      email => 'security\@suse.de'
    },
    license_ref_namespace => 'cavil'
  }
}
EOF

local $ENV{CAVIL_CONF} = "$conf";
my $app = Mojo::Server->new->build_app('Cavil');
$app->pg->migrations->migrate;

# Seed licenses and patterns
$app->sync->load(curfile->dirname->sibling('lib', 'Cavil', 'resources', 'license_patterns.jsonl')->to_string);

# Fill instance with test data
unless ($clean) {

  # Test checkouts
  my $tests = [
    ['perl-Mojolicious',       'c7cfdab0e71b0bebfdf8b2dc3badfecd'],
    ['ceph-image',             '5fcfdab0e71b0bebfdf8b5cc3badfecf'],
    ['go1.16-devel-container', 'ffcfdab0e71b1bebfdf8b5cc3badfeca'],
    ['harbor-helm',            '4fcfdab0e71b0bebfdf8b5cc3badfec4'],
    ['libfsverity0',           '9932c13432c3c5bdbe260ab8bc3b13ef'],
    ['PackageHub',             '280b37a43ba9dc09c563a5c4e99349c07414c9f46a8e8f8636d3ef8aaf63650b']
  ];
  for my $co (@$tests) {
    my $checkout = $checkouts->child(@$co)->make_path;
    my $test     = $dir->child('..', '..', 't', 'legal-bot', @$co)->realpath;
    $_->copy_to($checkout->child($_->basename)) for $test->list->each;
    my $deb_test = $test->child('debian');
    if (-d $deb_test) {
      my $deb_checkout = $checkout->child('debian')->make_path;
      $_->copy_to($deb_checkout->child($_->basename)) for $deb_test->list->each;
    }
  }

  # Second copy of perl-Mojolicious test checkout (different checksum but same content)
  my $test
    = $dir->child('..', '..', 't', 'legal-bot', 'perl-Mojolicious', 'c7cfdab0e71b0bebfdf8b2dc3badfecd')->realpath;
  my $checkout = $checkouts->child('perl-Mojolicious', 'c7cfdab0e71b0bebfdf8b2dc3bad1234')->make_path;
  $_->copy_to($checkout->child($_->basename)) for $test->list->each;

  # Third copy of perl-Mojolicious test checkout (different checksum and content)
  my $checkout2 = $checkouts->child('perl-Mojolicious', 'ffcfdab0e71b0bebfdf8b2dc3bad12ff')->make_path;
  $_->copy_to($checkout2->child($_->basename)) for $test->list->each;
  $checkout2->child('JustATest.pm')->spurt("# SPDX-License-Identifier: BSD-3-Clause\n\n\npackage JustATest;\n\n1;\n");

  # "perl-Mojolicious" example data
  my $user_id = $app->users->find_or_create(login => 'test_bot')->{id};
  my $pkgs    = $app->packages;
  my $mojo_id = my $pkg_id = $pkgs->add(
    name            => 'perl-Mojolicious',
    checkout_dir    => 'c7cfdab0e71b0bebfdf8b2dc3badfecd',
    api_url         => 'https://api.opensuse.org',
    requesting_user => $user_id,
    project         => 'devel:languages:perl',
    package         => 'perl-Mojolicious',
    srcmd5          => 'bd91c36647a5d3dd883d490da2140401',
    priority        => 5
  );
  $pkgs->imported($pkg_id);
  my $mojo = $pkgs->find($pkg_id);
  $mojo->{external_link} = 'obs#456712';
  $pkgs->update($mojo);
  $pkgs->unpack($pkg_id);
  $pkg_id = $pkgs->add(
    name            => 'perl-Mojolicious',
    checkout_dir    => 'c7cfdab0e71b0bebfdf8b2dc3bad1234',
    api_url         => 'https://api.opensuse.org',
    requesting_user => $user_id,
    project         => 'devel:languages:perl',
    package         => 'perl-Mojolicious',
    srcmd5          => 'bd91c36647a5d3dd883d490da2141234',
    priority        => 5
  );
  $pkgs->imported($pkg_id);
  $mojo = $pkgs->find($pkg_id);
  $mojo->{external_link} = 'obs#456713';
  $pkgs->update($mojo);
  $pkgs->unpack($pkg_id);
  my $mojo3_id = $pkg_id = $pkgs->add(
    name            => 'perl-Mojolicious',
    checkout_dir    => 'ffcfdab0e71b0bebfdf8b2dc3bad12ff',
    api_url         => 'https://api.opensuse.org',
    requesting_user => $user_id,
    project         => 'devel:languages:perl',
    package         => 'perl-Mojolicious',
    srcmd5          => 'eecfdab0e71b0bebfdf8b2dc3bad12ff',
    priority        => 5
  );
  $pkgs->imported($pkg_id);
  $mojo = $pkgs->find($pkg_id);
  $mojo->{external_link} = 'obs#456714';
  $pkgs->update($mojo);
  $pkgs->unpack($pkg_id);

  my $notes = $app->notes;
  $notes->add($mojo_id,  'perl-Mojolicious', $user_id, "Just a note $_", 0) for 1 .. 25;
  $notes->add($mojo3_id, 'perl-Mojolicious', $user_id, 'Another test',   0);

  # "ceph-image" example data
  $pkg_id = $pkgs->add(
    name            => 'ceph-image',
    checkout_dir    => '5fcfdab0e71b0bebfdf8b5cc3badfecf',
    api_url         => 'https://api.opensuse.org',
    requesting_user => $user_id,
    project         => 'filesystems:ceph',
    package         => 'ceph-image',
    srcmd5          => '4d91c36647a5d355883d490da2140404',
    priority        => 5
  );
  $pkgs->imported($pkg_id);
  my $ceph = $pkgs->find($pkg_id);
  $ceph->{external_link} = 'obs#913219';
  $pkgs->update($ceph);
  $pkgs->unpack($pkg_id);

  # "go1.16-devel-container" example data
  $pkg_id = $pkgs->add(
    name            => 'go1.16-devel-container',
    checkout_dir    => 'ffcfdab0e71b1bebfdf8b5cc3badfeca',
    api_url         => 'https://api.opensuse.org',
    requesting_user => $user_id,
    project         => 'devel:kubic:containers',
    package         => 'go1.16-devel-container',
    srcmd5          => 'dd91c36647a5d356883d490da2140412',
    priority        => 5
  );
  $pkgs->imported($pkg_id);
  my $go = $pkgs->find($pkg_id);
  $go->{external_link} = 'obs#881323';
  $pkgs->update($go);
  $pkgs->unpack($pkg_id);

  # "harbor-helm" example data
  $pkg_id = $pkgs->add(
    name            => 'harbor-helm',
    checkout_dir    => '4fcfdab0e71b0bebfdf8b5cc3badfec4',
    api_url         => 'https://api.opensuse.org',
    requesting_user => $user_id,
    project         => 'just:a:test',
    package         => 'harbor-helm',
    srcmd5          => 'abc1c36647a5d356883d490da2140def',
    priority        => 5,
    embargoed       => 1
  );
  $pkgs->imported($pkg_id);
  my $harbor = $pkgs->find($pkg_id);
  $harbor->{external_link} = 'obs#123456';
  $pkgs->update($harbor);
  $pkgs->unpack($pkg_id);

  # "libfsverity0" debian example data
  $pkg_id = $pkgs->add(
    name            => 'libfsverity0',
    checkout_dir    => '9932c13432c3c5bdbe260ab8bc3b13ef',
    api_url         => 'https://api.opensuse.org',
    requesting_user => $user_id,
    project         => 'just:a:test',
    package         => 'libfsverity0',
    srcmd5          => 'abc1c3664321d356883d490da2141234',
    priority        => 5
  );
  $pkgs->imported($pkg_id);
  my $deb = $pkgs->find($pkg_id);
  $deb->{external_link} = 'obs#395678';
  $pkgs->update($deb);
  $pkgs->unpack($pkg_id);

  # "PackageHub" ObsPrj example data
  $pkg_id = $pkgs->add(
    name            => 'PackageHub',
    checkout_dir    => '280b37a43ba9dc09c563a5c4e99349c07414c9f46a8e8f8636d3ef8aaf63650b',
    api_url         => 'gitea@src.opensuse.org:products/PackageHub.git',
    requesting_user => $user_id,
    project         => '',
    package         => 'PackageHub',
    srcmd5          => '280b37a43ba9dc09c563a5c4e99349c07414c9f46a8e8f8636d3ef8aaf63650b',
    priority        => 5
  );
  $pkgs->imported($pkg_id);
  my $obsprj = $pkgs->find($pkg_id);
  $obsprj->{external_link} = 'soo#products/PackageHub!123';
  $pkgs->update($obsprj);
  $pkgs->unpack($pkg_id);

  # Update products
  my $products   = $app->products;
  my $factory_id = $products->find_or_create('openSUSE:Factory')->{id};
  my $leap_id    = $products->find_or_create('openSUSE:Leap:15.0')->{id};
  $products->update($factory_id, [$mojo_id]);
  $products->update($leap_id,    [$mojo_id]);

  # Synthetic fold/clear/overlap playground. Snippets are AI-classified after the initial index below,
  # so it works in staging without a classifier server.
  my $lab_checkout = 'foldinglab00000000000000000000000001';
  my $lab_dir      = $checkouts->child('cavil-folding-lab', $lab_checkout)->make_path;
  my @blocks;
  my $block = sub {
    my ($marker, @body) = @_;
    push @blocks, "[$marker] fold lab keyword\n", map {"$_\n"} @body;
    push @blocks, map {"ordinary spacer line $marker $_\n"} 1 .. 10;
  };
  $block->(
    'FOLD_LOW_RISK',
    'This snippet should fold to a low risk synthetic license.',
    'It exists to make the folded tint and correction button easy to inspect.'
  );
  $block->(
    'FOLD_MAX_RISK',
    'This snippet should fold exactly at the configured max risk boundary.',
    'It is useful for checking the risk color used by derived matches.'
  );
  $block->(
    'NO_FOLD_HIGH_RISK',
    'This snippet is confident but points to a risk 6 license, above max_risk.',
    'It should remain unresolved so the high risk guard is visible.'
  );
  $block->(
    'CLEAR_BOILERPLATE',
    'This snippet looks like known boilerplate but has no margin over its runner up.',
    'It should clear without asserting a license.'
  );
  $block->(
    'OVERLAP_CLEAR',
    'This snippet overlaps a real curated license match on its first line.',
    'It should overlap-clear while the direct match still reports the license.'
  );
  $block->(
    'FOLD_WITH_DIRECT_MATCH',
    'This folded region also has a real curated match on its first line.',
    'The real match should win on that line and the fold should color the rest.'
  );
  $lab_dir->child('folding-lab.txt')->spurt(join '', @blocks);

  # The overlap-guard case lives in its own directory. It overlaps one license but resembles a
  # different one, so the overlap guard must keep it unresolved - and it must NOT be swept up by
  # covered-clear, so it deliberately shares a directory with no concrete license match of its own
  # (unlike folding-lab.txt, whose FOLD_WITH_DIRECT_MATCH puts a risk 4 match in that directory).
  my $guarded_dir = $lab_dir->child('guarded-lab');
  $guarded_dir->make_path;
  $guarded_dir->child('guarded.txt')
    ->spurt("[OVERLAP_GUARDED] fold lab keyword\n"
      . "This snippet overlaps one license but strongly resembles a different one.\n"
      . "The guard should keep it unresolved for human review.\n");

  # Covered-clear playground: an awkward license fragment in a file that has no license match of its
  # own, sitting next to a sibling file that does. With cover_scope 'dir' (see snippet_fold config) the
  # concrete license in the sibling covers the fragment - the common minified-file-next-to-LICENSE case.
  # This is the one resolution that needs a second file, so it lives in its own directory.
  my $covered_dir = $lab_dir->child('covered-lab');
  $covered_dir->make_path;
  $covered_dir->child('library.min.js')
    ->spurt("[COVERED_BY_DIR] fold lab keyword\n"
      . "This awkward license fragment has no license match of its own.\n"
      . "The sibling LICENSE in the same directory already carries a concrete license,\n"
      . "so directory-scope coverage clears it without asserting anything.\n");
  $covered_dir->child('LICENSE')->spurt("fold lab covering file license\n");

  my $fold_low = $app->patterns->create(
    pattern   => 'fold lab low risk license body',
    license   => 'Fold-Lab-Low',
    risk      => 2,
    unique_id => '11111111-1111-4111-8111-111111111111'
  );
  my $fold_max = $app->patterns->create(
    pattern   => 'fold lab max risk license body',
    license   => 'Fold-Lab-Max-Risk',
    risk      => 5,
    unique_id => '11111111-1111-4111-8111-111111111112'
  );
  my $fold_high = $app->patterns->create(
    pattern   => 'fold lab high risk license body',
    license   => 'Fold-Lab-High-Risk',
    risk      => 6,
    unique_id => '11111111-1111-4111-8111-111111111113'
  );
  my $overlap = $app->patterns->create(
    pattern   => 'fold lab overlap direct license',
    license   => 'Fold-Lab-Overlap',
    risk      => 2,
    unique_id => '11111111-1111-4111-8111-111111111114'
  );
  my $guarded = $app->patterns->create(
    pattern   => 'fold lab guarded different license',
    license   => 'Fold-Lab-Guarded',
    risk      => 4,
    unique_id => '11111111-1111-4111-8111-111111111115'
  );
  my $inside = $app->patterns->create(
    pattern   => 'fold lab direct match inside fold',
    license   => 'Fold-Lab-Inside-Direct',
    risk      => 4,
    unique_id => '11111111-1111-4111-8111-111111111116'
  );
  $app->patterns->create(pattern => 'fold lab keyword', unique_id => '11111111-1111-4111-8111-111111111117');
  my $covering = $app->patterns->create(
    pattern   => 'fold lab covering file license',
    license   => 'Fold-Lab-Covering',
    risk      => 3,
    unique_id => '11111111-1111-4111-8111-111111111118'
  );

  my $lab_id = $pkgs->add(
    name            => 'cavil-folding-lab',
    checkout_dir    => $lab_checkout,
    api_url         => 'https://api.opensuse.org',
    requesting_user => $user_id,
    project         => 'cavil:staging',
    package         => 'cavil-folding-lab',
    srcmd5          => $lab_checkout,
    priority        => 5
  );
  $pkgs->imported($lab_id);
  my $lab = $pkgs->find($lab_id);
  $lab->{external_link} = 'obs#folding-lab';
  $pkgs->update($lab);
  $pkgs->unpack($lab_id);

  $app->{staging_folding_lab} = {
    package   => $lab_id,
    fold_low  => $fold_low->{id},
    fold_max  => $fold_max->{id},
    fold_high => $fold_high->{id},
    overlap   => $overlap->{id},
    guarded   => $guarded->{id},
    inside    => $inside->{id},
    covering  => $covering->{id}
  };

  # Synthetic vendored-subcomponent playground: several ecosystems bundled inside a source archive at
  # obscured, deeply-nested paths, so it shows detection working the way it has to in the wild. Also
  # includes a declared-but-not-vendored dev dependency (must be excluded) and a module whose metadata
  # omits the license (must be backfilled from Cavil's own scan). Detection runs during the normal index
  # below - no extra setup needed.
  my $comp_checkout = 'componentslab00000000000000000001';
  my $comp_dir      = $checkouts->child('components-lab', $comp_checkout)->make_path;

  # The delivered source archive: every member is a real vendored module's own metadata file, under
  # obscured directory names a packaging tool might produce
  my $tar     = Archive::Tar->new;
  my $root    = 'components-lab-1.0';
  my %members = (

    # root project manifest declaring a dev tool that is NOT vendored (must not be reported)
    'app/package.json' =>
      '{"name": "components-lab-app", "version": "1.0.0", "license": "MIT", "devDependencies": {"eslint": "^9"}}',

    # npm (plain + scoped) buried under an obscured cpio-style directory name
    'app/lib/node_modules.obscpio._/package._1/package.json' =>
      '{"name": "react", "version": "18.2.0", "license": "MIT"}',
    'app/lib/node_modules.obscpio._/package._2/package.json' =>
      '{"name": "@vue/runtime-core", "version": "3.4.0", "license": "MIT"}',

    # npm whose metadata omits the license -> backfilled from Cavil's scan of its LICENSE
    'app/lib/node_modules.obscpio._/package._3/package.json' => '{"name": "left-pad", "version": "1.3.0"}',
    'app/lib/node_modules.obscpio._/package._3/LICENSE'      => "Components lab distinctive backfill license phrase.\n",

    # Rust crate under an obscured vendor directory
    'vendor.obscpio_/serde-1.0.197/Cargo.toml' =>
      qq([package]\nname = "serde"\nversion = "1.0.197"\nlicense = "MIT OR Apache-2.0"\n),

    # Go: one modules.txt enumerates the whole vendored set
    'thirdparty._/vendor/modules.txt' =>
      "# github.com/gorilla/mux v1.8.1\n## explicit; go 1.20\ngithub.com/gorilla/mux\n"
      . "# golang.org/x/sys v0.16.0\n## explicit\ngolang.org/x/sys/unix\n",

    # Java: Maven coordinates embedded in a bundled jar
    'java._/BOOT-INF/lib/guava.jar._/META-INF/maven/com.google.guava/guava/pom.properties' =>
      "groupId=com.google.guava\nartifactId=guava\nversion=33.0.0-jre\n",

    # Python: installed distribution metadata
    'py._/site-packages/requests-2.31.0.dist-info/METADATA' =>
      "Metadata-Version: 2.1\nName: requests\nVersion: 2.31.0\nLicense: Apache-2.0\n"
  );
  $tar->add_data("$root/$_", $members{$_}) for sort keys %members;
  $tar->write($comp_dir->child('components-lab.tar.gz')->to_string, Archive::Tar::COMPRESS_GZIP);

  # Loose spec at the checkout root so the primary component gets a name/version/license
  $comp_dir->child('components-lab.spec')->spurt(<<'SPEC');
Name:           components-lab
Version:        1.0
Summary:        Playground demonstrating vendored subcomponent detection
License:        MIT
Url:            https://example.com/components-lab

%description
Bundles npm, Rust, Go, Java and Python modules under obscured directory names.
SPEC

  # A license pattern so the license-less npm module's license is backfilled from detection
  $app->patterns->create(
    pattern   => 'Components lab distinctive backfill license phrase',
    license   => 'MIT',
    unique_id => '22222222-2222-4222-8222-222222222221'
  );
  $app->pg->db->query('UPDATE license_patterns SET spdx = $1 WHERE license = $1', 'MIT');

  my $comp_id = $pkgs->add(
    name            => 'components-lab',
    checkout_dir    => $comp_checkout,
    api_url         => 'https://api.opensuse.org',
    requesting_user => $user_id,
    project         => 'cavil:staging',
    package         => 'components-lab',
    srcmd5          => $comp_checkout,
    priority        => 5
  );
  $pkgs->imported($comp_id);
  my $comp = $pkgs->find($comp_id);
  $comp->{external_link} = 'obs#components-lab';
  $pkgs->update($comp);
  $pkgs->unpack($comp_id);

  # Synthetic diff playground: two versions of one package whose report diff
  # exercises every "why this needs review" block at once - a spec license
  # change, new unresolved matches across several files (enough to show the
  # five-file cap plus "+ N more", each name clickable), several new licenses by
  # risk, and a license incompatibility. Version 1 is accepted further below so
  # version 2 has an accepted previous review to diff against.
  $app->patterns->create(
    pattern   => 'diff lab mit license body',
    license   => 'MIT',
    risk      => 2,
    unique_id => '33333333-3333-4333-8333-333333333331'
  );
  $app->patterns->create(
    pattern   => 'diff lab apache license body',
    license   => 'Apache-2.0',
    risk      => 2,
    unique_id => '33333333-3333-4333-8333-333333333332'
  );
  $app->patterns->create(
    pattern   => 'diff lab gpl2 only license body',
    license   => 'GPL-2.0-only',
    risk      => 5,
    unique_id => '33333333-3333-4333-8333-333333333333'
  );
  $app->patterns->create(
    pattern   => 'diff lab strong copyleft license body',
    license   => 'GPL-3.0-or-later',
    risk      => 6,
    unique_id => '33333333-3333-4333-8333-333333333334'
  );
  $app->patterns->create(pattern => 'diff lab unresolved keyword', unique_id => '33333333-3333-4333-8333-333333333335');
  $app->pg->db->query('UPDATE license_patterns SET spdx = $1 WHERE license = $1', $_)
    for qw(MIT Apache-2.0 GPL-2.0-only GPL-3.0-or-later);

  my $diff_build = sub {
    my ($md5, $spec_license, $files) = @_;
    my $vdir = $checkouts->child('cavil-diff-lab', $md5)->make_path;
    $vdir->child('cavil-diff-lab.spec')->spurt(<<"SPEC");
Name:           cavil-diff-lab
Version:        1.0
Summary:        Playground demonstrating a rich report diff
License:        $spec_license

%description
Two versions of this package produce a diff that exercises every summary block.
SPEC
    $vdir->child($_)->spurt($files->{$_}) for sort keys %$files;
  };

  # Version 1: a single low-risk MIT file, accepted below
  $diff_build->('difflabv1000000000000000000000001', 'MIT', {'LICENSE.txt' => "diff lab mit license body\n"});

  # Version 2: a different spec license, three new licenses by risk (with an
  # incompatible pair), and eight brand-new unresolved keyword matches
  my %v2_files = (
    'apache.txt'          => "diff lab apache license body\n",
    'gpl2-only.txt'       => "diff lab gpl2 only license body\n",
    'strong-copyleft.txt' => "diff lab strong copyleft license body\n"
  );
  for my $i (1 .. 8) {
    $v2_files{sprintf 'unresolved_%02d.txt', $i}
      = sprintf
      "Synthetic diff-lab source file %d.\n\nDIFF_LAB_MARKER_%02d diff lab unresolved keyword appears here.\n\nTrailing context so the snippet renders.\n",
      $i, $i;
  }
  $diff_build->('difflabv2000000000000000000000002', 'Apache-2.0', \%v2_files);

  my $diff_v1_id = $pkgs->add(
    name            => 'cavil-diff-lab',
    checkout_dir    => 'difflabv1000000000000000000000001',
    api_url         => 'https://api.opensuse.org',
    requesting_user => $user_id,
    project         => 'cavil:staging',
    package         => 'cavil-diff-lab',
    srcmd5          => 'difflabv1000000000000000000000001',
    priority        => 5
  );
  $pkgs->imported($diff_v1_id);
  my $diff_v1 = $pkgs->find($diff_v1_id);
  $diff_v1->{external_link} = 'obs#diff-lab-1';
  $pkgs->update($diff_v1);
  $pkgs->unpack($diff_v1_id);

  $app->{staging_diff_lab} = {v1 => $diff_v1_id, v2_checkout => 'difflabv2000000000000000000000002'};
}

$app->minion->perform_jobs;

if (my $lab = $app->{staging_folding_lab}) {
  my $db     = $app->pg->db;
  my $pkg_id = $lab->{package};
  my $rows   = $db->query(
    'SELECT fs.id AS file_snippet, fs.file, fs.sline, s.id AS snippet, s.text
       FROM file_snippets fs JOIN snippets s ON s.id = fs.snippet WHERE fs.package = ?', $pkg_id
  );

  while (my $row = $rows->hash) {
    my ($pattern, $likelyness, $second) = ($lab->{fold_low}, 0.99, 0.1);
    if ($row->{text} =~ /FOLD_MAX_RISK/) {
      ($pattern, $likelyness, $second) = ($lab->{fold_max}, 0.99, 0.1);
    }
    elsif ($row->{text} =~ /NO_FOLD_HIGH_RISK/) {

      # Confident enough to fold (>= threshold) but a risk 6 license, so the fold risk gate blocks it;
      # kept just below clear_threshold (0.97) so boilerplate-clear does not sweep it up instead, which
      # is what makes the high-risk guard actually visible as an unresolved snippet.
      ($pattern, $likelyness, $second) = ($lab->{fold_high}, 0.96, 0.1);
    }
    elsif ($row->{text} =~ /CLEAR_BOILERPLATE/) {
      ($pattern, $likelyness, $second) = ($lab->{fold_low}, 0.99, 0.99);
    }
    elsif ($row->{text} =~ /OVERLAP_CLEAR/) {
      ($pattern, $likelyness, $second) = ($lab->{overlap}, 0.92, 0.4);
      $db->insert(
        'pattern_matches',
        {
          package => $pkg_id,
          file    => $row->{file},
          pattern => $lab->{overlap},
          sline   => $row->{sline},
          eline   => $row->{sline},
          ignored => 0
        }
      );
    }
    elsif ($row->{text} =~ /OVERLAP_GUARDED/) {
      ($pattern, $likelyness, $second) = ($lab->{guarded}, 0.92, 0.4);
      $db->insert(
        'pattern_matches',
        {
          package => $pkg_id,
          file    => $row->{file},
          pattern => $lab->{overlap},
          sline   => $row->{sline},
          eline   => $row->{sline},
          ignored => 0
        }
      );
    }
    elsif ($row->{text} =~ /FOLD_WITH_DIRECT_MATCH/) {
      ($pattern, $likelyness, $second) = ($lab->{fold_max}, 0.99, 0.1);
      $db->insert(
        'pattern_matches',
        {
          package => $pkg_id,
          file    => $row->{file},
          pattern => $lab->{inside},
          sline   => $row->{sline},
          eline   => $row->{sline},
          ignored => 0
        }
      );
    }
    elsif ($row->{text} =~ /COVERED_BY_DIR/) {

      # Below the fold and clear thresholds and with no overlapping match on its own line, so it only
      # resolves via directory-scope coverage: the sibling LICENSE (a real Fold-Lab-Covering match found
      # by indexing) carries a concrete risk-3 license, and this fragment's closest is lower risk.
      ($pattern, $likelyness, $second) = ($lab->{fold_low}, 0.7, 0.1);
    }

    $db->update(
      'snippets',
      {
        classified    => 1,
        license       => 1,
        confidence    => 100,
        likelyness    => $likelyness,
        second_match  => $second,
        score_version => SNIPPET_SCORE_VERSION,
        like_pattern  => $pattern
      },
      {id => $row->{snippet}}
    );
  }

  $app->snippets->resolve_snippets($pkg_id);
  $app->minion->enqueue(analyze => [$pkg_id]);
  $app->minion->perform_jobs;
}

if (my $diff = $app->{staging_diff_lab}) {
  my $pkgs    = $app->packages;
  my $user_id = $app->users->find(login => 'test_bot')->{id};

  # Accept version 1 so it becomes the closest previous review for version 2
  my $v1 = $pkgs->find($diff->{v1});
  $v1->{reviewing_user}   = $user_id;
  $v1->{result}           = 'Reviewed ok';
  $v1->{state}            = 'acceptable';
  $v1->{review_timestamp} = 1;
  $pkgs->update($v1);

  # Index version 2: its analyze step diffs against the accepted version 1 and
  # writes the rich "why this needs review" notice
  my $v2_id = $pkgs->add(
    name            => 'cavil-diff-lab',
    checkout_dir    => $diff->{v2_checkout},
    api_url         => 'https://api.opensuse.org',
    requesting_user => $user_id,
    project         => 'cavil:staging',
    package         => 'cavil-diff-lab',
    srcmd5          => $diff->{v2_checkout},
    priority        => 5
  );
  $pkgs->imported($v2_id);
  my $v2 = $pkgs->find($v2_id);
  $v2->{external_link} = 'obs#diff-lab-2';
  $pkgs->update($v2);
  $pkgs->unpack($v2_id);
  $app->minion->perform_jobs;
}

print <<"EOF";
Staging project created, use the CAVIL_CONF environment variable.

    CAVIL_CONF=$conf perl script/cavil

EOF

1;
