use Mojo::Base -strict;

use FindBin;
use lib "$FindBin::Bin/../lib";
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
  secrets              => ['just_a_test'],
  checkout_dir         => '$checkouts',
  cache_dir            => '$cache',
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
    overlap_guard   => 0.9
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
    'OVERLAP_GUARDED',
    'This snippet overlaps one license but strongly resembles a different one.',
    'The guard should keep it unresolved for human review.'
  );
  $block->(
    'FOLD_WITH_DIRECT_MATCH',
    'This folded region also has a real curated match on its first line.',
    'The real match should win on that line and the fold should color the rest.'
  );
  $lab_dir->child('folding-lab.txt')->spurt(join '', @blocks);

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
    inside    => $inside->{id}
  };
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
      ($pattern, $likelyness, $second) = ($lab->{fold_high}, 0.99, 0.1);
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

print <<"EOF";
Staging project created, use the CAVIL_CONF environment variable.

    CAVIL_CONF=$conf perl script/cavil

EOF

1;
