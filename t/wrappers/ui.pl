use Mojo::Base -strict;

use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../../lib";

use Mojo::Server::Daemon;
use Mojo::File qw(curfile);
use Test::Mojo;
use Cavil::Test;

my $cavil_test = Cavil::Test->new(online => $ENV{TEST_ONLINE}, schema => 'js_ui_test');
my $daemon     = Mojo::Server::Daemon->new(listen => ['http://*?fd=3'], silent => 1);

my $app = Test::Mojo->new(Cavil => $cavil_test->default_config)->app;
$daemon->app($app);
$app->log->level('debug');
$cavil_test->ui_fixtures($app);

$daemon->run;
