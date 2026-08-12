#!/usr/bin/perl
# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Mojo::Base -strict, -signatures;

use Cpanel::JSON::XS ();
use Mojo::File       qw(curfile);
use Mojo::JSON       qw(decode_json);
use Mojo::UserAgent;
use Mojo::Util qw(html_unescape trim);

# Canonical, indented JSON keeps generated diffs deterministic and readable.
# Drop unused OSADL timestamps so unchanged data remains unchanged.
my $JSON = Cpanel::JSON::XS->new->canonical->utf8->indent->space_after;

my $LICENSE_URL   = 'https://spdx.org/licenses/';
my $EXCEPTION_URL = 'https://spdx.org/licenses/exceptions-index.html';
my $CHANGES_URL = 'https://raw.githubusercontent.com/openSUSE/obs-service-format_spec_file/master/licenses_changes.txt';
my $SCANCODE_URL = 'https://scancode-licensedb.aboutcode.org/index.json';
my $OSADL_URL    = 'https://www.osadl.org/fileadmin/checklists/matrixseqexpl.json';
my $FLAGS_URL    = 'https://raw.githubusercontent.com/spdx/license-list-data/main/json/licenses.json';

my $dir              = curfile->dirname->dirname->child('lib', 'Cavil', 'resources');
my $license_file     = $dir->child('license_list.txt');
my $exception_file   = $dir->child('license_exceptions.txt');
my $changes_file     = $dir->child('license_changes.txt');
my $scancode_file    = $dir->child('license_list_scancode.txt');
my $osadl_file       = $dir->child('license_compatibility.json');
my $obligations_file = $dir->child('license_obligations.json');
my $flags_file       = $dir->child('license_flags.json');

my $ua = Mojo::UserAgent->new;

# Retry transient failures so one of many sequential requests does not discard prior work.
# In particular, OSADL's AAAA records can fail on hosts without an IPv6 route.
my $RETRIES = 5;

sub fetch ($url) {
  for my $attempt (1 .. $RETRIES) {
    my $tx  = $ua->get($url);
    my $err = $tx->error;
    return $tx->result unless $err;
    die qq(Cannot fetch "$url": $err->{code} $err->{message}\n) if $err->{code} && $err->{code} < 500;
    warn qq(Fetching "$url" failed ($err->{message}), attempt $attempt of $RETRIES\n);
    sleep 1;
  }
  die qq(Cannot fetch "$url": giving up after $RETRIES attempts\n);
}

my $dom = fetch($LICENSE_URL)->dom;
my @licenses;
for my $license ($dom->at('table')->find('code[property="spdx:licenseId"]')->each) {
  push @licenses, $license->text;
}
$license_file->spew(join("\n", sort @licenses) . "\n");
say qq(Updated @{[scalar @licenses]} licenses in "$license_file");

$dom = fetch($EXCEPTION_URL)->dom;
my @exceptions;
for my $exception ($dom->at('table')->find('code[property="spdx:licenseExceptionId"]')->each) {
  push @exceptions, $exception->text;
}
$exception_file->spew(join("\n", sort @exceptions) . "\n");
say qq(Updated @{[scalar @exceptions]} exceptions in "$exception_file");

# Missing FSF status means no ruling, not "not free"; preserve that distinction.
# Deprecated identifiers cannot reach reports and are omitted.
my $spdx = decode_json(fetch($FLAGS_URL)->body);
my %flags;
for my $license (@{$spdx->{licenses}}) {
  next if $license->{isDeprecatedLicenseId};
  my $entry = $flags{$license->{licenseId}} = {osi => $license->{isOsiApproved} ? \1 : \0};
  $entry->{fsf} = $license->{isFsfLibre} ? \1 : \0 if exists $license->{isFsfLibre};
}
$flags_file->spew($JSON->encode({source => $FLAGS_URL, licenses => \%flags}));
say qq(Updated @{[scalar keys %flags]} SPDX license flags in "$flags_file");

my $text = fetch($CHANGES_URL)->text;
$changes_file->spew($text);
my $num = split("\n", $text) - 1;
say qq(Updated $num license changes in "$changes_file");

# ScanCode LicenseDB (for BSI TR-03183-2 "LicenseRef-scancode-*" identifiers). The data is licensed
# CC-BY-4.0 and requires attribution; see the NOTICE file.
my $scancode = decode_json(fetch($SCANCODE_URL)->body);
my @scancode_keys;
for my $license (@$scancode) {
  next if $license->{is_exception} || $license->{is_deprecated};
  push @scancode_keys, $license->{license_key};
}
$scancode_file->spew(join("\n", sort @scancode_keys) . "\n");
say qq(Updated @{[scalar @scancode_keys]} ScanCode licenses in "$scancode_file");

# Compatible cells are implied by absence; preserve all other directional results verbatim.
my $osadl = decode_json(fetch($OSADL_URL)->body);
my (%matrix, $cells);
for my $outbound (@{$osadl->{licenses}}) {
  my $a = $outbound->{name};
  for my $cell (@{$outbound->{compatibilities}}) {
    my $b = $cell->{name};
    next if $a eq $b;
    my $c = $cell->{compatibility};
    next unless $c eq 'No' || $c eq 'Check dependency' || $c eq 'Unknown';

    # OSADL explanations contain HTML entities (e.g. &quot;); decode them so the stored text is plain
    # and renders correctly in the web, text and MCP reports alike.
    $matrix{$a}{$b} = {compatibility => $c, explanation => html_unescape($cell->{explanation})};
    $cells++;
  }
}
$osadl_file->spew($JSON->encode({source => $OSADL_URL, matrix => \%matrix}));
say qq(Updated $cells OSADL compatibility cells in "$osadl_file");

# SPDX identifiers join obligation checklists with copyleft and disclosure data.
my $osadl_checklists = 'https://www.osadl.org/fileadmin/checklists';

my $copyleft   = decode_json(fetch("$osadl_checklists/copyleft.json")->body)->{copyleft}           // {};
my $disclosure = decode_json(fetch("$osadl_checklists/sourcedisclosure.json")->body)->{disclosure} // {};

my %obligations;
my $opt_list = fetch("$osadl_checklists/all/jsonlicenses-opt.txt")->text;
for my $url (split "\n", $opt_list) {
  $url = trim($url);
  next unless $url =~ m!/([^/]+)-opt\.json$!;
  my $name  = $1;
  my $entry = decode_json(fetch($url)->body)->{$name} or next;
  $obligations{$name} = {patent_hints => $entry->{'PATENT HINTS'}, use_cases => $entry->{'USE CASE'} // {}};
}

# Preserve classifications even when no full checklist exists.
for my $name (keys %$copyleft, keys %$disclosure) {
  my $entry = $obligations{$name} //= {};
  $entry->{copyleft}          = $copyleft->{$name}   if defined $copyleft->{$name};
  $entry->{source_disclosure} = $disclosure->{$name} if defined $disclosure->{$name};
}

$obligations_file->spew($JSON->encode({source => "$osadl_checklists/", licenses => \%obligations}));
say qq(Updated @{[scalar keys %obligations]} OSADL obligation checklists in "$obligations_file");
