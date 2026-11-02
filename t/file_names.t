# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Mojo::Base -strict, -signatures;
use utf8;

use FindBin;
use lib "$FindBin::Bin/lib";

use Test::More;
use Test::Mojo;
use Cavil::Test;
use MCP::Client;
use Mojo::Date;
use IO::Uncompress::Gunzip qw(gunzip $GunzipError);
use Mojo::Util             qw(decode encode url_escape);

plan skip_all => 'set TEST_ONLINE to enable this test' unless $ENV{TEST_ONLINE};

my $cavil_test = Cavil::Test->new(online => $ENV{TEST_ONLINE}, schema => 'file_names_test');
my $t          = Test::Mojo->new(Cavil => $cavil_test->default_config);
my ($id, $empty) = $cavil_test->file_names_fixtures($t->app);

# Names travel as the filesystem's bytes, and so do the URLs the frontend builds from them
my $licensed = encode('UTF-8', 'Lizenzä.txt');
my $plain    = encode('UTF-8', 'Notizen-ü.txt');
my $latin1   = "alt\xe4.txt";
my $url      = sub ($name) { url_escape $name, '^A-Za-z0-9\-._~' };

$t->get_ok('/login')->status_is(302);

subtest 'The file browser lists and opens every name' => sub {
  my $entries = $t->get_ok("/reviews/file_view_meta/$id/")->status_is(200)->tx->res->json->{entries};
  my %url     = map { $_->{name} => $_->{url} } @$entries;
  is_deeply [sort keys %url], [sort $licensed, $plain, $latin1], 'the names as they are on disk';
  is $url{$licensed}, "/reviews/file_view/$id/Lizenz%C3%A4.txt", 'a UTF-8 name is linked by its bytes';
  is $url{$latin1},   "/reviews/file_view/$id/alt%E4.txt",       'and so is one that is not UTF-8';

  for my $name ($licensed, $latin1) {
    $t->get_ok("/reviews/file_view_meta/$id/" . $url->($name))
      ->status_is(200)
      ->json_is('/currentPath',     $name)
      ->json_is('/source/filename', $name);
    ok $t->tx->res->json('/source/id'), 'with its matches';
  }

  $t->get_ok("/reviews/file_view/$id/" . $url->($licensed))
    ->status_is(200)
    ->text_is(title => 'Content of Lizenzä.txt')
    ->element_exists(qq{#file-browser[data-initial-path='"Lizenz\x{c3}\x{a4}.txt"']});
  $t->get_ok("/reviews/file_raw/$id/" . $url->($licensed))
    ->status_is(200)
    ->header_is('Content-Disposition' => q{attachment; filename="Lizenz_.txt"; filename*=UTF-8''Lizenz%C3%A4.txt});
  $t->get_ok("/reviews/file_raw/$id/" . $url->($latin1))
    ->status_is(200)
    ->header_is('Content-Disposition' => q{attachment; filename="alt_.txt"; filename*=UTF-8''alt%C3%A4.txt});
};

subtest 'The report links into the browser' => sub {
  my $files = $t->get_ok("/reviews/report_details/$id")->status_is(200)->tx->res->json('/risks/1/0/files');
  is_deeply [sort map { $_->[1] } @$files], [sort $licensed, $latin1], 'both licensed files';
  $t->get_ok("/reviews/file_view_meta/$id/" . $url->($_->[1]))->status_is(200) for @$files;
};

subtest 'A snippet from a file with no matches, by path' => sub {
  $t->get_ok("/snippets/from_path/$id/" . $url->($plain) . '?start=1&end=1' => {Accept => 'application/json'})
    ->status_is(200)
    ->json_has('/snippet');
  ok +(grep { $_ eq $plain } @{$t->app->packages->matched_files($id)}), 'recorded under the name on disk';
};

subtest 'Agents read names as people wrote them and can use them' => sub {
  my $expires = Mojo::Date->new(time + 36000)->to_datetime =~ s/:\d{2}Z$//r;
  $t->post_ok('/api_keys' => form => {expires => $expires, type => 'read-write', description => 'Names'})
    ->status_is(200);
  my $key = $t->get_ok('/api_keys/meta')->tx->res->json('/keys/0/api_key');
  my $mcp = Test::Mojo->new($t->app);
  $mcp->ua->on(start => sub ($ua, $tx) { $tx->req->headers->authorization("Bearer $key") });
  my $client = MCP::Client->new(ua => $mcp->ua, url => $mcp->ua->server->url->path('/mcp'));
  $client->can('discover') ? $client->discover : $client->initialize_session;
  my $text = sub { $client->call_tool(@_)->{content}[0]{text} };

  is $text->('cavil_list_files', {package_id => $id}), "Lizenzä.txt\nNotizen-ü.txt\naltä.txt", 'decoded where UTF-8';
  is $text->('cavil_list_files', {package_id => $id, file_glob => 'Lizenzä*'}), 'Lizenzä.txt', 'globs are text too';
  like $text->('cavil_get_file', {package_id => $id, file_path => 'Lizenzä.txt'}), qr/MIT/, 'a listed name opens';
  like $text->('cavil_get_file', {package_id => $id, file_path => 'altä.txt'}),    qr/MIT/, 'so does one in Latin-1';
  is $text->('cavil_list_files', {package_id => $id, file_glob => 'altä*'}), 'altä.txt', 'and its glob';
  like $text->('cavil_create_snippet',
    {package_id => $id, file_path => 'Notizen-ü.txt', start_line => 1, end_line => 1}), qr/^Snippet \d+ created/,
    'and a snippet can be made from it';
  like $text->('cavil_get_report', {package_id => $id}), qr/`Lizenzä\.txt`/, 'the report names it readably';
};

subtest 'An ignore glob typed with the real name matches the file' => sub {
  $t->post_ok('/ignored-files' => form => {glob => 'Lizenzä.txt'})->status_is(200);
  $t->app->packages->reindex($id);
  $t->app->minion->perform_jobs;
  my $files = $t->get_ok("/reviews/report_details/$id")->status_is(200)->tx->res->json('/risks/1/0/files');
  is_deeply [map { $_->[1] } @$files], [$latin1], 'the ignored file is gone from the report';
};

subtest 'A license document with a non-ASCII name is found and reproduced' => sub {
  my $pkgs = $t->app->packages;
  my $doc  = encode('UTF-8', 'LICENSE-ä.txt');
  $pkgs->pkg_checkout_dir($id)->child($doc)->spew("SPDX-License-Identifier: MIT\nNo use by the evil empire.\n");
  $pkgs->unpack($id);
  $t->app->minion->perform_jobs;

  my $documents = $t->get_ok("/reviews/meta/$id")->status_is(200)->tx->res->json('/legal_documents/documents');
  is_deeply [map { $_->{path} } @$documents], [$doc], 'listed under its name on disk';
  is $documents->[0]{url}, "/reviews/file_view/$id/LICENSE-%C3%A4.txt", 'and linked by its bytes';

  my $path = $pkgs->document_path($id, 'dossier');
  $t->app->dossier->generate_to_file($id, $path, $pkgs->dossier_stamp($pkgs->find($id)));
  gunzip "$path" => \my $gz or die $GunzipError;
  my $dossier = decode('UTF-8', $gz);
  like $dossier,   qr/### `LICENSE-ä\.txt`/,      'the dossier reproduces it under its readable name';
  like $dossier,   qr/No use by the evil empire/, 'with the line nothing explains';
  unlike $dossier, qr/not a readable text file/,  'instead of giving up on it';
};

subtest 'An empty report on a near-empty checkout says what it contains' => sub {
  $t->get_ok("/reviews/report_details/$empty")
    ->status_is(200)
    ->json_is('/risks',          {})
    ->json_is('/missed_files',   [])
    ->json_is('/checkout_files', ['.gitattributes', '.gitignore']);
};

subtest 'The file browser shows its dotfiles too' => sub {
  my $entries = $t->get_ok("/reviews/file_view_meta/$empty/")->status_is(200)->tx->res->json->{entries};
  is_deeply [map { $_->{name} } @$entries], ['.gitattributes', '.gitignore'], 'both files, nothing of our own';
};

subtest 'A file the package ships under a name like ours is still package content' => sub {
  my $pkgs = $t->app->packages;
  $pkgs->pkg_checkout_dir($empty)->child('.report.notes')->spew("the package's own notes\n");
  $pkgs->unpack($empty);
  $t->app->minion->perform_jobs;
  $t->get_ok("/reviews/report_details/$empty")
    ->status_is(200)
    ->json_is('/checkout_files', ['.gitattributes', '.gitignore', '.report.notes']);
  my $entries = $t->get_ok("/reviews/file_view_meta/$empty/")->status_is(200)->tx->res->json->{entries};
  is_deeply [map { $_->{name} } @$entries], ['.gitattributes', '.gitignore', '.report.notes'], 'listed too';
};

subtest 'Our own files cannot be opened by path either' => sub {
  for my $path ('.unpacked.json', './.unpacked.json', '.unpacked.json/') {
    $t->get_ok("/reviews/file_view_meta/$empty/$path")->status_is(404);
    $t->get_ok("/reviews/file_raw/$empty/$path")->status_is(404);
  }
  $t->get_ok("/reviews/file_raw/$empty/.gitignore")->status_is(200)->content_is(".osc\n");

  my $entries = $t->get_ok("/reviews/file_view_meta/$empty/.")->status_is(200)->tx->res->json->{entries};
  is_deeply [map { $_->{name} } @$entries], ['.gitattributes', '.gitignore', '.report.notes'], 'nor listed through "."';

  ok !defined $t->app->snippets->from_file_path($empty, '.unpacked.json',   1, 1), 'nor turned into a snippet';
  ok !defined $t->app->snippets->from_file_path($empty, './.unpacked.json', 1, 1), 'by any spelling';
};

subtest 'A shipped symlink reaches neither our files nor outside the tree' => sub {
  my $unpacked = $t->app->packages->pkg_checkout_dir($empty)->child('.unpacked');
  symlink '.unpacked.json',                     $unpacked->child('log-link');
  symlink $cavil_test->checkout_dir->to_string, $unpacked->child('escape-link');
  for my $link (qw(log-link escape-link)) {
    $t->get_ok("/reviews/file_raw/$empty/$link")->status_is(404);
    ok !defined $t->app->snippets->from_file_path($empty, $link, 1, 1), "$link is not turned into a snippet";
  }
  $unpacked->child($_)->remove for qw(log-link escape-link);
};

subtest 'The near-empty listing carries names as they are on disk' => sub {
  my $pkgs = $t->app->packages;
  $pkgs->pkg_checkout_dir($empty)->child(encode('UTF-8', 'Lizenzänderung.txt'))->spew("nothing to see\n");
  $pkgs->unpack($empty);
  $t->app->minion->perform_jobs;
  $t->get_ok("/reviews/report_details/$empty")
    ->status_is(200)
    ->json_is('/checkout_files',
    ['.gitattributes', '.gitignore', '.report.notes', encode('UTF-8', 'Lizenzänderung.txt')]);
  ok !-e $pkgs->pkg_checkout_dir($empty)->child('.postprocessed.json.new'), 'the manifest was moved into place';
};

subtest 'A checkout too big to list, or mid re-unpack, is not listed' => sub {
  my $pkgs = $t->app->packages;
  my $dir  = $pkgs->pkg_checkout_dir($empty);
  $dir->child("empty_$_.txt")->spew("nothing to see\n") for 1 .. 21;
  $pkgs->unpack($empty);
  $t->app->minion->perform_jobs;
  is $pkgs->find($empty)->{unpacked_files}, 25, 'all files unpacked';
  $t->get_ok("/reviews/report_details/$empty")
    ->status_is(200)
    ->json_is('/risks',          {})
    ->json_is('/checkout_files', undef);

  # Between the unpack and the index job the count is unset, then stale, while the old report stays live
  $pkgs->unpacked($empty);
  $t->get_ok("/reviews/report_details/$empty")->status_is(200)->json_is('/checkout_files', undef);
  $pkgs->update_file_stats($empty, {files => 2, size => 49});
  $t->get_ok("/reviews/report_details/$empty")->status_is(200)->json_is('/checkout_files', undef);
};

done_testing();
