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

done_testing;
