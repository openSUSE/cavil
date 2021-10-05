use Mojo::Base -strict;

use FindBin;
use lib "$FindBin::Bin/../lib";
use Mojo::File qw(curfile path);
use Mojo::Pg;
use Mojo::Server;

my $dir = path(__FILE__)->sibling('do_not_commit');
die "Staging project already exists.\n" if -e $dir;

die <<'EOF' unless my $postgres = shift;
PostgreSQL connection string required. You need an already existing but empty
database, and we will create seed data for you.

    perl staging/start.pl postgresql://tester:testing@/test

EOF
my $pg = Mojo::Pg->new($postgres);
$pg->db->query('drop schema if exists cavil_staging cascade');
$pg->db->query('create schema cavil_staging');

$dir->make_path;
my $checkouts = $dir->child('legal-bot')->make_path->realpath;
my $cache     = $dir->child('cache')->make_path->realpath;

# Test checkouts
my $tests
  = [['perl-Mojolicious', 'c7cfdab0e71b0bebfdf8b2dc3badfecd'], ['ceph-image', '5fcfdab0e71b0bebfdf8b5cc3badfecf']];
for my $co (@$tests) {
  my $checkout = $checkouts->child(@$co)->make_path;
  my $test     = $dir->child('..', '..', 't', 'legal-bot', @$co)->realpath;
  $_->copy_to($checkout->child($_->basename)) for $test->list->each;
}

# Second copy of perl-Mojolicious test checkout (different checksum but same content)
my $test = $dir->child('..', '..', 't', 'legal-bot', 'perl-Mojolicious', 'c7cfdab0e71b0bebfdf8b2dc3badfecd')->realpath;
my $checkout = $checkouts->child('perl-Mojolicious', 'c7cfdab0e71b0bebfdf8b2dc3bad1234')->make_path;
$_->copy_to($checkout->child($_->basename)) for $test->list->each;

my $online = Mojo::URL->new($postgres)->query([search_path => ['cavil_staging', 'public']])->to_unsafe_string;
my $conf   = $dir->child('cavil.conf')->spurt(<<"EOF");
{
  secrets              => ['just_a_test'],
  checkout_dir         => '$checkouts',
  cache_dir            => '$cache',
  tokens               => [],
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
$app->sync->load(curfile->dirname->sibling('lib', 'Cavil', 'resources', 'license_patterns')->to_string);

# "perl-Mojolicious" example data
my $user_id = $app->users->find_or_create(login => 'test_bot')->{id};
my $pkgs    = $app->packages;
my $pkg_id  = $pkgs->add(
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

$app->minion->perform_jobs;

# Update products
my $products   = $app->products;
my $factory_id = $products->find_or_create('openSUSE:Factory')->{id};
my $leap_id    = $products->find_or_create('openSUSE:Leap:15.0')->{id};
$products->update($factory_id, [$pkg_id]);
$products->update($leap_id,    [$pkg_id]);

print <<"EOF";
Staging project created, use the CAVIL_CONF environment variable.

    CAVIL_CONF=$conf perl script/cavil

EOF

1;
