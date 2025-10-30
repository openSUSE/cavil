use Mojo::Base -strict;

use FindBin;
use lib "$FindBin::Bin/../lib";
use Mojo::File qw(curfile path);
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
  acceptable_risk      => 3,
  index_bucket_average => 100,
  cleanup_bucket_average => 50,
  min_files_short_report => 20,
  max_email_url_size   => 2048,
  max_task_memory      => 5_000_000_000,
  max_worker_rss       => 100000,
  max_expanded_files   => 100
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

  # Extra packages to fill up the backlog
  for my $i (1 .. 21) {
    my $pkg_id = $pkgs->add(
      name            => "just-a-test-$i.0",
      checkout_dir    => '404fdab0e71b0bebfdf8b2dc3badf404',
      api_url         => 'https://api.opensuse.org',
      requesting_user => $user_id,
      project         => 'home:kraih',
      package         => "just-a-test-$i.0",
      srcmd5          => '4041c36647a5d3dd883d490da2140404',
      priority        => 5
    );
    my $pkg = $pkgs->find($pkg_id);
    $pkg->{external_link} = "test#$i";
    $pkgs->update($pkg);
  }

  # Update products
  my $products   = $app->products;
  my $factory_id = $products->find_or_create('openSUSE:Factory')->{id};
  my $leap_id    = $products->find_or_create('openSUSE:Leap:15.0')->{id};
  $products->update($factory_id, [$mojo_id]);
  $products->update($leap_id,    [$mojo_id]);
}

$app->minion->perform_jobs;

print <<"EOF";
Staging project created, use the CAVIL_CONF environment variable.

    CAVIL_CONF=$conf perl script/cavil

EOF

1;
