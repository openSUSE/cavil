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
use Mojo::Util qw(encode);
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

# Add deterministic test files for cavil_get_file/cavil_list_files MCP tools
my $unpacked_dir = $dir->child('.unpacked');
$unpacked_dir->make_path;
my $mcp_dir = $unpacked_dir->child('mcp_get_file_dir')->make_path;
$mcp_dir->child('mcp_get_file.txt')->spurt(encode('UTF-8', "first line\nsecond 👌 line\nthird line\nfourth line\n"));
$mcp_dir->child('nested')->make_path->child('nested_file.txt')->spurt("nested content\n");
$unpacked_dir->child('mcp_root_file.txt')->spurt("root content\n");

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
      is scalar @{$result->{tools}}, 4,                        'four tools available';
      is $result->{tools}[0]{name},  'cavil_get_open_reviews', 'right tool name';
      is $result->{tools}[1]{name},  'cavil_get_report',       'right tool name';
      is $result->{tools}[2]{name},  'cavil_get_file',         'right tool name';
      is $result->{tools}[3]{name},  'cavil_list_files',       'right tool name';
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
        like $text, qr/Upstream project maintained by SUSE employee/,                        'legal review notice';
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

    subtest 'cavil_get_file tool' => sub {
      subtest 'Embargoed package' => sub {
        $t->app->pg->db->update('bot_packages', {embargoed => 1}, {id => 1});
        my $result = $client->call_tool('cavil_get_file', {package_id => 1, file_path => 'mcp_get_file.txt'});
        ok $result->{isError}, 'is error';
        is $result->{content}[0]{text}, 'Package is embargoed and may not be processed with AI', 'embargoed message';
        $t->app->pg->db->update('bot_packages', {embargoed => 0}, {id => 1});
      };

      subtest 'Non-existent package' => sub {
        my $result = $client->call_tool('cavil_get_file', {package_id => 99999, file_path => 'mcp_get_file.txt'});
        ok $result->{isError}, 'is error';
        is $result->{content}[0]{text}, 'Package not found', 'not found message';
      };

      subtest 'Invalid file path' => sub {
        subtest 'Path traversal attempt (start)' => sub {
          my $result = $client->call_tool('cavil_get_file', {package_id => 1, file_path => '../etc/passwd'});
          ok $result->{isError}, 'is error';
          is $result->{content}[0]{text}, 'Invalid file path', 'invalid path message';
        };

        subtest 'Path traversal attempt (end)' => sub {
          my $result
            = $client->call_tool('cavil_get_file', {package_id => 1, file_path => 'mcp_get_file.txt/../../etc/passwd'});
          ok $result->{isError}, 'is error';
          is $result->{content}[0]{text}, 'Invalid file path', 'invalid path message';
        };
      };

      subtest 'Maximum line range exceeded' => sub {
        my $result = $client->call_tool('cavil_get_file',
          {package_id => 1, file_path => 'mcp_get_file.txt', start_line => 1, end_line => 1002});
        ok $result->{isError}, 'is error';
        is $result->{content}[0]{text}, 'Maximum line range exceeded', 'line range limit message';
      };

      subtest 'Invalid line range' => sub {
        my $result = $client->call_tool('cavil_get_file',
          {package_id => 1, file_path => 'mcp_get_file.txt', start_line => 4, end_line => 3});
        ok $result->{isError}, 'is error';
        is $result->{content}[0]{text}, 'Invalid line range', 'invalid range message';
      };

      subtest 'File not found' => sub {
        my $result = $client->call_tool('cavil_get_file', {package_id => 1, file_path => 'missing_file.txt'});
        ok $result->{isError}, 'is error';
        is $result->{content}[0]{text}, 'File not found', 'missing file message';
      };

      subtest 'Path is a directory' => sub {
        my $result = $client->call_tool('cavil_get_file', {package_id => 1, file_path => 'mcp_get_file_dir'});
        ok $result->{isError}, 'is error';
        is $result->{content}[0]{text}, 'Path is a directory, not a file', 'directory path message';
      };

      subtest 'Get file content (one line)' => sub {
        my $result = $client->call_tool('cavil_get_file',
          {package_id => 1, file_path => 'mcp_get_file_dir/mcp_get_file.txt', start_line => 2, end_line => 2});
        ok !$result->{isError}, 'not an error';
        my $text = $result->{content}[0]{text};
        is $text, "second 👌 line\n", 'returns expected line';
      };

      subtest 'Get file content (line range)' => sub {
        my $result = $client->call_tool('cavil_get_file',
          {package_id => 1, file_path => 'mcp_get_file_dir/mcp_get_file.txt', start_line => 2, end_line => 3});
        ok !$result->{isError}, 'not an error';
        my $text = $result->{content}[0]{text};
        is $text, "second 👌 line\nthird line\n", 'returns expected line range';
      };

      subtest 'Get file content (with trailing slash)' => sub {
        my $result
          = $client->call_tool('cavil_get_file', {package_id => 1, file_path => 'mcp_get_file_dir/mcp_get_file.txt/'});
        ok !$result->{isError}, 'not an error';
        my $text = $result->{content}[0]{text};
        like $text, qr/^first line$/m,    'contains first line';
        like $text, qr/^second 👌 line$/m, 'contains second line';
        like $text, qr/^third line$/m,    'contains third line';
        like $text, qr/^fourth line$/m,   'contains fourth line';
      };
    };

    subtest 'cavil_list_files tool' => sub {
      subtest 'Embargoed package' => sub {
        $t->app->pg->db->update('bot_packages', {embargoed => 1}, {id => 1});
        my $result = $client->call_tool('cavil_list_files', {package_id => 1});
        ok $result->{isError}, 'is error';
        is $result->{content}[0]{text}, 'Package is embargoed and may not be processed with AI', 'embargoed message';
        $t->app->pg->db->update('bot_packages', {embargoed => 0}, {id => 1});
      };

      subtest 'Non-existent package' => sub {
        my $result = $client->call_tool('cavil_list_files', {package_id => 99999});
        ok $result->{isError}, 'is error';
        is $result->{content}[0]{text}, 'Package not found', 'not found message';
      };

      subtest 'Package not yet unpacked' => sub {
        my $result = $client->call_tool('cavil_list_files', {package_id => 2});
        ok $result->{isError}, 'is error';
        is $result->{content}[0]{text}, 'Package is not yet unpacked', 'not unpacked message';
      };

      subtest 'List files from package root' => sub {
        my $result = $client->call_tool('cavil_list_files', {package_id => 1});
        ok !$result->{isError}, 'not an error';
        my $text = $result->{content}[0]{text};
        like $text, qr/^mcp_get_file_dir\/mcp_get_file\.txt$/m,        'contains top-level file in test dir';
        like $text, qr/^mcp_get_file_dir\/nested\/nested_file\.txt$/m, 'contains nested file';
        like $text, qr/^mcp_root_file\.txt$/m,                         'contains root file';
      };

      subtest 'List files with exact glob' => sub {
        my $result
          = $client->call_tool('cavil_list_files', {package_id => 1, file_glob => 'mcp_get_file_dir/mcp_get_file.txt'});
        ok !$result->{isError}, 'not an error';
        my $text = $result->{content}[0]{text};
        is $text, "mcp_get_file_dir/mcp_get_file.txt", 'returns expected file list';
      };

      subtest 'List files with wildcard glob' => sub {
        my $result = $client->call_tool('cavil_list_files', {package_id => 1, file_glob => 'mcp_get_file_dir/*'});
        ok !$result->{isError}, 'not an error';
        my $text = $result->{content}[0]{text};
        is $text, "mcp_get_file_dir/mcp_get_file.txt\nmcp_get_file_dir/nested/nested_file.txt",
          'returns expected file list';
      };

      subtest 'List files with no matches' => sub {
        my $result = $client->call_tool('cavil_list_files', {package_id => 1, file_glob => '*.does-not-exist'});
        ok !$result->{isError}, 'not an error';
        is $result->{content}[0]{text}, '', 'returns empty result';
      };

      subtest 'File list limit' => sub {
        my $mcp_many_files_dir = $unpacked_dir->child('mcp_many_files')->make_path;
        $mcp_many_files_dir->child("file_$_.txt")->spurt("x\n") for (1 .. 1001);

        subtest 'Maximum file list size exceeded' => sub {
          my $result = $client->call_tool('cavil_list_files', {package_id => 1, file_glob => 'mcp_many_files/*'});
          ok $result->{isError}, 'is error';
          is $result->{content}[0]{text}, 'Maximum file list size exceeded', 'file list limit message';
        };

        subtest 'Glob prevents file limit from being reached' => sub {
          my $result
            = $client->call_tool('cavil_list_files', {package_id => 1, file_glob => 'mcp_many_files/file_1.txt'});
          ok !$result->{isError}, 'not an error';
          is $result->{content}[0]{text}, 'mcp_many_files/file_1.txt', 'returns single filtered file';
        };
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
      is scalar @{$result->{tools}}, 8,                               'eight tools available';
      is $result->{tools}[0]{name},  'cavil_get_open_reviews',        'right tool name';
      is $result->{tools}[1]{name},  'cavil_get_report',              'right tool name';
      is $result->{tools}[2]{name},  'cavil_get_file',                'right tool name';
      is $result->{tools}[3]{name},  'cavil_list_files',              'right tool name';
      is $result->{tools}[4]{name},  'cavil_accept_review',           'right tool name';
      is $result->{tools}[5]{name},  'cavil_reject_review',           'right tool name';
      is $result->{tools}[6]{name},  'cavil_propose_ignore_snippet',  'right tool name';
      is $result->{tools}[7]{name},  'cavil_propose_license_pattern', 'right tool name';
    };

    subtest 'List tools (normal user)' => sub {
      $t->app->users->remove_role(2, 'admin');
      $t->app->users->remove_role(2, 'manager');

      my $result = $client->list_tools;
      is scalar @{$result->{tools}}, 4,                        'four tools available';
      is $result->{tools}[0]{name},  'cavil_get_open_reviews', 'right tool name';
      is $result->{tools}[1]{name},  'cavil_get_report',       'right tool name';
      is $result->{tools}[2]{name},  'cavil_get_file',         'right tool name';
      is $result->{tools}[3]{name},  'cavil_list_files',       'right tool name';

      $t->app->users->add_role(2, 'admin');
      $t->app->users->add_role(2, 'manager');
    };


    subtest 'List tools (manager)' => sub {
      $t->app->users->remove_role(2, 'admin');

      my $result = $client->list_tools;
      is scalar @{$result->{tools}}, 5,                        'five tools available';
      is $result->{tools}[0]{name},  'cavil_get_open_reviews', 'right tool name';
      is $result->{tools}[1]{name},  'cavil_get_report',       'right tool name';
      is $result->{tools}[2]{name},  'cavil_get_file',         'right tool name';
      is $result->{tools}[3]{name},  'cavil_list_files',       'right tool name';
      is $result->{tools}[4]{name},  'cavil_accept_review',    'right tool name';

      $t->app->users->add_role(2, 'admin');
    };

    subtest 'List tools (contributor)' => sub {
      $t->app->users->remove_role(2, 'admin');
      $t->app->users->remove_role(2, 'manager');
      $t->app->users->add_role(2, 'contributor');

      my $result = $client->list_tools;
      is scalar @{$result->{tools}}, 6,                               'six tools available';
      is $result->{tools}[0]{name},  'cavil_get_open_reviews',        'right tool name';
      is $result->{tools}[1]{name},  'cavil_get_report',              'right tool name';
      is $result->{tools}[2]{name},  'cavil_get_file',                'right tool name';
      is $result->{tools}[3]{name},  'cavil_list_files',              'right tool name';
      is $result->{tools}[4]{name},  'cavil_propose_ignore_snippet',  'right tool name';
      is $result->{tools}[5]{name},  'cavil_propose_license_pattern', 'right tool name';

      $t->app->users->remove_role(2, 'contributor');
      $t->app->users->add_role(2, 'manager');
      $t->app->users->add_role(2, 'admin');
    };

    subtest 'List tools (contributor and manager)' => sub {
      $t->app->users->remove_role(2, 'admin');
      $t->app->users->add_role(2, 'contributor');

      my $result = $client->list_tools;
      is scalar @{$result->{tools}}, 7,                               'seven tools available';
      is $result->{tools}[0]{name},  'cavil_get_open_reviews',        'right tool name';
      is $result->{tools}[1]{name},  'cavil_get_report',              'right tool name';
      is $result->{tools}[2]{name},  'cavil_get_file',                'right tool name';
      is $result->{tools}[3]{name},  'cavil_list_files',              'right tool name';
      is $result->{tools}[4]{name},  'cavil_accept_review',           'right tool name';
      is $result->{tools}[5]{name},  'cavil_propose_ignore_snippet',  'right tool name';
      is $result->{tools}[6]{name},  'cavil_propose_license_pattern', 'right tool name';

      $t->app->users->remove_role(2, 'contributor');
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
    };

    subtest 'cavil_accept_review tool' => sub {
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

    subtest 'cavil_propose_ignore_snippet tool' => sub {
      subtest 'Propose ignore' => sub {
        my $result = $client->call_tool('cavil_propose_ignore_snippet',
          {package_id => 1, snippet_id => 1, reason => 'Just a test ignore proposal'});
        ok !$result->{isError}, 'not an error';
        is $result->{content}[0]{text}, 'Proposal to ignore snippet has been successfully submitted',
          'proposal message';

        $t->get_ok('/login')->status_is(302)->header_is(Location => '/');
        $t->get_ok('/licenses/proposed/meta?action=create_ignore')
          ->status_is(200)
          ->json_is('/changes/0/action',                    'create_ignore')
          ->json_is('/changes/0/login',                     'tester')
          ->json_is('/changes/0/data/ai_assisted',          1)
          ->json_is('/changes/0/data/edited',               0)
          ->json_is('/changes/0/data/from',                 'perl-Mojolicious')
          ->json_is('/changes/0/data/highlighted_keywords', [1])
          ->json_is('/changes/0/data/package',              1)
          ->json_like('/changes/0/data/pattern', qr/Fixed copyright notice/)
          ->json_like('/changes/0/data/reason',  qr/AI Assistant: Just a test ignore proposal/)
          ->json_is('/changes/0/data/snippet', 1);
        $t->get_ok('/logout')->status_is(302)->header_is(Location => '/');
      };

      subtest 'Propose ignore (conflicting proposal)' => sub {
        my $result = $client->call_tool('cavil_propose_ignore_snippet',
          {package_id => 1, snippet_id => 1, reason => 'Just a test ignore proposal'});
        ok $result->{isError}, 'is an error';
        is $result->{content}[0]{text}, 'Conflicting ignore pattern proposal already exists', 'conflict message';
      };

      subtest 'Propose ignore (conflicting pattern)' => sub {
        $t->get_ok('/login')->status_is(302)->header_is(Location => '/');
        $t->get_ok('/licenses/proposed/meta?action=create_ignore')
          ->status_is(200)
          ->json_is('/changes/0/action',           'create_ignore')
          ->json_is('/changes/0/login',            'tester')
          ->json_is('/changes/0/data/ai_assisted', 1)
          ->json_is('/changes/0/data/package',     1)
          ->json_is('/changes/0/data/snippet',     1);
        my $json = $t->tx->res->json;
        my $form = {
          'create-ignore' => 1,
          hash            => $json->{changes}[0]{token_hexsum},
          from            => $json->{changes}[0]{data}{from},
          contributor     => $json->{changes}[0]{login}
        };
        $t->post_ok('/snippet/decision/1' => form => $form)
          ->status_is(200)
          ->content_like(qr/ignore pattern has been created/);
        $t->get_ok('/logout')->status_is(302)->header_is(Location => '/');

        my $result = $client->call_tool('cavil_propose_ignore_snippet',
          {package_id => 1, snippet_id => 1, reason => 'Just a test ignore proposal'});
        ok $result->{isError}, 'is an error';
        is $result->{content}[0]{text}, 'Conflicting ignore pattern already exists', 'conflict message';
      };

      subtest 'Propose ignore (non-existent package)' => sub {
        my $result = $client->call_tool('cavil_propose_ignore_snippet',
          {package_id => 23, snippet_id => 1, reason => 'Just a test ignore proposal'});
        ok $result->{isError}, 'is an error';
        is $result->{content}[0]{text}, 'Package not found', 'not found message';
      };

      subtest 'Propose ignore (embargoed package)' => sub {
        $t->app->pg->db->update('bot_packages', {embargoed => 1}, {id => 1});
        my $result = $client->call_tool('cavil_propose_ignore_snippet',
          {package_id => 1, snippet_id => 2, reason => 'Just a test ignore proposal'});
        ok $result->{isError}, 'is an error';
        is $result->{content}[0]{text}, 'Package is embargoed and may not be processed with AI', 'embargoed message';
        $t->app->pg->db->update('bot_packages', {embargoed => 0}, {id => 1});
      };


      subtest 'Propose ignore (non-existent snippet)' => sub {
        my $result = $client->call_tool('cavil_propose_ignore_snippet',
          {package_id => 1, snippet_id => 23, reason => 'Just a test ignore proposal'});
        ok $result->{isError}, 'is an error';
        is $result->{content}[0]{text}, 'Snippet not found', 'not found message';
      };
    };

    subtest 'cavil_propose_license_pattern tool' => sub {
      subtest 'Propose license pattern' => sub {
        my $result = $client->call_tool(
          'cavil_propose_license_pattern',
          {
            package_id => 1,
            snippet_id => 5,
            pattern    => 'terms of the Artistic License version 2.0',
            license    => 'Artistic-2.0',
            reason     => 'Just a test pattern proposal'
          }
        );
        ok !$result->{isError}, 'not an error';
        is $result->{content}[0]{text}, 'Proposal for new license pattern has been successfully submitted',
          'proposal message';

        $t->get_ok('/login')->status_is(302)->header_is(Location => '/');
        $t->get_ok('/licenses/proposed/meta?action=create_pattern')
          ->status_is(200)
          ->json_is('/changes/0/action',                    'create_pattern')
          ->json_is('/changes/0/login',                     'tester')
          ->json_is('/changes/0/data/ai_assisted',          1)
          ->json_is('/changes/0/data/edited',               1)
          ->json_is('/changes/0/data/license',              'Artistic-2.0')
          ->json_is('/changes/0/data/risk',                 5)
          ->json_is('/changes/0/data/patent',               0)
          ->json_is('/changes/0/data/trademark',            0)
          ->json_is('/changes/0/data/export_restricted',    0)
          ->json_is('/changes/0/data/highlighted_keywords', [])
          ->json_is('/changes/0/data/package',              1)
          ->json_like('/changes/0/data/pattern', qr/terms of the Artistic License version 2.0/)
          ->json_like('/changes/0/data/reason',  qr/AI Assistant: Just a test pattern proposal/)
          ->json_is('/changes/0/data/snippet', 5);
        $t->get_ok('/logout')->status_is(302)->header_is(Location => '/');
      };

      subtest 'Propose license pattern (with flags)' => sub {
        $t->app->pg->db->delete('proposed_changes');
        $t->app->pg->db->update(
          'license_patterns',
          {trademark => 1, patent => 1, export_restricted => 1},
          {license   => 'Artistic-2.0'}
        );

        my $result = $client->call_tool(
          'cavil_propose_license_pattern',
          {
            package_id => 1,
            snippet_id => 5,
            pattern    => 'terms of the Artistic License version 2.0',
            license    => 'Artistic-2.0',
            reason     => 'Just a test pattern proposal'
          }
        );
        ok !$result->{isError}, 'not an error';
        is $result->{content}[0]{text}, 'Proposal for new license pattern has been successfully submitted',
          'proposal message';

        $t->get_ok('/login')->status_is(302)->header_is(Location => '/');
        $t->get_ok('/licenses/proposed/meta?action=create_pattern')
          ->status_is(200)
          ->json_is('/changes/0/action',                    'create_pattern')
          ->json_is('/changes/0/login',                     'tester')
          ->json_is('/changes/0/data/ai_assisted',          1)
          ->json_is('/changes/0/data/edited',               1)
          ->json_is('/changes/0/data/license',              'Artistic-2.0')
          ->json_is('/changes/0/data/risk',                 5)
          ->json_is('/changes/0/data/patent',               1)
          ->json_is('/changes/0/data/trademark',            1)
          ->json_is('/changes/0/data/export_restricted',    1)
          ->json_is('/changes/0/data/highlighted_keywords', [])
          ->json_is('/changes/0/data/package',              1)
          ->json_like('/changes/0/data/pattern', qr/terms of the Artistic License version 2.0/)
          ->json_like('/changes/0/data/reason',  qr/AI Assistant: Just a test pattern proposal/)
          ->json_is('/changes/0/data/snippet', 5);
        $t->get_ok('/logout')->status_is(302)->header_is(Location => '/');
      };

      subtest 'Propose license pattern (conflicting proposal)' => sub {
        my $result = $client->call_tool(
          'cavil_propose_license_pattern',
          {
            package_id => 1,
            snippet_id => 5,
            pattern    => 'terms of the Artistic License version 2.0',
            license    => 'Artistic-2.0',
            reason     => 'Just a test pattern proposal'
          }
        );
        ok $result->{isError}, 'is an error';
        is $result->{content}[0]{text}, 'Conflicting license pattern proposal already exists', 'conflict message';
        $t->app->pg->db->delete('proposed_changes');
      };

      subtest 'Propose license pattern (conflicting license pattern)' => sub {
        my $result = $client->call_tool(
          'cavil_propose_license_pattern',
          {
            package_id => 1,
            snippet_id => 1,
            pattern    => 'copyright notice',
            license    => 'Artistic-2.0',
            reason     => 'Just a test pattern proposal'
          }
        );
        ok $result->{isError}, 'is an error';
        is $result->{content}[0]{text}, 'Conflicting license pattern already exists', 'conflict message';
      };

      subtest 'Propose license pattern (pattern mismatch)' => sub {
        my $result = $client->call_tool(
          'cavil_propose_license_pattern',
          {
            package_id => 1,
            snippet_id => 5,
            pattern    => 'Artistic-2.0',
            license    => 'Artistic-2.0',
            reason     => 'Just a test pattern proposal'
          }
        );
        ok $result->{isError}, 'is an error';
        is $result->{content}[0]{text}, 'License pattern does not match the original snippet',
          'pattern mismatch message';
      };

      subtest 'Propose license pattern (redundant skip)' => sub {
        my $result = $client->call_tool(
          'cavil_propose_license_pattern',
          {
            package_id => 1,
            snippet_id => 5,
            pattern    => 'terms of the Artistic License version 2.0 $SKIP9',
            license    => 'Artistic-2.0',
            reason     => 'Just a test pattern proposal'
          }
        );
        ok $result->{isError}, 'is an error';
        is $result->{content}[0]{text}, 'License pattern contains redundant $SKIP at beginning or end',
          'redundant skip message';
      };

      subtest 'Propose license pattern (unknown license)' => sub {
        my $result = $client->call_tool(
          'cavil_propose_license_pattern',
          {
            package_id => 1,
            snippet_id => 5,
            pattern    => 'terms of the Artistic License version 2.0',
            license    => 'Artistic-1.0',
            reason     => 'Just a test pattern proposal'
          }
        );
        ok $result->{isError}, 'is an error';
        is $result->{content}[0]{text}, 'License expression is not in the list of known licenses',
          'unknown license message';
      };

      subtest 'Propose license pattern (unknown license with suggestions)' => sub {
        my $result = $client->call_tool(
          'cavil_propose_license_pattern',
          {
            package_id => 1,
            snippet_id => 5,
            pattern    => 'terms of the Artistic License version 2.0',
            license    => 'Artistic',
            reason     => 'Just a test pattern proposal'
          }
        );
        ok $result->{isError}, 'is an error';
        is $result->{content}[0]{text},
          "License expression is not in the list of known licenses, closest matches are:\n* Artistic-2.0",
          'unknown license message';
      };

      subtest 'Propose ignore (non-existent package)' => sub {
        my $result = $client->call_tool(
          'cavil_propose_license_pattern',
          {
            package_id => 23,
            snippet_id => 1,
            pattern    => 'terms of the Artistic License version 2.0',
            license    => 'Artistic-2.0',
            reason     => 'Just a test pattern proposal'
          }
        );
        ok $result->{isError}, 'is an error';
        is $result->{content}[0]{text}, 'Package not found', 'not found message';
      };

      subtest 'Propose ignore (non-existent snippet)' => sub {
        my $result = $client->call_tool(
          'cavil_propose_license_pattern',
          {
            package_id => 1,
            snippet_id => 200,
            pattern    => 'terms of the Artistic License version 2.0',
            license    => 'Artistic-2.0',
            reason     => 'Just a test pattern proposal'
          }
        );
        ok $result->{isError}, 'is an error';
        is $result->{content}[0]{text}, 'Snippet not found', 'not found message';
      };

      subtest 'Propose ignore (embargoed package)' => sub {
        $t->app->pg->db->update('bot_packages', {embargoed => 1}, {id => 1});
        my $result = $client->call_tool(
          'cavil_propose_license_pattern',
          {
            package_id => 1,
            snippet_id => 5,
            pattern    => 'terms of the Artistic License version 2.0',
            license    => 'Artistic-2.0',
            reason     => 'Just a test pattern proposal'
          }
        );
        ok $result->{isError}, 'is an error';
        is $result->{content}[0]{text}, 'Package is embargoed and may not be processed with AI', 'embargoed message';
        $t->app->pg->db->update('bot_packages', {embargoed => 0}, {id => 1});
      };
    };
  }
};

done_testing;
