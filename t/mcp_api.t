# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later
use Mojo::Base -strict, -signatures;

use FindBin;
use lib "$FindBin::Bin/lib";

use Test::More;
use Test::Mojo;
use Cavil::Test;
use Mojo::File qw(path);
use Mojo::Date;
use MCP::Client;

plan skip_all => 'set TEST_ONLINE to enable this test' unless $ENV{TEST_ONLINE};

my $cavil_test = Cavil::Test->new(online => $ENV{TEST_ONLINE}, schema => 'mcp_api_test');
my $t          = Test::Mojo->new(Cavil => $cavil_test->default_config);
$cavil_test->mojo_fixtures($t->app);

# Add patterns for known incompatible licenses
$t->app->patterns->create(pattern => 'SPDX-License-Identifier: Apache-2.0',   license => 'Apache-2.0');
$t->app->patterns->create(pattern => 'SPDX-License-Identifier: GPL-2.0-only', license => 'GPL-2.0-only');
$t->app->pg->db->query('UPDATE license_patterns SET spdx = $1 WHERE license = $1', $_) for qw(Apache-2.0 GPL-2.0-only);

# Add files with incompatible licenses
my $pkg = $t->app->packages->find(1);
my $dir = path($cavil_test->checkout_dir, $pkg->{name}, $pkg->{checkout_dir});
$dir->child('apache_file.txt')->spurt("# SPDX-License-Identifier: Apache-2.0\n\nThis is a test file.\n");
$dir->child('gpl2_file.txt')->spurt("# SPDX-License-Identifier: GPL-2.0-only\n\nThis is another test file.\n");

# Unpack and index
$t->app->minion->enqueue(unpack => [1]);
$t->app->minion->perform_jobs;

subtest 'MCP' => sub {
  my $key           = '';
  my $write_key     = '';
  my $expires_epoch = time + 36000;
  my $expires       = Mojo::Date->new($expires_epoch)->to_datetime =~ s/:\d{2}Z$//r;

  subtest 'Read-only' => sub {
    subtest 'Create API key' => sub {
      $t->get_ok('/login')->status_is(302)->header_is(Location => '/');

      $t->post_ok('/api_keys' => form => {expires => $expires, type => 'read-only', description => 'Test key'})
        ->status_is(200)
        ->json_is('/created' => 1);
      $t->get_ok('/api_keys/meta')
        ->status_is(200)
        ->json_is('/keys/0/id'    => 1)
        ->json_is('/keys/0/owner' => 2)
        ->json_like('/keys/0/api_key' => qr/^[a-f0-9\-]{20,}$/i)
        ->json_is('/keys/0/description' => 'Test key')
        ->json_has('/keys/0/expires_epoch');
      $key = $t->tx->res->json('/keys/0/api_key');

      $t->get_ok('/logout')->status_is(302)->header_is(Location => '/');
    };

    subtest 'Authentication' => sub {
      $t->get_ok('/mcp')
        ->status_is(403)
        ->json_is({error => 'It appears you have insufficient permissions for accessing this resource'});

      $t->ua->on(start => sub ($ua, $tx) { $tx->req->headers->authorization("Bearer $key") });
      $t->get_ok('/mcp')->status_is(405);
    };

    my $client = MCP::Client->new(ua => $t->ua, url => $t->ua->server->url->path('/mcp'));

    subtest 'Start session' => sub {
      is $client->session_id, undef, 'no session id';
      my $result = $client->initialize_session;
      is $result->{serverInfo}{name},    'Cavil', 'server name';
      is $result->{serverInfo}{version}, '1.0.0', 'server version';
      ok $result->{capabilities}, 'has capabilities';
      ok $client->session_id,     'session id set';
    };

    subtest 'List tools' => sub {
      my $result = $client->list_tools;
      is scalar @{$result->{tools}}, 2,                        'two tools available';
      is $result->{tools}[0]{name},  'cavil_get_open_reviews', 'right tool name';
      is $result->{tools}[1]{name},  'cavil_get_report',       'right tool name';
    };

    subtest 'cavil_get_open_reviews tool' => sub {
      subtest 'No matches' => sub {
        my $result = $client->call_tool('cavil_get_open_reviews', {search => 'NonExistentPackage'});
        ok !$result->{isError}, 'not an error';
        my $text = $result->{content}[0]{text};
        like $text, qr/There are currently no open reviews/, 'no results';
      };

      subtest 'No search' => sub {
        my $result = $client->call_tool('cavil_get_open_reviews', {search => 'Mojolicious'});
        ok !$result->{isError}, 'not an error';
        my $text = $result->{content}[0]{text};
        like $text, qr/1\..+perl-Mojolicious/,  'contains package name';
        like $text, qr/Id:.+1/,                 'contains id';
        like $text, qr/External-Link:.+mojo/,   'contains external link';
        like $text, qr/Priority:.+5/,           'contains priority';
        like $text, qr/Unresolved-Matches:.+6/, 'contains unresolved matches';
        note $text;
      };

      subtest 'With search' => sub {
        my $result = $client->call_tool('cavil_get_open_reviews', {search => 'mojo#2'});
        ok !$result->{isError}, 'not an error';
        my $text = $result->{content}[0]{text};
        like $text,   qr/1\..+perl-Mojolicious/, 'contains package name';
        like $text,   qr/Id:.+2/,                'contains id';
        unlike $text, qr/Id:.+1/,                'does not contain other matches';
      };
    };

    subtest 'cavil_get_report tool' => sub {
      subtest 'Embargoed package' => sub {
        $t->app->pg->db->update('bot_packages', {embargoed => 1}, {id => 1});
        my $result = $client->call_tool('cavil_get_report', {package_id => 1});
        ok $result->{isError}, 'is error';
        is $result->{content}[0]{text}, 'Package is embargoed and may not be processed with AI', 'embargoed message';
        $t->app->pg->db->update('bot_packages', {embargoed => 0}, {id => 1});
      };

      subtest 'Non-existent package' => sub {
        my $result = $client->call_tool('cavil_get_report', {package_id => 99999});
        ok $result->{isError}, 'is error';
        is $result->{content}[0]{text}, 'Package not found', 'not found message';
      };

      subtest 'Package not yet indexed' => sub {
        my $pkg = $t->app->packages->find(1);
        $t->app->pg->db->update('bot_packages', {indexed => undef}, {id => $pkg->{id}});
        my $result = $client->call_tool('cavil_get_report', {package_id => 1});
        ok $result->{isError}, 'is error';
        is $result->{content}[0]{text}, 'Package is not yet indexed, please try again later', 'not indexed message';
        $t->app->pg->db->update('bot_packages', {indexed => \'NOW()'}, {id => $pkg->{id}});
      };

      subtest 'No report available' => sub {
        $t->app->pg->db->delete('bot_reports', {package => 1});
        my $result = $client->call_tool('cavil_get_report', {package_id => 1});
        ok $result->{isError}, 'is error';
        is $result->{content}[0]{text}, 'No report available', 'no report message';
      };

      subtest 'Package being processed' => sub {
        my $id     = $t->app->minion->enqueue(index => [1] => {notes => {pkg_1 => 1}});
        my $result = $client->call_tool('cavil_get_report', {package_id => 1});
        ok $result->{isError}, 'is error';
        is $result->{content}[0]{text}, 'Package is being processed, please try again later', 'processing message';
        $t->app->minion->perform_jobs;
      };

      subtest 'Full report' => sub {
        my $result = $client->call_tool('cavil_get_report', {package_id => 1});
        ok !$result->{isError}, 'not an error';
        my $text = $result->{content}[0]{text};
        like $text, qr/Package:.+perl-Mojolicious/,                                          'package name';
        like $text, qr/Id:.+1/,                                                              'package id';
        like $text, qr/State:.+new/,                                                         'state';
        like $text, qr/External-Link:.+mojo/,                                                'external link';
        like $text, qr/Version:.+7\.25/,                                                     'version';
        like $text, qr/Summary:.+Real-time web framework/,                                   'summary';
        like $text, qr/Group:.+Development\/Libraries\/Perl/,                                'group';
        like $text, qr/URL:.+search\.cpan\.org/,                                             'url';
        like $text, qr/Shortname:./,                                                         'shortname';
        like $text, qr/Checkout:.+c7cfdab0e71b0bebfdf8b2dc3badfecd/,                         'checkout';
        like $text, qr/Unpacked:.+ files/,                                                   'unpacked';
        like $text, qr/Priority:.+5/,                                                        'priority';
        like $text, qr/Created:.+/,                                                          'created';
        like $text, qr/Manual review is required because no previous reports are available/, 'system notice';
        like $text, qr/Elevated risk, package might contain incompatible licenses/,          'risk notice';
        like $text, qr/\* GPL-2.0-only: 1 file/,                                             'license summary';
        like $text, qr/- `gpl2_file.txt`/,                                                   'matched file';
        like $text, qr/- \.\.\./,                                                            'more matched files';
        like $text, qr/Mojolicious-7\.25\/Changes/,                                          'file with unknown match';
        like $text, qr/- Fixed copyright notice/,                                            'unknown match preview';
        like $text, qr/sri\@cpan\.org/,                                                      'email found';
        like $text, qr/http:\/\/mojolicious\.org/,                                           'URL found';
        note $text;
      };
    };
  };

  subtest 'Read-write' => sub {
    subtest 'Create API key (write)' => sub {
      $t->get_ok('/login')->status_is(302)->header_is(Location => '/');

      $t->post_ok('/api_keys' => form => {expires => $expires, type => 'read-write', description => 'Write key'})
        ->status_is(200)
        ->json_is('/created' => 2);
      $t->get_ok('/api_keys/meta')
        ->status_is(200)
        ->json_is('/keys/0/id'          => 1)
        ->json_is('/keys/0/owner'       => 2)
        ->json_is('/keys/1/id'          => 2)
        ->json_is('/keys/1/owner'       => 2)
        ->json_is('/keys/1/description' => 'Write key');
      $write_key = $t->tx->res->json('/keys/1/api_key');

      $t->get_ok('/logout')->status_is(302)->header_is(Location => '/');
    };

    subtest 'Authentication' => sub {
      $t->ua->unsubscribe('start');
      $t->get_ok('/mcp')
        ->status_is(403)
        ->json_is({error => 'It appears you have insufficient permissions for accessing this resource'});

      $t->ua->on(start => sub ($ua, $tx) { $tx->req->headers->authorization("Bearer $write_key") });
      $t->get_ok('/mcp')->status_is(405);
    };

    my $client = MCP::Client->new(ua => $t->ua, url => $t->ua->server->url->path('/mcp'));

    subtest 'Start session' => sub {
      is $client->session_id, undef, 'no session id';
      my $result = $client->initialize_session;
      is $result->{serverInfo}{name},    'Cavil', 'server name';
      is $result->{serverInfo}{version}, '1.0.0', 'server version';
      ok $result->{capabilities}, 'has capabilities';
      ok $client->session_id,     'session id set';
    };

    subtest 'List tools' => sub {
      my $result = $client->list_tools;
      is scalar @{$result->{tools}}, 4,                        'four tools available';
      is $result->{tools}[0]{name},  'cavil_get_open_reviews', 'right tool name';
      is $result->{tools}[1]{name},  'cavil_get_report',       'right tool name';
      is $result->{tools}[2]{name},  'cavil_accept_review',    'right tool name';
      is $result->{tools}[3]{name},  'cavil_reject_review',    'right tool name';
    };

    subtest 'List tools (normal user)' => sub {
      $t->app->users->remove_role(2, 'admin');
      $t->app->users->remove_role(2, 'manager');

      my $result = $client->list_tools;
      is scalar @{$result->{tools}}, 2,                        'two tools available';
      is $result->{tools}[0]{name},  'cavil_get_open_reviews', 'right tool name';
      is $result->{tools}[1]{name},  'cavil_get_report',       'right tool name';

      $t->app->users->add_role(2, 'admin');
      $t->app->users->add_role(2, 'manager');
    };


    subtest 'List tools (manager)' => sub {
      $t->app->users->remove_role(2, 'admin');

      my $result = $client->list_tools;
      is scalar @{$result->{tools}}, 3,                        'three tools available';
      is $result->{tools}[0]{name},  'cavil_get_open_reviews', 'right tool name';
      is $result->{tools}[1]{name},  'cavil_get_report',       'right tool name';
      is $result->{tools}[2]{name},  'cavil_accept_review',    'right tool name';

      $t->app->users->add_role(2, 'admin');
    };

    subtest 'cavil_reject_review tool' => sub {
      subtest 'Reject review' => sub {
        $t->app->pg->db->update('bot_packages', {state => 'new', reviewing_user => undef, ai_assisted => 0}, {id => 1});

        subtest 'Successful rejection' => sub {
          my $result = $client->call_tool('cavil_reject_review', {package_id => 1, reason => 'Test review rejection'});
          ok !$result->{isError}, 'not an error';
          is $result->{content}[0]{text}, 'Review has been successfully rejected', 'reject message';
        };

        subtest 'Reject already reviewed package' => sub {
          my $result = $client->call_tool('cavil_reject_review', {package_id => 1, reason => 'Test review rejection'});
          ok $result->{isError}, 'error';
          is $result->{content}[0]{text}, 'Package has already been reviewed', 'error message';
        };

        $t->get_ok('/login')->status_is(302)->header_is(Location => '/');
        $t->get_ok('/reviews/meta/1')
          ->status_is(200)
          ->json_is('/state',          'unacceptable')
          ->json_is('/reviewing_user', 'tester')
          ->json_like('/result', qr/AI Assistant: Test review rejection/)
          ->json_is('/ai_assisted', 1);
        $t->get_ok('/logout')->status_is(302)->header_is(Location => '/');
      };

      subtest 'Reject review (embargoed)' => sub {
        $t->app->pg->db->update('bot_packages', {state => 'new', reviewing_user => undef, ai_assisted => 0}, {id => 1});
        $t->app->pg->db->update('bot_packages', {embargoed => 1}, {id => 1});

        my $result = $client->call_tool('cavil_reject_review', {package_id => 1, reason => 'Test review rejection'});
        ok $result->{isError}, 'is error';
        is $result->{content}[0]{text}, 'Package is embargoed and may not be processed with AI', 'embargoed message';

        $t->app->pg->db->update('bot_packages', {embargoed => 0}, {id => 1});
      };

      subtest 'Accept review' => sub {
        $t->app->pg->db->update('bot_packages', {state => 'new', reviewing_user => undef, ai_assisted => 0}, {id => 1});

        subtest 'Successful acceptance' => sub {
          my $result = $client->call_tool('cavil_accept_review', {package_id => 1, reason => 'Test review acceptance'});
          ok !$result->{isError}, 'not an error';
          is $result->{content}[0]{text}, 'Review has been successfully accepted', 'accept message';
        };

        subtest 'Accept already reviewed package' => sub {
          my $result = $client->call_tool('cavil_accept_review', {package_id => 1, reason => 'Test review acceptance'});
          ok $result->{isError}, 'error';
          is $result->{content}[0]{text}, 'Package has already been reviewed', 'error message';
        };

        $t->get_ok('/login')->status_is(302)->header_is(Location => '/');
        $t->get_ok('/reviews/meta/1')
          ->status_is(200)
          ->json_is('/state',          'acceptable')
          ->json_is('/reviewing_user', 'tester')
          ->json_like('/result', qr/AI Assistant: Test review acceptance/)
          ->json_is('/ai_assisted', 1);
        $t->get_ok('/logout')->status_is(302)->header_is(Location => '/');
      };

      subtest 'Accept review (embargoed)' => sub {
        $t->app->pg->db->update('bot_packages', {state => 'new', reviewing_user => undef, ai_assisted => 0}, {id => 1});
        $t->app->pg->db->update('bot_packages', {embargoed => 1}, {id => 1});

        my $result = $client->call_tool('cavil_accept_review', {package_id => 1});
        ok $result->{isError}, 'is error';
        is $result->{content}[0]{text}, 'Package is embargoed and may not be processed with AI', 'embargoed message';

        $t->app->pg->db->update('bot_packages', {embargoed => 0}, {id => 1});
      };

      subtest 'Accept review (default reason)' => sub {
        $t->app->pg->db->update('bot_packages', {state => 'new', reviewing_user => undef, ai_assisted => 0}, {id => 1});

        subtest 'Successful acceptance' => sub {
          my $result = $client->call_tool('cavil_accept_review', {package_id => 1});
          ok !$result->{isError}, 'not an error';
          is $result->{content}[0]{text}, 'Review has been successfully accepted', 'accept message';
        };

        $t->get_ok('/login')->status_is(302)->header_is(Location => '/');
        $t->get_ok('/reviews/meta/1')
          ->status_is(200)
          ->json_is('/state',          'acceptable')
          ->json_is('/reviewing_user', 'tester')
          ->json_like('/result', qr/Reviewed ok/)
          ->json_unlike('/result', qr/AI Assistant:/)
          ->json_is('/ai_assisted', 1);
        $t->get_ok('/logout')->status_is(302)->header_is(Location => '/');
      };

      subtest 'Accept review (lawyer)' => sub {
        $t->app->pg->db->update('bot_packages', {state => 'new', reviewing_user => undef, ai_assisted => 0}, {id => 1});
        $t->app->users->add_role(2, 'lawyer');

        subtest 'Successful acceptance' => sub {
          my $result = $client->call_tool('cavil_accept_review',
            {package_id => 1, reason => 'Test review acceptance by lawyer'});
          ok !$result->{isError}, 'not an error';
          is $result->{content}[0]{text}, 'Review has been successfully accepted', 'accept message';
        };

        $t->get_ok('/login')->status_is(302)->header_is(Location => '/');
        $t->get_ok('/reviews/meta/1')
          ->status_is(200)
          ->json_is('/state',          'acceptable_by_lawyer')
          ->json_is('/reviewing_user', 'tester')
          ->json_like('/result', qr/AI Assistant: Test review acceptance by lawyer/)
          ->json_is('/ai_assisted', 1);
        $t->get_ok('/logout')->status_is(302)->header_is(Location => '/');
      };
    };
  }
};

done_testing;
