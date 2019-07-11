# Copyright (C) 2018 SUSE Linux GmbH
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
use Mojo::Base 'Mojolicious';

use Mojo::Pg;
use Cavil::Bootstrap;
use Cavil::Classifier;
use Cavil::Model::Licenses;
use Cavil::Model::Packages;
use Cavil::Model::Patterns;
use Cavil::Model::Products;
use Cavil::Model::Reports;
use Cavil::Model::Requests;
use Cavil::Model::Users;
use Cavil::Model::Snippets;
use Cavil::OBS;
use Scalar::Util 'weaken';
use Time::HiRes ();

has bootstrap => sub {
  my $self      = shift;
  my $bootstrap = Cavil::Bootstrap->new(app => $self);
  weaken $bootstrap->{app};
  return $bootstrap;
};
has classifier => sub { Cavil::Classifier->new };
has obs        => sub { Cavil::OBS->new };

our $VERSION = '0.5';

sub startup {
  my $self = shift;

  my $file   = $ENV{CAVIL_CONF} || 'cavil.conf';
  my $config = $self->plugin(Config => {file => $file});
  $self->secrets($config->{secrets});

  $self->classifier->url($config->{classifier});

  # Avoid huge temp files in "/tmp"
  $ENV{MOJO_TMPDIR} = $config->{tmp_dir} if $config->{tmp_dir};

  # Short logs for systemd
  if ($self->mode eq 'production') {
    $self->log->short(1);

    # All interesting log messages are "info" or higher
    $self->log->level('info');
    $self->hook(
      before_routes => sub {
        my $c = shift;

        my $req     = $c->req;
        my $method  = $req->method;
        my $url     = $req->url->to_abs->to_string;
        my $started = [Time::HiRes::gettimeofday];
        $c->tx->on(
          finish => sub {
            my $code    = shift->res->code;
            my $elapsed = Time::HiRes::tv_interval($started,
              [Time::HiRes::gettimeofday()]);
            my $rps = $elapsed == 0 ? '??' : sprintf '%.3f', 1 / $elapsed;
            $self->log->info(qq{$method $url -> $code (${elapsed}s, $rps/s)});
          }
        );
      }
    );
  }

  # Application specific commands
  push @{$self->commands->namespaces}, 'Cavil::Command';

  # Sessions last 14 days
  $self->sessions->default_expiration(1209600);

  $self->plugin('Cavil::Plugin::Helpers');

  $self->plugin(
    AssetPack => {pipes => [qw(Sass Css JavaScript Fetch Combine)]});
  $self->helper(
    icon_url => sub {
      my ($c, $icon) = @_;
      my $json = $c->app->asset->processed($icon)->[0]->TO_JSON;
      return $c->url_for(assetpack => $json);
    }
  );

  # Read "assets/assetpack.def"
  $self->asset->process;

  # Job queue (model)
  #
  #  Start a background worker (processes 4 jobs parallel by default)
  #  $ script/cavil minion worker
  #
  #  Start a background worker (process one job at a time)
  #  $ script/cavil minion worker -j 1
  #
  $self->helper(
    pg => sub { state $pg = Mojo::Pg->new($config->{pg})->max_connections(1) });
  $self->plugin(Minion => {Pg => $self->pg});
  $self->plugin('Cavil::Task::Classify');
  $self->plugin('Cavil::Task::Import');
  $self->plugin('Cavil::Task::Unpack');
  $self->plugin('Cavil::Task::Index');
  $self->plugin('Cavil::Task::Analyze');
  $self->plugin('Cavil::Task::Cleanup');
  $self->plugin('Cavil::Task::ClosestMatch');

  $self->plugin('Cavil::Plugin::Linux');
  $self->plugin('Cavil::Plugin::Compression');

  # Model
  $self->helper(
    packages => sub {
      state $pkgs = Cavil::Model::Packages->new(
        checkout_dir => $config->{checkout_dir},
        minion       => $self->minion,
        pg           => shift->pg
      );
    }
  );
  $self->helper(
    products => sub {
      state $pkgs = Cavil::Model::Products->new(pg => shift->pg);
    }
  );
  $self->helper(
    reports => sub {
      state $reps = Cavil::Model::Reports->new(
        acceptable_risk    => $config->{acceptable_risk},
        checkout_dir       => $config->{checkout_dir},
        max_expanded_files => $config->{max_expanded_files},
        pg                 => shift->pg
      );
    }
  );
  $self->helper(
    requests => sub {
      state $reqs = Cavil::Model::Requests->new(pg => shift->pg);
    }
  );
  $self->helper(
    users => sub {
      state $users = Cavil::Model::Users->new(pg => shift->pg);
    }
  );

  $self->helper(
    licenses => sub {
      state $lics = Cavil::Model::Licenses->new(pg => shift->pg);
    }
  );

  my $cache = $self->home->child('cache')->make_path;
  $self->helper(
    patterns => sub {
      my $self = shift;
      state $patterns = Cavil::Model::Patterns->new(
        cache => $cache,
        pg    => $self->pg,
        log   => $self->app->log
      );
    }
  );

  $self->helper(
    snippets => sub {
      state $snips = Cavil::Model::Snippets->new(pg => shift->pg);
    }
  );

  # Migrations (do not run automatically, use the migrate command)
  #
  my $path = $self->home->child('migrations', 'cavil.sql');
  $self->pg->migrations->name('legalqueue_api')->from_file($path);

  # Authentication
  my $public  = $self->routes;
  my $bot     = $public->under('/')->to('Auth::Token#check');
  my $manager = $public->under('/' => {role => 'manager'})->to('Auth#check');
  my $admin   = $public->under('/' => {role => 'admin'})->to('Auth#check');
  my $classifier
    = $public->under('/' => {role => 'classifier'})->to('Auth#check');
  if ($config->{openid}) {
    $public->get('/login')->to('Auth::OpenID#login')->name('login');
    $public->get('/openid')->to('Auth::OpenID#openid')->name('openid');
    $public->get('/response')->to('Auth::OpenID#response')->name('response');
  }
  else { $public->get('/login')->to('Auth::Dummy#login')->name('login') }
  $public->get('/logout')->to('Auth#logout')->name('logout');

  # Minion admin
  $self->plugin('Minion::Admin' => {route => $admin->any('/minion')});

  # API
  $bot->get('/package/:id')->to('Queue#package_status');
  $bot->patch('/package/:id')->to('Queue#update_package');
  $bot->post('/packages')->to('Queue#create_package');
  $bot->post('/packages/import/:id')->to('Queue#import_package');
  $bot->patch('/products/*name')->to('Queue#update_product');
  $bot->post('/requests')->to('Queue#create_request');
  $bot->get('/requests')->to('Queue#list_requests');
  $bot->delete('/requests')->to('Queue#remove_request');

  # Public API
  $public->get('/api/package/:name' => sub { shift->redirect_to('package_api') }
  );
  $public->get('/api/1.0/package/:name')->to('API#status')->name('package_api');
  $public->get('/api/1.0/source')->to('API#source')->name('source_api');

  # Review UI
  $public->get('/')->to('Reviewer#list_reviews')->name('dashboard');
  $public->get('/search')->to('Search#search')->name('search');
  $public->get('/reviews/list')->to('Reviewer#list_new_ajax')
    ->name('reviews_ajax');
  $public->get('/reviews/recent')->to('Reviewer#list_recent')
    ->name('reviews_recent');
  $public->get('/reviews/list_recent')->to('Reviewer#list_recent_ajax')
    ->name('reviews_recent_ajax');
  $public->get('/reviews/file_view/:id/*file')->to('Reviewer#file_view')
    ->name('file_view');
  $public->get('/reviews/details/:id')->to('Reviewer#details')
    ->name('package_details');
  $public->get('/reviews/calc_report/:id')->to('Reviewer#calc_report')
    ->name('calc_report');
  $public->post('/reviews/fetch_source/:id')->to('Reviewer#fetch_source');
  $admin->post('/reviews/review_package/:id')->to('Reviewer#review_package')
    ->name('review_package');
  $manager->post('/reviews/fasttrack_package/:id')
    ->to('Reviewer#fasttrack_package')->name('fasttrack_package');
  $admin->post('/reviews/add_ignore')->to('Reviewer#add_ignore');
  $admin->post('/reviews/reindex/:id')->to('Reviewer#reindex_package')
    ->name('reindex_package');

  $admin->get('/licenses')->to('License#list')->name('licenses');
  $admin->post('/licenses')->to('License#create');
  $admin->get('/licenses/new_pattern')->to('License#new_pattern')
    ->name('new_pattern');
  $admin->post('/licenses/new_pattern')->to('License#new_pattern');
  $admin->post('/licenses/create_pattern')->to('License#create_pattern')
    ->name('create_pattern');
  $admin->get('/licenses/:id')->to('License#show')->name('license_show');
  $admin->post('/licenses/:id')->to('License#update')->name('license_update');

  $admin->get('/licenses/edit_pattern/:id')->to('License#edit_pattern')
    ->name('edit_pattern');
  $admin->post('/licenses/update_pattern/:id')->to('License#update_pattern')
    ->name('update_pattern');
  $admin->delete('/licenses/remove_pattern/:id')->to('License#remove_pattern')
    ->name('remove_pattern');

  $public->get('/products')->to('Product#list')->name('products');
  $public->get('/products/*name/list_packages')
    ->to('Product#list_packages_ajax')->name('product_packages_ajax');
  $public->get('/products/*name')->to('Product#show')->name('product_show');

  $public->get('/snippets')->to('Snippet#list')->name('snippets');
  $classifier->post('/snippets')->to('Snippet#update')->name('tag_snippets');
  $admin->get('/snippet/edit/:id')->to('Snippet#edit')->name('edit_snippet');
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
