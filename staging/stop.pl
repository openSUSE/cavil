use Mojo::Base -strict;

use FindBin;
use lib "$FindBin::Bin/../lib";
use Mojo::File 'path';
use Mojo::Pg;
use Mojo::Server;

my $dir  = path(__FILE__)->sibling('do_not_commit');
my $conf = $dir->child('cavil.conf');
die "Staging project already cleaned up.\n" unless -f $conf;

local $ENV{CAVIL_CONF} = "$conf";
my $app = Mojo::Server->new->build_app('Cavil');
$app->pg->db->query('drop schema cavil_staging cascade');
$dir->remove_tree;
say 'Staging project cleaned up.';

1;
