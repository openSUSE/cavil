# Copyright (C) 2024 SUSE LLC
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

use Mojo::Base -strict;

use FindBin;
use lib "$FindBin::Bin/lib";

use Test::More;
use Test::Mojo;
use Cavil::Test;
use Mojo::File qw(tempdir);
use Mojolicious::Lite;

plan skip_all => 'set TEST_ONLINE to enable this test' unless $ENV{TEST_ONLINE};

my $cavil_test = Cavil::Test->new(online => $ENV{TEST_ONLINE}, schema => 'command_obs_test');
my $config     = $cavil_test->default_config;
my $t          = Test::Mojo->new(Cavil => $config);
my $app        = $t->app;
$cavil_test->no_fixtures($app);

app->log->level('error');

app->routes->add_condition(
  query => sub {
    my ($route, $c, $captures, $hash) = @_;

    for my $key (keys %$hash) {
      my $values = ref $hash->{$key} ? $hash->{$key} : [$hash->{$key}];
      my $param  = $c->req->url->query->param($key);
      return undef unless defined $param && grep { $param eq $_ } @$values;
    }

    return 1;
  }
);

get '/source/:project/perl-Mojolicious' => [project => ['home:kraih']] => (query => {view => 'info'}) =>
  {text => <<'EOF'};
<sourceinfo package="perl-Mojolicious" rev="9199eca9ec0fa5cffe4c3a6cb99a8093"
vrev="140"
srcmd5="0e5c2d1c0c4178869cf7fb82482b9c52"
lsrcmd5="d277e095ec45b64835452d5e87d2d349"
verifymd5="bb19066400b2b60e2310b45f10d12f56">
  <filename>perl-Mojolicious.spec</filename>
</sourceinfo>
EOF

get '/source/:project/perl-Mojolicious/_meta' => [project => ['home:kraih']] => {text => <<'EOF'};
<package name="postgresql-plr" project="server:database:postgresql">
  <title>Mojolicious</title>
  <description>
    Real-time web framework
  </description>
</package>
EOF

get '/source/:project/perl-Mojolicious'                                    => [project => ['home:kraih']] =>
  (query => {expand => 1, rev => [1, '0e5c2d1c0c4178869cf7fb82482b9c52']}) => {text => <<'EOF'};
<directory name="perl-Mojolicious" rev="9199eca9ec0fa5cffe4c3a6cb99a8093"
  vrev="140" srcmd5="9199eca9ec0fa5cffe4c3a6cb99a8093">
  <linkinfo project="devel:languages:perl" package="perl-Mojolicious"
    srcmd5="0e5c2d1c0c4178869cf7fb82482b9c52"
    lsrcmd5="d277e095ec45b64835452d5e87d2d349" />
  <serviceinfo code="succeeded" lsrcmd5="9ed57c4451a8074594a106af43604341" />
  <entry name="perl-Mojo#licious.changes" md5="64dc1045d41bc24d40e196a965f6e253"
    size="76628" mtime="1485497156" />
  <entry name="perl-Mojolicious.spec" md5="aca567897d3201d004b48cdface4ea44"
    size="2405" mtime="1485497157" />
</directory>
EOF

get '/source/:project/perl-Mojolicious/perl-Mojolicious.spec' => [project => ['home:kraih']] =>
  (query => {rev => '9199eca9ec0fa5cffe4c3a6cb99a8093'})      => {text => 'Mojolicious spec!'};

get '/source/:project/perl-Mojolicious/:special'         => [project => ['home:kraih']]                =>
  (query => {rev => '9199eca9ec0fa5cffe4c3a6cb99a8093'}) => [special => ['perl-Mojo#licious.changes']] =>
  {text => 'Mojolicious changes!'};

my $api = 'http://127.0.0.1:'
  . $app->obs->config({'127.0.0.1' => {user => 'test', password => 'testing'}})->ua->server->app(app)->url->port;

subtest 'OBS' => sub {
  subtest 'Info' => sub {
    my $buffer = '';
    {
      open my $handle, '>', \$buffer;
      local *STDOUT = $handle;
      $app->start('obs', $api, 'home:kraih', 'perl-Mojolicious');
    }
    like $buffer, qr/package.+perl-Mojolicious/,                'package info';
    like $buffer, qr/srcmd5.+0e5c2d1c0c4178869cf7fb82482b9c52/, 'srcmd5 info';
  };

  subtest 'Download' => sub {
    my $tempdir = tempdir;
    my $buffer  = '';
    {
      open my $handle, '>', \$buffer;
      local *STDOUT = $handle;
      $app->start('obs', $api, 'home:kraih', 'perl-Mojolicious', '-d', $tempdir);
    }
    like $buffer, qr/Downloaded/i, 'right output';
    ok -e $tempdir->child('perl-Mojolicious', 'bb19066400b2b60e2310b45f10d12f56', 'perl-Mojo#licious.changes'),
      'spec file exists';
    ok -e $tempdir->child('perl-Mojolicious', 'bb19066400b2b60e2310b45f10d12f56', 'perl-Mojolicious.spec'),
      'spec file exists';
  };

  subtest 'Import' => sub {
    is $app->minion->jobs({tasks => ['obs_import']})->total, 0, 'no jobs queued';
    my $buffer = '';
    {
      open my $handle, '>', \$buffer;
      local *STDOUT = $handle;
      $app->start('obs', $api, 'home:kraih', 'perl-Mojolicious', '--import');
    }
    like $buffer, qr/Triggered obs_import job 1/i, 'right output';
    is $app->minion->jobs({tasks => ['obs_import']})->total, 1, 'job queued';
  };
};

done_testing();
