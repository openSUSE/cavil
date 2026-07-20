# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package Cavil;
use Mojo::Base 'Mojolicious', -signatures;

use Mojo::Pg;
use Cavil::Classifier;
use Cavil::Git;
use Cavil::Role qw(roles_with_capability);
use Cavil::Model::Notes;
use Cavil::Model::IgnoredFiles;
use Cavil::Model::Packages;
use Cavil::Model::Patterns;
use Cavil::Model::Products;
use Cavil::Model::Reports;
use Cavil::Model::Requests;
use Cavil::Model::Users;
use Cavil::Model::APIKeys;
use Cavil::Model::Snippets;
use Cavil::OBS;
use Cavil::SPDX;
use Cavil::Sync;
use Scalar::Util 'weaken';
use Mojo::File qw(path);

has classifier => sub { Cavil::Classifier->new };
has git        => sub { Cavil::Git->new };
has obs        => sub { Cavil::OBS->new };
has spdx       => sub ($self) {
  my $spdx = Cavil::SPDX->new(app => $self);
  weaken $spdx->{app};
  return $spdx;
};
has sync => sub ($self) {
  my $sync = Cavil::Sync->new(app => $self);
  weaken $sync->{app};
  return $sync;
};

our $VERSION = '1.029';

sub startup ($self) {

  my $file   = $ENV{CAVIL_CONF} || 'cavil.conf';
  my $config = $self->plugin(Config => {file => $file});
  $self->secrets($config->{secrets});

  if (my $classifier = $config->{classifier}) {
    $self->classifier->type($classifier->{type})->url($classifier->{url})->token($classifier->{token});
  }

  # Avoid huge temp files in "/tmp"
  $ENV{MOJO_TMPDIR} = $config->{tmp_dir} if $config->{tmp_dir};
  $self->max_request_size(262144000);

  # OBS/git configuration
  if (my $obs = $config->{obs}) { $self->obs->config($obs) }
  if (my $git = $config->{git}) { $self->git->config($git) }

  # Short logs for systemd
  $self->log->short(1) if $self->mode eq 'production';

  # Application specific commands
  push @{$self->commands->namespaces}, 'Cavil::Command';

  # Sessions last 14 days
  $self->sessions->default_expiration(1209600)->encrypted(1);

  $self->plugin('Cavil::Plugin::Helpers');

  # Webpack
  $self->plugin('Webpack');

  # Job queue (model)
  #
  #  Start a background worker (processes 4 jobs parallel by default)
  #  $ script/cavil minion worker
  #
  #  Start a background worker (process one job at a time)
  #  $ script/cavil minion worker -j 1
  #
  $self->helper(pg => sub { state $pg = Mojo::Pg->new($config->{pg})->max_connections(1) });
  $self->plugin(Minion => {Pg => $self->pg});
  $self->plugin('Cavil::Task::Classify');
  $self->plugin('Cavil::Task::Import');
  $self->plugin('Cavil::Task::Unpack');
  $self->plugin('Cavil::Task::Index');
  $self->plugin('Cavil::Task::Analyze');
  $self->plugin('Cavil::Task::Cleanup');
  $self->plugin('Cavil::Task::ClosestMatch');
  $self->plugin('Cavil::Task::SPDX');

  $self->plugin('Cavil::Plugin::Linux');

  my $mcp_action = $self->plugin('Cavil::Plugin::MCP');
  $self->types->type(mcp => 'text/plain;charset=utf-8');

  # Compress dynamically generated content
  $self->renderer->compress(1);

  # Model
  if (my $remove_after = $config->{minion_remove_after}) { $self->minion->remove_after($remove_after) }
  if (my $stuck_after  = $config->{minion_stuck_after})  { $self->minion->stuck_after($stuck_after) }
  $self->helper(
    packages => sub ($c) {
      state $pkgs = Cavil::Model::Packages->new(
        checkout_dir => $config->{checkout_dir},
        log          => $self->log,
        minion       => $self->minion,
        pg           => $c->pg
      );
    }
  );
  $self->helper(products => sub ($c) { state $pkgs = Cavil::Model::Products->new(pg => $c->pg) });
  $self->helper(
    reports => sub ($c) {
      state $reps = Cavil::Model::Reports->new(
        acceptable_risk    => $config->{acceptable_risk},
        checkout_dir       => $config->{checkout_dir},
        max_expanded_files => $config->{max_expanded_files},
        snippet_fold       => $config->{snippet_fold},
        pg                 => $c->pg
      );
    }
  );
  $self->helper(requests => sub ($c) { state $reqs  = Cavil::Model::Requests->new(pg => $c->pg) });
  $self->helper(users    => sub ($c) { state $users = Cavil::Model::Users->new(pg => $c->pg) });
  $self->helper(
    ignored_files => sub ($c) { state $pkgs = Cavil::Model::IgnoredFiles->new(pg => $c->pg, log => $self->log) });

  my $cache = path($config->{cache_dir})->make_path;
  $self->helper(
    patterns => sub ($c) {
      state $patterns
        = Cavil::Model::Patterns->new(cache => $cache, pg => $c->pg, minion => $c->minion, log => $c->app->log);
    }
  );

  $self->helper(
    snippets => sub ($c) {
      state $snips = Cavil::Model::Snippets->new(
        checkout_dir => $config->{checkout_dir},
        pg           => $c->pg,
        snippet_fold => $config->{snippet_fold}
      );
    }
  );

  $self->helper(api_keys => sub ($c) { state $keys = Cavil::Model::APIKeys->new(pg => $c->pg) });

  $self->helper(notes => sub ($c) { state $nts = Cavil::Model::Notes->new(pg => $c->pg) });

  # Migrations (do not run automatically, use the migrate command)
  #
  my $path = $self->home->child('migrations', 'cavil.sql');
  $self->pg->migrations->name('legalqueue_api')->from_file($path);

  # Authentication
  my $public    = $self->routes;
  my $bot       = $public->under('/')->to('Auth::Token#check');
  my $api_key   = $public->under('/')->to('Auth::APIKey#check');
  my $logged_in = $public->under('/' => {roles => []})->to('Auth#check');

  # Authorization is expressed by capability, not role: each gate accepts the roles that grant the
  # capability (see Cavil::Role and docs/Roles.md). "curate" is admin+lawyer, "infra" is admin only, so
  # a lawyer can do all curation but not run the machine.
  my $can_infra    = $public->under('/' => {roles => roles_with_capability('infra')})->to('Auth#check');
  my $can_curate   = $public->under('/' => {roles => roles_with_capability('curate')})->to('Auth#check');
  my $can_propose  = $public->under('/' => {roles => roles_with_capability('propose')})->to('Auth#check');
  my $can_review   = $public->under('/' => {roles => roles_with_capability('review')})->to('Auth#check');
  my $can_classify = $public->under('/' => {roles => roles_with_capability('classify')})->to('Auth#check');

  if (my $openid = $config->{openid}) {
    $self->plugin(
      OAuth2 => {
        providers => {
          opensuse => {
            key            => $openid->{key},
            secret         => $openid->{secret},
            scope          => 'openid email profile',
            well_known_url => $openid->{well_known_url}
          },
        },
      }
    );
    $public->get('/login' => sub ($c) { $c->redirect_to('openid') });
    $public->any(['GET', 'POST'] => '/oidc/callback')->to('Auth::OpenIDConnect#login')->name('openid');
  }
  else { $public->get('/login')->to('Auth::Dummy#login')->name('login') }
  $public->get('/logout')->to('Auth#logout')->name('logout');

  # Minion admin
  $self->plugin('Minion::Admin' => {route => $can_infra->any('/minion')});

  # API for Open Build Service bots
  $bot->get('/package/<id:num>')->to('Queue#package_status');
  $bot->patch('/package/<id:num>')->to('Queue#update_package');
  $bot->post('/packages')->to('Queue#create_package');
  $bot->post('/packages/import/<id:num>')->to('Queue#import_package');
  $bot->patch('/products/*name')->to('Queue#update_product');
  $bot->delete('/products')->to('Queue#remove_product');
  $bot->post('/requests')->to('Queue#create_request');
  $bot->get('/requests')->to('Queue#list_requests');
  $bot->delete('/requests')->to('Queue#remove_request');
  $bot->get('/package/<id:num>/report' => [format => ['json', 'txt']])->to('Report#report', format => 'json');

  # API for lawyer tools
  $bot->get('/source/<id:num>')->to('Report#source', format => 'json');

  # Public API (legacy)
  $public->get('/api/package/:name' => sub ($c) { $c->redirect_to('package_api') });
  $public->get('/api/1.0/identify/:name/:checksum')->to('API#identify')->name('identify_api');
  $public->get('/api/1.0/package/:name')->to('API#status')->name('package_api');
  $public->get('/api/1.0/source')->to('API#source')->name('source_api');

  # API with key
  $api_key->any('/mcp' => $mcp_action)->name('mcp');
  $api_key->get('/api/v1/whoami')->to('API#whoami')->name('whoami_api');
  $api_key->get('/api/v1/reports')->to('API#reports');
  $api_key->get('/api/v1/search')->to('API#package_search')->name('search_api');
  $api_key->get('/api/v1/report/<id:num>' => [format => ['json', 'txt', 'mcp']])->to('Report#report');
  $api_key->get('/api/v1/spdx/<id:num>')->to('Report#spdx');

  # API Keys
  $logged_in->get('/api_keys')->to('APIKeys#list')->name('list_api_keys');
  $logged_in->get('/api_keys/meta')->to('APIKeys#list_meta')->name('list_api_keys_meta');
  $logged_in->post('/api_keys')->to('APIKeys#create')->name('create_api_keys');
  $logged_in->delete('/api_keys/:id')->to('APIKeys#remove')->name('remove_api_keys');

  # Review UI
  $public->get('/')->to('Reviewer#list_reviews')->name('dashboard');
  $public->get('/search')->to('Search#search')->name('search');
  $public->get('/package/autocomplete')->to('Search#autocomplete')->name('package_autocomplete');
  $public->get('/pagination/search/*name' => {name => ''})
    ->to('Pagination#review_search')
    ->name('pagination_review_search');
  $public->get('/reviews/recent')->to('Reviewer#list_recent')->name('reviews_recent');
  $logged_in->get('/reviews/file_view/<id:num>/*file' => {file => ''})->to('Reviewer#file_view')->name('file_view');
  $logged_in->get('/reviews/file_view_meta/<id:num>/*file' => {file => ''})
    ->to('Reviewer#file_view_meta')
    ->name('file_view_meta');
  $logged_in->get('/reviews/details/<id:num>')->to('Reviewer#details')->name('package_details');
  $logged_in->get('/reviews/meta/<id:num>')->to('Reviewer#meta')->name('package_meta');
  $logged_in->get('/reviews/report/<id:num>' => [format => ['json', 'txt']])
    ->to('Report#report', format => 'json')
    ->name('report');
  $logged_in->get('/reviews/report_details/<id:num>')->to('Report#details')->name('report_details');
  $logged_in->get('/reviews/fetch_source/<id:num>' => [format => ['json']])->to('Report#source', format => 'json');
  $logged_in->get('/reviews/notes/recent'          => [format => ['html', 'json']])
    ->to('Notes#recent', format => 'html')
    ->name('recent_notes');
  $logged_in->get('/reviews/notes/tags' => [format => ['json']])->to('Notes#tags', format => 'json')->name('note_tags');
  $logged_in->get('/reviews/notes/<id:num>')->to('Notes#list')->name('list_notes');
  $logged_in->post('/reviews/notes/<id:num>')->to('Notes#create')->name('create_note');
  $logged_in->patch('/reviews/notes/<id:num>')->to('Notes#update')->name('update_note');
  $logged_in->delete('/reviews/notes/<id:num>')->to('Notes#remove')->name('remove_note');
  $logged_in->post('/reviews/notes/preview')->to('Notes#preview')->name('preview_note');
  $can_curate->post('/reviews/review_package/<id:num>')->to('Reviewer#review_package')->name('review_package');
  $can_review->post('/reviews/fasttrack_package/<id:num>')->to('Reviewer#fasttrack_package')->name('fasttrack_package');
  $can_curate->post('/reviews/reindex/<id:num>')->to('Reviewer#reindex_package')->name('reindex_package');
  $public->get('/pagination/reviews/open')->to('Pagination#open_reviews')->name('pagination_open_reviews');
  $public->get('/pagination/reviews/recent')->to('Pagination#recent_reviews')->name('pagination_recent_reviews');
  $logged_in->get('/spdx/<id:num>')->to('Report#spdx')->name('spdx_report');

  $public->get('/licenses')->to('License#list')->name('licenses');
  $public->get('/pagination/licenses/known')->to('Pagination#known_licenses')->name('pagination_known_licenses');
  $can_curate->get('/licenses/new_pattern')->to('License#new_pattern')->name('new_pattern');
  $can_curate->post('/licenses/create_pattern')->to('License#create_pattern')->name('create_pattern');
  $logged_in->get('/licenses/proposed')->to('License#proposed')->name('proposed_patterns');
  $logged_in->get('/licenses/missing')->to('License#missing')->name('missing_licenses');
  $logged_in->get('/licenses/proposed/stats')->to('License#proposal_stats')->name('proposed_patterns_stats');
  $logged_in->get('/licenses/proposed/meta')->to('License#proposed_meta')->name('proposed_patterns_meta');
  $logged_in->get('/licenses/recent')->to('License#recent')->name('recent_patterns');
  $logged_in->get('/licenses/recent/meta')->to('License#recent_meta')->name('recent_patterns_meta');

  $can_curate->get('/ignored-matches')->to('Ignore#list_matches')->name('list_ignored_matches');
  $can_curate->delete('/ignored-matches/<id:num>')->to('Ignore#remove_match')->name('remove_ignored_match');
  $can_curate->get('/pagination/matches/ignored')->to('Pagination#ignored_matches')->name('pagination_ignored_matches');

  $can_curate->get('/ignored-files')->to('Ignore#list_globs')->name('list_globs');
  $can_curate->post('/ignored-files')->to('Ignore#add_glob')->name('add_ignore');
  $can_curate->delete('/ignored-files/<id:num>')->to('Ignore#remove_glob')->name('remove_ignored_file');
  $can_curate->get('/pagination/files/ignored')->to('Pagination#ignored_files')->name('pagination_ignored_files');

  # Public because of fine grained access controls (owner of proposal may remove it again)
  $public->post('/licenses/proposed/remove/:checksum')->to('License#remove_proposal')->name('proposed_remove');

  $logged_in->get('/licenses/pattern/<id:num>.json')->to('License#pattern_detail')->name('pattern_detail');
  $can_curate->post('/licenses/pattern/<id:num>.json')->to('License#update_pattern_json')->name('update_pattern_json');
  $logged_in->get('/licenses/pattern/<id:num>/match_count.json')
    ->to('License#match_count_json')
    ->name('pattern_match_count');
  $public->get('/licenses/meta/*name' => {name => ''})->to('License#show_meta')->name('license_show_meta');
  $can_curate->post('/licenses/meta/*name' => {name => ''})
    ->to('License#update_patterns_json')
    ->name('update_patterns_json');
  $can_curate->get('/licenses/edit_pattern/<id:num>')->to('License#edit_pattern')->name('edit_pattern');
  $can_curate->post('/licenses/update_pattern/<id:num>')->to('License#update_pattern')->name('update_pattern');
  $can_curate->post('/licenses/update_patterns')->to('License#update_patterns')->name('update_patterns');
  $can_curate->delete('/licenses/remove_pattern/<id:num>')->to('License#remove_pattern')->name('remove_pattern');
  $public->get('/licenses/*name')->to('License#show')->name('license_show');

  $public->get('/products')->to('Product#list')->name('products');
  $public->get('/pagination/products/known')->to('Pagination#known_products')->name('pagination_known_products');
  $public->get('/products/*name')->to('Product#show')->name('product_show');
  $public->get('/pagination/products/*name')->to('Pagination#product_reviews')->name('pagination_product_reviews');

  $logged_in->get('/snippets')->to('Snippet#list')->name('snippets');
  $logged_in->get('/snippets/meta')->to('Snippet#list_meta')->name('snippets_meta');
  $can_classify->post('/snippets/<id:num>')->to('Snippet#approve')->name('approve_snippets');
  $logged_in->get('/snippet/edit/<id:num>')->to('Snippet#edit')->name('edit_snippet');
  $logged_in->get('/snippet/meta/<id:num>')->to('Snippet#meta')->name('snippet_meta');
  $logged_in->get('/snippet/smart_edit/<id:num>')->to('Snippet#smart_edit')->name('snippet_smart_edit');
  $public->post('/snippet/closest')->to('Snippet#closest')->name('snippet_closest');
  $can_propose->get('/snippets/from_file/:file/<start:num>/<end:num>')->to('Snippet#from_file')->name('new_snippet');
  $can_propose->post('/snippet/batch_decision')->to('Snippet#batch_decision')->name('snippet_batch_decision');

  $logged_in->get('/stats')->to('Stats#index')->name('stats');
  $logged_in->get('/stats/meta')->to('Stats#meta')->name('stats_meta');

  # Upload (experimental)
  $can_infra->get('/upload')->to('Upload#index')->name('upload');
  $can_infra->post('/upload')->to('Upload#store')->name('store_upload');
}

1;

=encoding utf8

=head1 NAME

Cavil - Legal Review System

=head1 SYNOPSIS

  use Cavil;

=head1 DESCRIPTION

L<Cavil> is a legal review system.

=head1 AUTHORS

Code:

=over 2

Sebastian Riedel, C<sriedel@suse.de>

Stephan Kulow, C<coolo@suse.de>
 
=back

License patterns:

=over 2

Ciaran Farrell, C<ciaran.farrell@suse.com>

Christopher De Nicolo, C<Christopher.DeNicolo@suse.com>

=back

=head1 COPYRIGHT AND LICENSE

 Copyright (C) 2018 SUSE Linux GmbH

 This program is free software; you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation; either version 2 of the License, or
 (at your option) any later version.

 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.

 You should have received a copy of the GNU General Public License along
 with this program; if not, see <http://www.gnu.org/licenses/>.

=cut
