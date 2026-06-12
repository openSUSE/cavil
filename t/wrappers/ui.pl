use Mojo::Base -strict, -signatures;

# Coverage
BEGIN {
  if ($ENV{TEST_WRAPPER_COVERAGE}) {
    require Devel::Cover;
    Devel::Cover->import;
  }
}

use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../../lib";

use Mojo::Server::Daemon;
use Mojo::File qw(curfile);
use Mojo::JSON qw(from_json to_json);
use Test::Mojo;
use Cavil::Test;
use Mojo::IOLoop;

my $cavil_test = Cavil::Test->new(online => $ENV{TEST_ONLINE}, schema => $ENV{JS_UI_SCHEMA} // 'js_ui_test');
my $daemon     = Mojo::Server::Daemon->new(listen => ['http://*?fd=3'], silent => 1);

my $app = Test::Mojo->new(Cavil => $cavil_test->default_config)->app;
$daemon->app($app);
$app->log->level('warn');
$cavil_test->ui_fixtures($app);
my %report_state_original;

sub _save_report_state ($c, $id) {
  my $db     = $c->app->pg->db;
  my $pkg    = $db->select('bot_packages', ['obsolete', 'state'], {id      => $id})->hash;
  my $report = $db->select('bot_reports',  'ldig_report',         {package => $id})->hash;

  $report_state_original{$id}
    //= {obsolete => $pkg->{obsolete}, state => $pkg->{state}, ldig_report => $report->{ldig_report}};
}

$app->routes->get(
  '/perform_jobs' => sub ($c) {
    $c->minion->perform_jobs;
    $c->render(text => '<div>done</div>');
  }
);

$app->routes->get(
  '/login_as_contributor' => sub ($c) {
    my $user = $c->users->find_or_create(
      login    => 'contrib_tester',
      email    => 'contrib_tester@example.com',
      fullname => 'Dummy Contributor User',
      roles    => ['contributor']
    );
    $c->session(user => $user->{login});
    $c->redirect_to('dashboard');
  }
);

$app->routes->get(
  '/test/obsolete_with_report/:id' => sub ($c) {
    my $id = $c->stash('id');
    _save_report_state($c, $id);

    $c->app->pg->db->update('bot_packages', {obsolete => 1, state => 'obsolete'}, {id => $id});
    $c->render(text => 'ok');
  }
);

$app->routes->get(
  '/test/obsolete_without_report/:id' => sub ($c) {
    my $id = $c->stash('id');
    _save_report_state($c, $id);

    my $db = $c->app->pg->db;
    $db->update('bot_packages', {obsolete => 1, state => 'obsolete'}, {id => $id});
    $db->update('bot_reports', {ldig_report => undef}, {package => $id});
    $c->render(text => 'ok');
  }
);

$app->routes->get(
  '/test/empty_report/:id' => sub ($c) {
    my $id = $c->stash('id');
    _save_report_state($c, $id);

    my $db     = $c->app->pg->db;
    my $report = from_json($db->select('bot_reports', 'ldig_report', {package => $id})->hash->{ldig_report});
    $report->{emails}                = {};
    $report->{expanded}              = {};
    $report->{files}                 = {};
    $report->{incompatible_licenses} = [];
    $report->{licenses}              = {};
    $report->{lines}                 = {};
    $report->{matching_globs}        = [];
    $report->{missed_files}          = {};
    $report->{missed_snippets}       = {};
    $report->{risks}                 = {};
    $report->{urls}                  = {};
    $db->update('bot_packages', {obsolete => 0, state => 'new'}, {id => $id});
    $db->update('bot_reports', {ldig_report => to_json($report)}, {package => $id});
    $c->render(text => 'ok');
  }
);

$app->routes->get(
  '/test/restore_report_state/:id' => sub ($c) {
    my $id       = $c->stash('id');
    my $original = delete $report_state_original{$id};
    return $c->render(text => 'nothing to restore', status => 404) unless $original;

    my $db = $c->app->pg->db;
    $db->update('bot_packages', {obsolete => $original->{obsolete}, state => $original->{state}}, {id => $id});
    $db->update('bot_reports', {ldig_report => $original->{ldig_report}}, {package => $id});
    $c->render(text => 'ok');
  }
);

$app->routes->get('/test/restore_obsolete_without_report/:id' =>
    sub ($c) { $c->redirect_to('/test/restore_report_state/' . $c->stash('id')) });

$daemon->run;
