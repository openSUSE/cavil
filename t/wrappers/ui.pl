use Mojo::Base -strict, -signatures;

use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../../lib";

use Mojo::Server::Daemon;
use Mojo::File qw(curfile);
use Test::Mojo;
use Cavil::Test;
use Mojo::IOLoop;

my $cavil_test = Cavil::Test->new(online => $ENV{TEST_ONLINE}, schema => 'js_ui_test');
my $daemon     = Mojo::Server::Daemon->new(listen => ['http://*?fd=3'], silent => 1);

my $app = Test::Mojo->new(Cavil => $cavil_test->default_config)->app;
$daemon->app($app);
$app->log->level('warn');
$cavil_test->ui_fixtures($app);

$app->routes->get(
  '/perform_jobs' => sub ($c) {
    $c->minion->perform_jobs;
    $c->render(text => 'done');
  }
);

$daemon->run;
