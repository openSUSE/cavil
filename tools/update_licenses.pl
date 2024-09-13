#!/usr/bin/perl
use Mojo::Base -strict, -signatures;

use Mojo::File qw(curfile);
use Mojo::UserAgent;

my $LICENSE_URL   = 'https://spdx.org/licenses/';
my $EXCEPTION_URL = 'https://spdx.org/licenses/exceptions-index.html';
my $CHANGES_URL = 'https://raw.githubusercontent.com/openSUSE/obs-service-format_spec_file/master/licenses_changes.txt';

my $dir            = curfile->dirname->dirname->child('lib', 'Cavil', 'resources');
my $license_file   = $dir->child('license_list.txt');
my $exception_file = $dir->child('license_exceptions.txt');
my $changes_file   = $dir->child('license_changes.txt');

my $ua = Mojo::UserAgent->new;

# Licenses
my $dom = $ua->get($LICENSE_URL)->result->dom;
my @licenses;
for my $license ($dom->at('table')->find('code[property="spdx:licenseId"]')->each) {
  push @licenses, $license->text;
}
$license_file->spew(join("\n", sort @licenses) . "\n");
say qq(Updated @{[scalar @licenses]} licenses in "$license_file");

# Exceptions
$dom = $ua->get($EXCEPTION_URL)->result->dom;
my @exceptions;
for my $exception ($dom->at('table')->find('code[property="spdx:licenseExceptionId"]')->each) {
  push @exceptions, $exception->text;
}
$exception_file->spew(join("\n", sort @exceptions) . "\n");
say qq(Updated @{[scalar @exceptions]} exceptions in "$exception_file");

# License changes (OBS)
my $text = $ua->get($CHANGES_URL)->result->text;
$changes_file->spew($text);
my $num = split("\n", $text) - 1;
say qq(Updated $num license changes in "$changes_file");
