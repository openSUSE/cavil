use Mojo::Base -strict;

use Test::More;
use File::Copy 'copy';
use Mojo::File qw(path tempdir);
use Mojo::JSON 'decode_json';
use Cavil::Checkout;
use Mojo::Util 'dumper';

my $dir = path(__FILE__)->dirname->child('legal-bot');

sub temp_copy {
  my $from   = $dir->child(@_);
  my $target = tempdir;
  copy "$_", $target->child($_->basename) for $from->list->each;
  return $target;
}

# "gnome-icon-theme"
my $pwll = temp_copy('package-with-long-lines',
  '677dca225770d164778fd08123af89e960b8bd0d');
my $processor = Cavil::PostProcess->new(
  {destdir => $pwll, unpacked => {'README.md' => {mime => 'text/plain'}}});
$processor->postprocess;
is_deeply $processor->hash,
  {
  destdir  => $pwll,
  unpacked => {'README.processed.md' => {mime => 'text/plain'}}
  },
  'maxed';

is $pwll->child('README.processed.md')->slurp,
  $pwll->child('README.shortened')->slurp, 'Correctly split';

my $pwt = temp_copy('package-with-translations',
  '96d268b759eb1e18a63a95a2c622ab47d5c34f23');
$processor = Cavil::PostProcess->new(
  {
    destdir  => $pwt,
    unpacked => {
      'test.po'      => {mime => 'text/x-po'},
      'package.spec' => {mime => 'text/plain'}
    }
  }
);
$processor->postprocess;
is_deeply $processor->hash,
  {
  destdir  => $pwt,
  unpacked => {
    'test.processed.po'      => {mime => 'text/x-po'},
    'package.processed.spec' => {mime => 'text/plain'},
  }
  },
  'striped';

is $pwt->child('test.processed.po')->slurp,
  $pwt->child('test.stripped')->slurp, 'Correctly stripped msgid';
is $pwt->child('package.processed.spec')->slurp,
  $pwt->child('package.stripped')->slurp, 'Correctly stripped spec file';

done_testing;
