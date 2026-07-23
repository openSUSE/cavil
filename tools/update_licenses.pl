#!/usr/bin/perl
use Mojo::Base -strict, -signatures;

use Mojo::File qw(curfile);
use Mojo::JSON qw(from_json to_json);
use Mojo::UserAgent;
use Mojo::Util qw(html_unescape);

my $LICENSE_URL   = 'https://spdx.org/licenses/';
my $EXCEPTION_URL = 'https://spdx.org/licenses/exceptions-index.html';
my $CHANGES_URL = 'https://raw.githubusercontent.com/openSUSE/obs-service-format_spec_file/master/licenses_changes.txt';
my $SCANCODE_URL = 'https://scancode-licensedb.aboutcode.org/index.json';
my $OSADL_URL    = 'https://www.osadl.org/fileadmin/checklists/matrixseqexpl.json';

my $dir            = curfile->dirname->dirname->child('lib', 'Cavil', 'resources');
my $license_file   = $dir->child('license_list.txt');
my $exception_file = $dir->child('license_exceptions.txt');
my $changes_file   = $dir->child('license_changes.txt');
my $scancode_file  = $dir->child('license_list_scancode.txt');
my $osadl_file     = $dir->child('license_compatibility.json');

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

# ScanCode LicenseDB (for BSI TR-03183-2 "LicenseRef-scancode-*" identifiers). The data is licensed
# CC-BY-4.0 and requires attribution; see the NOTICE file.
my $scancode = from_json($ua->get($SCANCODE_URL)->result->body);
my @scancode_keys;
for my $license (@$scancode) {
  next if $license->{is_exception} || $license->{is_deprecated};
  push @scancode_keys, $license->{license_key};
}
$scancode_file->spew(join("\n", sort @scancode_keys) . "\n");
say qq(Updated @{[scalar @scancode_keys]} ScanCode licenses in "$scancode_file");

# OSADL license compatibility matrix. The data is licensed CC-BY-4.0 and requires attribution; see
# the NOTICE file. The upstream matrix is a ~3MB directed grid (outbound -> inbound) of SPDX-named
# licenses, each cell graded Same/Yes/No/Check dependency/Unknown with a human-readable explanation.
# We store it verbatim as a directed matrix, keeping only the cells that are not plainly compatible
# (No / Check dependency / Unknown) - the "Yes"/"Same" cells are implied by absence. Cavil presents
# this per package as OSADL's own sub-matrix, so no collapsing, curation or reinterpretation happens
# here; the directional structure and the explanations are preserved exactly as OSADL publishes them.
my $osadl = from_json($ua->get($OSADL_URL)->result->body);
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
$osadl_file->spew(to_json({source => $OSADL_URL, timestamp => $osadl->{timestamp}, matrix => \%matrix}) . "\n");
say qq(Updated $cells OSADL compatibility cells in "$osadl_file");
