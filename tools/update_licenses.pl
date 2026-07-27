#!/usr/bin/perl
use Mojo::Base -strict, -signatures;

use Cpanel::JSON::XS ();
use Mojo::File       qw(curfile);
use Mojo::JSON       qw(decode_json);
use Mojo::UserAgent;
use Mojo::Util qw(html_unescape trim);

# Bundled JSON resources are written alphabetically sorted and indented, so regenerating one only
# produces a diff where the upstream data actually changed, and that diff is readable line by line.
# Neither can be taken for granted otherwise: upstream key order is arbitrary, Perl randomizes hash
# order per process, and a single-line 1.6MB file reports every change as a whole-file rewrite. The
# encoder lives here because Mojo::JSON offers neither option. Bytes in, bytes out: the fetched
# bodies are UTF-8 and OSADL escapes non-ASCII (e.g. the copyright sign as ©), which decode_json
# turns into characters and this encoder writes back out as UTF-8. Indented output is newline
# terminated already, so callers must not append one.
#
# OSADL stamps every rebuild of their data with a fresh timestamp, whether or not anything changed,
# and nothing in Cavil reads it - so it is deliberately not carried into the bundles. Provenance is
# the "source" URL plus the NOTICE file.
my $JSON = Cpanel::JSON::XS->new->canonical->utf8->indent->space_after;

my $LICENSE_URL   = 'https://spdx.org/licenses/';
my $EXCEPTION_URL = 'https://spdx.org/licenses/exceptions-index.html';
my $CHANGES_URL = 'https://raw.githubusercontent.com/openSUSE/obs-service-format_spec_file/master/licenses_changes.txt';
my $SCANCODE_URL = 'https://scancode-licensedb.aboutcode.org/index.json';
my $OSADL_URL    = 'https://www.osadl.org/fileadmin/checklists/matrixseqexpl.json';

my $dir              = curfile->dirname->dirname->child('lib', 'Cavil', 'resources');
my $license_file     = $dir->child('license_list.txt');
my $exception_file   = $dir->child('license_exceptions.txt');
my $changes_file     = $dir->child('license_changes.txt');
my $scancode_file    = $dir->child('license_list_scancode.txt');
my $osadl_file       = $dir->child('license_compatibility.json');
my $obligations_file = $dir->child('license_obligations.json');

my $ua = Mojo::UserAgent->new;

# A full run makes well over a hundred sequential requests, so a single hiccup must not throw away
# the ones already done. Connection errors are worth another try; an HTTP status below 500 means the
# server answered and disagreed, so that is fatal right away. One case is common enough to name:
# OSADL publishes AAAA records, and on a dual-stack host without an IPv6 default route a fraction of
# connects fail immediately with "Network is unreachable" because Mojo::UserAgent picks whichever
# address the resolver returned first and, unlike curl, does not fall back to the other family.
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

# Licenses
my $dom = fetch($LICENSE_URL)->dom;
my @licenses;
for my $license ($dom->at('table')->find('code[property="spdx:licenseId"]')->each) {
  push @licenses, $license->text;
}
$license_file->spew(join("\n", sort @licenses) . "\n");
say qq(Updated @{[scalar @licenses]} licenses in "$license_file");

# Exceptions
$dom = fetch($EXCEPTION_URL)->dom;
my @exceptions;
for my $exception ($dom->at('table')->find('code[property="spdx:licenseExceptionId"]')->each) {
  push @exceptions, $exception->text;
}
$exception_file->spew(join("\n", sort @exceptions) . "\n");
say qq(Updated @{[scalar @exceptions]} exceptions in "$exception_file");

# License changes (OBS)
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

# OSADL license compatibility matrix. The data is licensed CC-BY-4.0 and requires attribution; see
# the NOTICE file. The upstream matrix is a ~3MB directed grid (outbound -> inbound) of SPDX-named
# licenses, each cell graded Same/Yes/No/Check dependency/Unknown with a human-readable explanation.
# We store it verbatim as a directed matrix, keeping only the cells that are not plainly compatible
# (No / Check dependency / Unknown) - the "Yes"/"Same" cells are implied by absence. Cavil presents
# this per package as OSADL's own sub-matrix, so no collapsing, curation or reinterpretation happens
# here; the directional structure and the explanations are preserved exactly as OSADL publishes them.
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

# OSADL obligation checklists plus the copyleft and source-code-disclosure classifications. Same
# CC-BY-4.0 data and attribution as the compatibility matrix (see the NOTICE file), refreshed here
# alongside it. OSADL publishes one obligation checklist per license, grouped by delivery use case
# ("Source code delivery" / "Binary delivery") with nested "IF" conditions, "YOU MUST"/"YOU MUST NOT"
# obligations and "EITHER"/"OR" alternatives, plus small copyleft and source-disclosure tables. We
# bundle the checklists verbatim and fold in the two classifications, so Cavil can present OSADL's own
# obligation view per license - with room for other sources later, exactly like the compatibility
# matrix. Everything is keyed by SPDX identifier.
my $osadl_checklists = 'https://www.osadl.org/fileadmin/checklists';

my $copyleft   = decode_json(fetch("$osadl_checklists/copyleft.json")->body)->{copyleft}           // {};
my $disclosure = decode_json(fetch("$osadl_checklists/sourcedisclosure.json")->body)->{disclosure} // {};

# One optimized checklist file per license; the list file holds their URLs, one per line.
my %obligations;
my $opt_list = fetch("$osadl_checklists/all/jsonlicenses-opt.txt")->text;
for my $url (split "\n", $opt_list) {
  $url = trim($url);
  next unless $url =~ m!/([^/]+)-opt\.json$!;
  my $name  = $1;
  my $entry = decode_json(fetch($url)->body)->{$name} or next;
  $obligations{$name} = {patent_hints => $entry->{'PATENT HINTS'}, use_cases => $entry->{'USE CASE'} // {}};
}

# Fold in copyleft / source-disclosure for every license either table knows about, even the few that
# have no full checklist, so all the verified information OSADL provides is bundled.
for my $name (keys %$copyleft, keys %$disclosure) {
  my $entry = $obligations{$name} //= {};
  $entry->{copyleft}          = $copyleft->{$name}   if defined $copyleft->{$name};
  $entry->{source_disclosure} = $disclosure->{$name} if defined $disclosure->{$name};
}

$obligations_file->spew($JSON->encode({source => "$osadl_checklists/", licenses => \%obligations}));
say qq(Updated @{[scalar keys %obligations]} OSADL obligation checklists in "$obligations_file");
