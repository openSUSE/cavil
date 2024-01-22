# Copyright (C) 2018-2022 SUSE LLC
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, see <http://www.gnu.org/licenses/>.

package Cavil;
use Mojo::Base 'Mojolicious', -signatures;

use Mojo::Pg;
use Cavil::Classifier;
use Cavil::Model::Packages;
use Cavil::Model::Patterns;
use Cavil::Model::Products;
use Cavil::Model::Reports;
use Cavil::Model::Requests;
use Cavil::Model::Users;
use Cavil::Model::Snippets;
use Cavil::OBS;
use Cavil::SPDX;
use Cavil::Sync;
use Scalar::Util 'weaken';
use Mojo::File qw(path);

has classifier => sub { Cavil::Classifier->new };
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

our $VERSION = '1.006';

sub startup ($self) {

  my $file   = $ENV{CAVIL_CONF} || 'cavil.conf';
  my $config = $self->plugin(Config => {file => $file});
  $self->secrets($config->{secrets});

  $self->classifier->url($config->{classifier});

  # Avoid huge temp files in "/tmp"
  $ENV{MOJO_TMPDIR} = $config->{tmp_dir} if $config->{tmp_dir};
  $self->max_request_size(262144000);

  # Optional OBS credentials
  if (my $obs = $config->{obs}) {
    $self->obs->user($obs->{user})       if $obs->{user};
    $self->obs->ssh_key($obs->{ssh_key}) if $obs->{ssh_key};
  }

  # Short logs for systemd
  $self->log->short(1) if $self->mode eq 'production';

  # Application specific commands
  push @{$self->commands->namespaces}, 'Cavil::Command';

  # Sessions last 14 days
  $self->sessions->default_expiration(1209600);

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
        pg                 => $c->pg
      );
    }
  );
  $self->helper(requests => sub ($c) { state $reqs  = Cavil::Model::Requests->new(pg => $c->pg) });
  $self->helper(users    => sub ($c) { state $users = Cavil::Model::Users->new(pg => $c->pg) });

  my $cache = path($config->{cache_dir})->make_path;
  $self->helper(
    patterns => sub ($c) {
      state $patterns
        = Cavil::Model::Patterns->new(cache => $cache, pg => $c->pg, minion => $c->minion, log => $c->app->log);
    }
  );

  $self->helper(snippets => sub ($c) { state $snips = Cavil::Model::Snippets->new(pg => $c->pg) });

  # Migrations (do not run automatically, use the migrate command)
  #
  my $path = $self->home->child('migrations', 'cavil.sql');
  $self->pg->migrations->name('legalqueue_api')->from_file($path);

  # Authentication
  my $public     = $self->routes;
  my $bot        = $public->under('/')->to('Auth::Token#check');
  my $manager    = $public->under('/' => {role => 'manager'})->to('Auth#check');
  my $admin      = $public->under('/' => {role => 'admin'})->to('Auth#check');
  my $classifier = $public->under('/' => {role => 'classifier'})->to('Auth#check');
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
  $self->plugin('Minion::Admin' => {route => $admin->any('/minion')});

  # API
  $bot->get('/package/<id:num>')->to('Queue#package_status');
  $bot->patch('/package/<id:num>')->to('Queue#update_package');
  $bot->post('/packages')->to('Queue#create_package');
  $bot->post('/packages/import/<id:num>')->to('Queue#import_package');
  $bot->patch('/products/*name')->to('Queue#update_product');
  $bot->post('/requests')->to('Queue#create_request');
  $bot->get('/requests')->to('Queue#list_requests');
  $bot->delete('/requests')->to('Queue#remove_request');
  $bot->get('/package/<id:num>/report')->to('Report#calc', format => 'json');
  $bot->get('/source/<id:num>')->to('Report#source', format => 'json');

  # Public API
  $public->get('/api/package/:name' => sub ($c) { $c->redirect_to('package_api') });
  $public->get('/api/1.0/package/:name')->to('API#status')->name('package_api');
  $public->get('/api/1.0/source')->to('API#source')->name('source_api');

  # Review UI
  $public->get('/')->to('Reviewer#list_reviews')->name('dashboard');
  $public->get('/search')->to('Search#search')->name('search');
  $public->get('/pagination/search/*name')->to('Pagination#review_search')->name('pagination_review_search');
  $public->get('/reviews/recent')->to('Reviewer#list_recent')->name('reviews_recent');
  $manager->get('/reviews/file_view/<id:num>/*file')->to('Reviewer#file_view')->name('file_view');
  $public->get('/reviews/details/<id:num>')->to('Reviewer#details')->name('package_details');
  $public->get('/reviews/meta/<id:num>')->to('Reviewer#meta')->name('package_meta');
  $public->get('/reviews/calc_report/<id:num>' => [format => ['json', 'html']])->to('Report#calc', format => 'html')
    ->name('calc_report');
  $public->get('/reviews/fetch_source/<id:num>' => [format => ['json', 'html']])->to('Report#source', format => 'html');
  $admin->post('/reviews/review_package/<id:num>')->to('Reviewer#review_package')->name('review_package');
  $manager->post('/reviews/fasttrack_package/<id:num>')->to('Reviewer#fasttrack_package')->name('fasttrack_package');
  $admin->post('/reviews/add_ignore')->to('Reviewer#add_ignore');
  $admin->post('/reviews/add_glob')->to('Reviewer#add_glob')->name('add_glob');
  $admin->post('/reviews/reindex/<id:num>')->to('Reviewer#reindex_package')->name('reindex_package');
  $public->get('/pagination/reviews/open')->to('Pagination#open_reviews')->name('pagination_open_reviews');
  $public->get('/pagination/reviews/recent')->to('Pagination#recent_reviews')->name('pagination_recent_reviews');
  $public->get('/spdx/<id:num>')->to('Report#spdx')->name('spdx_report');

  $public->get('/licenses')->to('License#list')->name('licenses');
  $public->get('/pagination/licenses/known')->to('Pagination#known_licenses')->name('pagination_known_licenses');
  $admin->get('/licenses/new_pattern')->to('License#new_pattern')->name('new_pattern');
  $admin->post('/licenses/new_pattern')->to('License#new_pattern');
  $admin->post('/licenses/create_pattern')->to('License#create_pattern')->name('create_pattern');

  $admin->get('/licenses/edit_pattern/<id:num>')->to('License#edit_pattern')->name('edit_pattern');
  $admin->post('/licenses/update_pattern/<id:num>')->to('License#update_pattern')->name('update_pattern');
  $admin->post('/licenses/update_patterns')->to('License#update_patterns')->name('update_patterns');
  $admin->delete('/licenses/remove_pattern/<id:num>')->to('License#remove_pattern')->name('remove_pattern');
  $public->get('/licenses/*name')->to('License#show')->name('license_show');

  $public->get('/products')->to('Product#list')->name('products');
  $public->get('/pagination/products/known')->to('Pagination#known_products')->name('pagination_known_products');
  $public->get('/products/*name')->to('Product#show')->name('product_show');
  $public->get('/pagination/products/*name')->to('Pagination#product_reviews')->name('pagination_product_reviews');

  $public->get('/snippets')->to('Snippet#list')->name('snippets');
  $public->get('/snippets/meta')->to('Snippet#meta')->name('snippets_meta');
  $classifier->post('/snippets/<id:num>')->to('Snippet#approve')->name('approve_snippets');
  $public->get('/snippet/edit/<id:num>')->to('Snippet#edit')->name('edit_snippet');
  $public->get('/snippets/from_file/:file/<start:num>/<end:num>')->to('Snippet#from_file')->name('new_snippet');
  $admin->post('/snippet/decision/<id:num>')->to('Snippet#decision')->name('snippet_decision');
  $public->get('/snippets/top')->to('Snippet#top')->name('top_snippets');

  # Upload (experimental)
  $admin->get('/upload')->to('Upload#index')->name('upload');
  $admin->post('/upload')->to('Upload#store')->name('store_upload');

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
