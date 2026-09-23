# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Mojo::Base -strict, -signatures;

use FindBin;
use lib "$FindBin::Bin/lib";

use Test::More;
use Test::Mojo;
use Cavil::Test;
use Mojo::File qw(path curfile tempdir);
use Mojo::JSON qw(decode_json encode_json);
use Cavil::Checkout;
use Cavil::Util qw(encode_json_fast extract_urls_and_emails);
use Time::HiRes qw(time);

plan skip_all => 'set TEST_ONLINE to enable this test' unless $ENV{TEST_ONLINE};

my $dir = path(__FILE__)->dirname->child('legal-bot');

my $TMP = tempdir;

sub temp_copy (@path) {
  my $from   = $dir->child(@path);
  my $target = $TMP->child(@path)->make_path;
  $_->copy_to($target->child($_->basename)) for $from->list({hidden => 1})->each;

  my $deb_test = $from->child('debian');
  if (-d $deb_test) {
    my $deb_dir = $target->child('debian')->make_path;
    $_->copy_to($deb_dir->child($_->basename)) for $deb_test->list->each;
  }

  return $target;
}

subtest 'URLs and email addresses' => sub {
  subtest 'all four forms are recognised' => sub {
    my $meta = extract_urls_and_emails(<<'EOF');
Sebastian Riedel <sri@cpan.org> wrote this.
Reported by nobody@nowhere.invalid too.
<a href="mailto:kraih@kraih.com" >Sebastian Riedel</a>
See http://mojolicious.org and ftp://ftp.gnu.org/pub for more.
EOF
    is_deeply [sort keys %{$meta->{emails}}], ['kraih@kraih.com', 'nobody@nowhere.invalid', 'sri@cpan.org'],
      'right email addresses';
    is $meta->{emails}{'sri@cpan.org'}{name},    'Sebastian Riedel', 'name in front of the address';
    is $meta->{emails}{'kraih@kraih.com'}{name}, 'Sebastian Riedel', 'name after a mailto: link';

    # Any two words in front of an address are taken for a name, so an address in running prose picks up
    # whatever preceded it. Only all-lowercase and punctuated candidates are rejected
    is $meta->{emails}{'nobody@nowhere.invalid'}{name}, 'Reported by', 'preceding words taken for a name';
    is_deeply [sort keys %{$meta->{urls}}], ['ftp://ftp.gnu.org/pub', 'http://mojolicious.org'], 'right URLs';
  };

  subtest 'repeated values are counted, not duplicated' => sub {
    my $meta = extract_urls_and_emails(join "\n\n", map {"Contact: sri\@cpan.org and http://mojolicious.org"} 1 .. 4);
    is_deeply [keys %{$meta->{emails}}], ['sri@cpan.org'], 'one email address';
    is $meta->{emails}{'sri@cpan.org'}{count}, 4, 'address counted once per occurrence';
    is_deeply [keys %{$meta->{urls}}], ['http://mojolicious.org'], 'one URL';
    is $meta->{urls}{'http://mojolicious.org'}, 4, 'URL counted once per occurrence';
  };

  subtest 'placeholder and unusable values are skipped' => sub {
    my $meta = extract_urls_and_emails(<<'EOF');
someone@example.com and http://www.example.org/ are placeholders (RFC 2606)
file:///etc/passwd is not interesting
bad@-nope.de is not a legal address (RFC 822)
EOF
    is_deeply $meta->{emails}, {}, 'no email addresses';
    is_deeply $meta->{urls},   {}, 'no URLs';
  };

  subtest 'malformed input is survivable' => sub {
    for my $case (
      ['empty'         => ''],
      ['invalid UTF-8' => "\xff\xfe\x00bad\@\x80\xc3(\x28"],
      ['NUL bytes'     => join "\0", 'sri@cpan.org', 'http://mojolicious.org'],
      ['no final NL'   => "x\r\n" x 500 . 'z' x 1500],
      ['nothing but @' => '@' x 30000],
      ['nothing but :' => '://' x 10000]
      )
    {
      my ($name, $text) = @$case;
      ok eval { extract_urls_and_emails($text); 1 }, "survives $name";
    }
  };

  # Text with no whitespace used to make the address branches quadratic: the local-part class rescanned
  # to end of buffer from every start position, so a single file at the 30KB slurp cap cost seconds. The
  # bounded quantifiers in Cavil::Checkout make it linear again. Doubling the input and comparing is what
  # the guard is worth having: the ratio is ~2 while this is linear and ~4 if it goes quadratic again,
  # and unlike a wall-clock limit it means the same thing on a fast desktop and a loaded CI runner. The
  # trailing "@" is deliberate, so the text gets past the index() shortcut and the bounds are measured.
  subtest 'pathological input stays linear' => sub {
    my $scan = sub ($size) {
      my $text = substr('a.' x $size, 0, $size - 1) . '@';
      my $best = 9e9;
      for (1 .. 3) {
        my $start = time;
        my $meta  = extract_urls_and_emails($text);
        my $spent = time - $start;
        $best = $spent if $spent < $best;
        is_deeply $meta, {emails => {}, urls => {}}, "nothing extracted from ${size} bytes" if $_ == 1;
      }
      return $best;
    };
    my $ratio = $scan->(30000) / $scan->(15000);
    ok $ratio < 3, sprintf('doubling the input doubled the work (ratio %.2f, quadratic would be ~4)', $ratio);
  };
};

subtest 'ceph-image (kiwi)' => sub {
  my $ceph     = temp_copy('ceph-image', '5fcfdab0e71b0bebfdf8b5cc3badfecf');
  my $checkout = Cavil::Checkout->new($ceph);
  $checkout->unpack;
  my $stats = $checkout->unpacked_file_stats;
  is $stats->{files}, 5, 'right number of files';

  # Smaller than the raw sources: the .kiwi and tumbleweed.xml are markup and are stripped to text
  # before indexing
  is $stats->{size}, 1834, 'right size';
};

subtest 'perl-Mojolicious' => sub {
  my $mojo_temp_dir = temp_copy('perl-Mojolicious', 'c7cfdab0e71b0bebfdf8b2dc3badfecd');
  Cavil::Checkout->new($mojo_temp_dir)->unpack;
  my $json = $mojo_temp_dir->child('.unpacked.json');
  ok -f $json, 'log file exists';
  my $hash = decode_json($json->slurp);
  is $hash->{destdir}, $mojo_temp_dir->child('.unpacked'), 'right destination';
  is $hash->{pid},     $$,                                 'right process id';
  is_deeply $hash->{unpacked}{'Mojolicious-7.25/LICENSE'}, {mime => 'text/plain'}, 'right structure';
  ok -f $mojo_temp_dir->child('.unpacked', 'Mojolicious-7.25', 'LICENSE'), 'license file exists';
  my $module = $mojo_temp_dir->child('.unpacked', 'Mojolicious-7.25', 'lib', 'Mojolicious.pm');
  ok -f $module, 'module exists';

  # Check post processed
  $json = $mojo_temp_dir->child('.postprocessed.json');
  ok -f $json, '2nd log file exists';
  $hash = decode_json($json->slurp);

  my $maxed_file = 'Mojolicious-7.25/README.processed.md';
  is_deeply $hash->{unpacked}->{$maxed_file}, {mime => 'text/plain'}, 'file was maxed';
};

subtest 'error-broken-archive' => sub {
  my $eba      = temp_copy('error-broken-archive', 'cb5e100e5a9a3e7f6d1fd97512215282');
  my $checkout = Cavil::Checkout->new($eba);
  $checkout->unpack;
  my $json = $eba->child('.unpacked.json');
  ok -f $json, 'log file exists';
  my $hash = decode_json($json->slurp);
  is $hash->{destdir}, $eba->child('.unpacked'), 'right destination';
  is $hash->{pid},     $$,                       'right process id';
  is_deeply $hash->{unpacked}{'error-broken-archive/test.txt'}, {mime => 'text/plain'}, 'right structure';
};

subtest 'Derived documents never reach the unpacked tree' => sub {
  my $co  = $TMP->child('report-exclude', 'hash')->make_path;
  my $src = $TMP->child('report-exclude-src')->make_path;
  $src->child('hello.txt')->spew("hello world\n");
  $src->child('vendor')->make_path->child('.report.json')->spew(qq({"tool": "not ours"}\n));
  is system('tar', '-czf', $co->child('src.tar.gz')->to_string, '-C', $src->to_string, '.'), 0, 'archive built';

  # A previous run's documents sit in the checkout dir
  $co->child('.report.spdx.json')->spew('{"spdxVersion":"SPDX-2.3","packages":[' . ('{"n":"x"},' x 200) . '{}]}');
  is system('gzip', $co->child('.report.spdx.json')->to_string), 0, 'report gzipped';
  $co->child('.report.notice.txt')->spew("NOTICE\n\nPermission is hereby granted, free of charge\n");
  is system('gzip', $co->child('.report.notice.txt')->to_string), 0, 'notice gzipped';

  Cavil::Checkout->new($co)->unpack;

  my $hash = decode_json($co->child('.postprocessed.json')->slurp)->{unpacked};
  ok !(grep {m{^\.report\.}} keys %$hash),             'no derived document in the unpacked set';
  ok !-e $co->child('.unpacked', '.report.spdx.json'), 'the report was not exploded into .unpacked';

  # A NOTICE is nothing but license text, so indexing one would match every license it reproduces
  ok !-e $co->child('.unpacked', '.report.notice.txt'), 'nor the notice';
  ok !-e $co->child('.report.spdx.json.gz'),            'the stale documents are gone from the checkout dir';
  ok !-e $co->child('.report.notice.txt.gz'),           'both of them';

  ok +(grep {m{hello\.txt$}} keys %$hash),            'real source files are still unpacked';
  ok +(grep {m{vendor/\.report\.json$}} keys %$hash), "and so is a package's own .report file";
};

subtest 'Generated SPDX reports are never handed to the indexer' => sub {
  my $co = $TMP->child('report-leak', 'hash')->make_path;

  # Simulate a re-unpacked checkout whose previous SPDX report reappeared and, for the uncompressed
  # copy, was line-wrapped by postprocess into ".report.spdx.processed.json".
  $co->child('.postprocessed.json')->spew(
    encode_json {
      destdir  => $co->child('.unpacked')->to_string,
      unpacked => {
        'src/real.txt'                => {mime => 'text/plain'},
        '.report.spdx.json'           => {mime => 'text/plain'},
        '.report.spdx.processed.json' => {mime => 'text/plain'},
        '.report.spdx.json.gz'        => {mime => 'application/gzip'},
        '.report.processed.spdx.json' => {mime => 'text/plain'},
      }
    }
  );

  my $files = Cavil::Checkout->new($co)->unpacked_files;
  is_deeply [sort map { $_->[0] } @$files], ['src/real.txt'],
    'every .report.spdx variant (incl. the .processed one) is skipped, only real files remain';
};

subtest 'Markup files are stripped during unpack' => sub {
  my $co   = $TMP->child('markup-checkout', 'hash')->make_path;
  my $long = join ' ', ('Permission is hereby granted free of charge to any person obtaining a copy') x 3;
  $co->child('readme.html')
    ->spew(qq{<html><body><h1>License</h1><p>$long</p><p>Redistribution &amp; use permitted.</p></body></html>});

  my $checkout = Cavil::Checkout->new($co);
  $checkout->unpack;

  my $files = $checkout->unpacked_files;
  ok +(grep { $_->[0] =~ m{(?:^|/)readme\.processed\.html$} } @$files), 'indexer sees the stripped .processed.html';
  ok !(grep { $_->[0] =~ m{(?:^|/)readme\.html$} } @$files),            'raw readme.html is not indexed';

  my ($rel) = map { $_->[0] } grep { $_->[0] =~ m{readme\.processed\.html$} } @$files;
  my $stripped = $co->child('.unpacked', split m{/}, $rel)->slurp;
  like $stripped,   qr/Permission is hereby granted free of charge/, 'license text extracted';
  like $stripped,   qr/Redistribution & use permitted/,              'HTML entity decoded';
  unlike $stripped, qr/<html|<body|<h1|<p>/,                         'markup tags removed';
};

subtest 'A file list with non-ASCII names is read back whole' => sub {
  my $co = $TMP->child('non-ascii', 'hash')->make_path;

  # A hash with more than a handful of distinct non-ASCII keys is what used to wedge the unpack job
  # forever while it wrote this very file, so build one big enough to have done it
  my @accented = split //, "\x{e9}\x{f8}\x{142}\x{fc}\x{e7}";
  my %unpacked = map { ("src/caf$accented[$_ % @accented]-$_.txt" => {mime => 'text/plain'}) } 1 .. 100;
  $co->child('.postprocessed.json')
    ->spew(encode_json_fast {destdir => $co->child('.unpacked')->to_string, unpacked => \%unpacked});

  my $checkout = Cavil::Checkout->new($co);
  my $files    = $checkout->unpacked_files;
  is scalar @$files, 100, 'every file is handed to the indexer';
  is_deeply [sort keys %unpacked], [map { $_->[0] } @$files], 'with their names intact';
  is $checkout->unpacked_file_stats->{files}, 100, 'and the stats agree on the count';
};

subtest 'The file list is only read once per checkout, and re-read after a new unpack' => sub {
  my $co = $TMP->child('file-list-cache', 'hash')->make_path;
  $co->child('first.txt')->spew("Licensed under the MIT license.\n");

  my $checkout = Cavil::Checkout->new($co);
  $checkout->unpack;
  is_deeply [map { $_->[0] } @{$checkout->unpacked_files}], ['first.txt'], 'one file';

  # Reading it again must not go back to disk, so a file list removed underneath us changes nothing
  my $list = $co->child('.postprocessed.json');
  my $json = $list->slurp;
  $list->remove;
  is_deeply [map { $_->[0] } @{$checkout->unpacked_files}], ['first.txt'], 'the second read is cached';
  is $checkout->unpacked_file_stats->{files}, 1, 'and the stats use the same copy';
  $list->spew($json);

  # A re-unpack replaces the sources, so the same object has to see the new list
  $co->child('second.txt')->spew("Licensed under the Apache-2.0 license.\n");
  $checkout->unpack;
  is_deeply [sort map { $_->[0] } @{$checkout->unpacked_files}], ['first.txt', 'second.txt'],
    'the cache was dropped by the new unpack';
};

subtest 'Unpack background job' => sub {
  my $cavil_test = Cavil::Test->new(online => $ENV{TEST_ONLINE}, schema => 'unpack_test_mojo');
  my $t          = Test::Mojo->new(Cavil => $cavil_test->default_config);
  $cavil_test->mojo_fixtures($t->app);

  ok !$t->app->packages->is_unpacked(1), 'not unpacked yet';
  my $minion = $t->app->minion;
  my $job_id = $minion->enqueue(unpack => [1]);
  $minion->perform_jobs;
  ok $t->app->packages->is_unpacked(1), 'unpacked';
  unlike $minion->job($job_id)->info->{result}, qr/Package \d+ is already being processed/, 'no race condition';

  my $dir  = $cavil_test->checkout_dir->child('perl-Mojolicious', 'c7cfdab0e71b0bebfdf8b2dc3badfecd');
  my $json = $dir->child('.unpacked.json');
  ok -f $json, 'log file exists';
  my $hash = decode_json($json->slurp);
  is $hash->{destdir}, $dir->child('.unpacked'), 'right destination';
  ok -f $dir->child('.unpacked', 'Mojolicious-7.25', 'LICENSE'), 'license file exists';
  my $module = $dir->child('.unpacked', 'Mojolicious-7.25', 'lib', 'Mojolicious.pm');
  ok -f $module,                               'module exists';
  ok -f $t->app->patterns->matcher_cache_file, 'cache initialized';

  # Prevent import race condition
  ok $minion->job($job_id)->retry, 'unpack job retried';
  ok my $guard = $t->app->packages->claim_guard(1, 999999), 'package claimed by another job';
  my $worker = $minion->worker->register;
  ok my $job = $worker->dequeue(0, {id => $job_id}), 'job dequeued';
  is $job->execute, undef, 'no error';
  like $minion->job($job_id)->info->{result}, qr/Package \d+ is already being processed/, 'race condition prevented';
  $worker->unregister;
  undef $guard;
  is $t->app->packages->find(1)->{processing_job}, undef, 'package no longer claimed';
};

subtest 'Unpack background job (with exclude file)' => sub {
  my $cavil_test = Cavil::Test->new(online => $ENV{TEST_ONLINE}, schema => 'unpack_test_buildah');
  my $config     = $cavil_test->default_config;
  $config->{exclude_file} = curfile->sibling('exclude-files', 'checkout.exclude')->to_string;
  my $t = Test::Mojo->new(Cavil => $config);
  $cavil_test->unpack_fixtures($t->app);

  my $minion = $t->app->minion;

  ok !$t->app->packages->is_unpacked(1), 'not unpacked yet';
  $minion->enqueue(unpack => [1]);
  $minion->perform_jobs;
  ok $t->app->packages->is_unpacked(1), 'unpacked';
  my $good = path($t->app->packages->pkg_checkout_dir(1));
  ok -e $good->child('.unpacked',  'foo', 'bar.txt');
  ok !-e $good->child('.unpacked', 'foo', 'bar', 'bar.tar');
  ok -e $good->child('.unpacked',  'foo', 'bar', 'bar');
  ok -e $good->child('.unpacked',  'foo', 'bar', 'bar', 'test.js');

  ok !$t->app->packages->is_unpacked(2), 'not unpacked yet';
  $minion->enqueue(unpack => [2]);
  $minion->perform_jobs;
  ok $t->app->packages->is_unpacked(2), 'unpacked';
  my $good_too = path($t->app->packages->pkg_checkout_dir(2));
  ok -e $good_too->child('.unpacked',  'foo', 'bar.txt');
  ok -e $good_too->child('.unpacked',  'foo', 'bar', 'bar.tar');
  ok !-e $good_too->child('.unpacked', 'foo', 'bar', 'bar');
  ok !-e $good_too->child('.unpacked', 'foo', 'bar', 'bar', 'test.js');

  ok !$t->app->packages->is_unpacked(3), 'not unpacked yet';
  $minion->enqueue(unpack => [3]);
  $minion->perform_jobs;
  ok $t->app->packages->is_unpacked(3), 'unpacked';
  my $broken = path($t->app->packages->pkg_checkout_dir(3));
  ok -e $broken->child('.unpacked',  'foo', 'bar.txt');
  ok -e $broken->child('.unpacked',  'foo', 'bar', 'test-case.tar');
  ok !-e $broken->child('.unpacked', 'foo', 'bar', 'test-case');
};

done_testing;
