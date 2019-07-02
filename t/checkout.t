use Mojo::Base -strict;

use Test::More;
use File::Copy 'copy';
use Mojo::File qw(path tempdir);
use Mojo::JSON 'decode_json';
use Cavil::Checkout;
use Mojo::Util 'dumper';

my $dir = path(__FILE__)->dirname->child('legal-bot');

sub report {
  my $report = eval path(__FILE__)->dirname->child('reports', shift)->slurp;
  return $@ ? die $@ : $report;
}

sub temp_copy {
  my $from   = $dir->child(@_);
  my $target = tempdir;
  copy "$_", $target->child($_->basename) for $from->list->each;
  return $target;
}

# "gnome-icon-theme"
my $theme = $dir->child('gnome-icon-theme', '6101f5eb933704aaad5dea63667110ac');
my $checkout = Cavil::Checkout->new($theme);
is_deeply $checkout->specfile_report, report('gnome-icon-theme.specfile'),
  'right specfile report';

# "gnome-menus"
my $menus = $dir->child('gnome-menus', 'aaacabb87b4356ac167f1a19458bc412');
$checkout = Cavil::Checkout->new($menus);
is_deeply $checkout->specfile_report, report('gnome-menus.specfile'),
  'right specfile report';

# "gtk-vnc"
my $vnc = $dir->child('gtk-vnc', 'dbc35628c22fb9537a187e338c5e7007');
$checkout = Cavil::Checkout->new($vnc);
is_deeply $checkout->specfile_report, report('gtk-vnc.specfile'),
  'right specfile report';

# "kmod"
my $kmod = $dir->child('kmod', 'a91003b451a34fe24defecdde1f2902e');
$checkout = Cavil::Checkout->new($kmod);
is_deeply $checkout->specfile_report, report('kmod.specfile'),
  'right specfile report';

# "libqt4"
my $qt = $dir->child('libqt4', '9ec277c8a213f76119aa737e98f01959');
$checkout = Cavil::Checkout->new($qt);
is_deeply $checkout->specfile_report, report('libqt4.specfile'),
  'right specfile report';

# "mono-core"
my $mono = $dir->child('mono-core', '610dad1a6b8dd8e36b021ab0291cd1d9');
$checkout = Cavil::Checkout->new($mono);
is_deeply $checkout->specfile_report, report('mono-core.specfile'),
  'right specfile report';

# "perl-Mojolicious"
my $mojo = $dir->child('perl-Mojolicious', 'c7cfdab0e71b0bebfdf8b2dc3badfecd');
$checkout = Cavil::Checkout->new($mojo);
is_deeply $checkout->specfile_report, report('perl-Mojolicious.specfile'),
  'right specfile report';
my $mojo_temp_dir
  = temp_copy('perl-Mojolicious', 'c7cfdab0e71b0bebfdf8b2dc3badfecd');
$checkout = Cavil::Checkout->new($mojo_temp_dir);
$checkout->unpack;
my $json = $mojo_temp_dir->child('.unpacked.json');
ok -f $json, 'log file exists';
my $hash = decode_json($json->slurp);
is $hash->{destdir}, $mojo_temp_dir->child('.unpacked'), 'right destination';
is $hash->{pid}, $$, 'right process id';
is_deeply $hash->{unpacked}{'Mojolicious-7.25/LICENSE'},
  {mime => 'text/plain'}, 'right structure';
ok -f $mojo_temp_dir->child('.unpacked', 'Mojolicious-7.25', 'LICENSE'),
  'license file exists';
my $module = $mojo_temp_dir->child('.unpacked', 'Mojolicious-7.25', 'lib',
  'Mojolicious.pm');
ok -f $module, 'module exists';

# check post processed
$json = $mojo_temp_dir->child('.postprocessed.json');
ok -f $json, '2nd log file exists';
$hash = decode_json($json->slurp);

my $maxed_file = 'Mojolicious-7.25/README.processed.md';
is_deeply $hash->{unpacked}->{$maxed_file}, {mime => 'text/plain'},
  'file was maxed';

# "plasma-nm5"
my $nm5 = $dir->child('plasma-nm5', '4df243e211552e65b7146523c2f7051c');
$checkout = Cavil::Checkout->new($nm5);
is_deeply $checkout->specfile_report, report('plasma-nm5.specfile'),
  'right specfile report';

# "timezone"
my $tz = $dir->child('timezone', '2724cdf3fada2aba427132fee8327b0f');
$checkout = Cavil::Checkout->new($tz);
is_deeply $checkout->specfile_report, report('timezone.specfile'),
  'right specfile report';

# "wxWidgets-3_2"
my $wx = $dir->child('wxWidgets-3_2', '25014ee9d3640ebd9bc2370a2bbb5a63');
$checkout = Cavil::Checkout->new($wx);
is_deeply $checkout->specfile_report, report('wxWidgets-3_2.specfile'),
  'right specfile report';

# "error-invalid-license"
my $eil
  = $dir->child('error-invalid-license', 'cb5e100e5a9a3e7f6d1fd97512215282');
$checkout = Cavil::Checkout->new($eil);
is_deeply $checkout->specfile_report, report('error-invalid-license.specfile'),
  'right specfile report';

# "error-no-spdx"
my $ens = $dir->child('error-no-spdx', 'cb5e100e5a9a3e7f6d1fd97512215282');
$checkout = Cavil::Checkout->new($ens);
is_deeply $checkout->specfile_report, report('error-no-spdx.specfile'),
  'right specfile report';

# "error-missing-main"
my $emm = $dir->child('error-missing-main', 'cb5e100e5a9a3e7f6d1fd97512215282');
$checkout = Cavil::Checkout->new($emm);
is_deeply $checkout->specfile_report, report('error-missing-main.specfile'),
  'right specfile report';

# "error-missing-specfile"
my $ems
  = $dir->child('error-missing-specfile', 'cb5e100e5a9a3e7f6d1fd97512215282');
$checkout = Cavil::Checkout->new($ems);
is_deeply $checkout->specfile_report,
  report('error-missing-specfile.specfile'), 'right specfile report';

# "error-broken-archive"
my $eba = temp_copy('error-broken-archive', 'cb5e100e5a9a3e7f6d1fd97512215282');
$checkout = Cavil::Checkout->new($eba);
$checkout->unpack;
$json = $eba->child('.unpacked.json');
ok -f $json, 'log file exists';
$hash = decode_json($json->slurp);
is $hash->{destdir}, $eba->child('.unpacked'), 'right destination';
is $hash->{pid}, $$, 'right process id';
is_deeply $hash->{unpacked}{'error-broken-archive/test.txt'},
  {mime => 'text/plain'}, 'right structure';

done_testing;
