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

# Optional fixture selection (default: the full UI fixtures). The snippet-fold/clear sets also need
# the feature switched on in the app config.
my $fixtures = $ENV{JS_UI_FIXTURES} // 'default';
my $config   = $cavil_test->default_config;
$config->{snippet_fold} = {enabled => 1, threshold => 0.9, min_margin => 0.1, max_risk => 9}
  if $fixtures eq 'snippet_fold';
$config->{snippet_fold} = {enabled => 1, threshold => 0.95, min_margin => 0.15, max_risk => 5, clear_threshold => 0.95}
  if $fixtures eq 'snippet_clear';
$config->{snippet_fold} = {enabled => 1, threshold => 0.95, min_margin => 0.15, max_risk => 5, clear_threshold => 0.95}
  if $fixtures eq 'snippet_triage';
$config->{snippet_fold}
  = {enabled => 1, threshold => 0.95, min_margin => 0.15, max_risk => 5, overlap_clear => 1, overlap_guard => 0.9}
  if $fixtures eq 'snippet_overlap';

my $app = Test::Mojo->new(Cavil => $config)->app;
$daemon->app($app);
$app->log->level('warn');
if    ($fixtures eq 'snippet_fold')    { $cavil_test->snippet_fold_fixtures($app) }
elsif ($fixtures eq 'snippet_clear')   { $cavil_test->snippet_clear_fixtures($app) }
elsif ($fixtures eq 'snippet_triage')  { $cavil_test->snippet_triage_fixtures($app) }
elsif ($fixtures eq 'snippet_overlap') { $cavil_test->snippet_overlap_fixtures($app) }
elsif ($fixtures eq 'report_notice')   { $cavil_test->report_notice_fixtures($app) }
else                                   { $cavil_test->ui_fixtures($app) }
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
