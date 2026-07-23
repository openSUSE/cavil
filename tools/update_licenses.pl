#!/usr/bin/perl
use Mojo::Base -strict, -signatures;

use Mojo::File qw(curfile);
use Mojo::JSON qw(from_json to_json);
use Mojo::UserAgent;

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
my $osadl_file     = $dir->child('license_incompatibilities.json');

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
# Cavil only surfaces the problematic combinations, so we collapse the grid into a compact list of
# unordered incompatible pairs: a pair is flagged when *either* direction says "No" (hard
# incompatibility) or, failing that, "Check dependency" (softer advisory). We keep the explanation of
# the flagging direction (preferring the sorted-first license as the outbound one when both agree).
my $osadl = from_json($ua->get($OSADL_URL)->result->body);
my %osadl_cells;
for my $outbound (@{$osadl->{licenses}}) {
  my $a = $outbound->{name};
  for my $cell (@{$outbound->{compatibilities}}) {
    $osadl_cells{$a}{$cell->{name}} = $cell;
  }
}
my %osadl_pairs;
for my $a (sort keys %osadl_cells) {
  for my $b (sort keys %{$osadl_cells{$a}}) {
    next if $a eq $b;
    my ($x, $y) = sort ($a, $b);
    next if $osadl_pairs{"$x\0$y"};    # already decided from the other direction

    # Prefer the sorted-first license as outbound for a stable explanation, but flag on either
    # direction and let "No" win over "Check dependency".
    my $xy = $osadl_cells{$x}{$y};
    my $yx = $osadl_cells{$y}{$x};
    my ($compatibility, $explanation);
    for my $cell (grep {defined} $xy, $yx) {
      my $c = $cell->{compatibility};
      next unless $c eq 'No' || $c eq 'Check dependency';
      if (!defined $compatibility || ($c eq 'No' && $compatibility ne 'No')) {
        ($compatibility, $explanation) = ($c, $cell->{explanation});
        last if $c eq 'No';
      }
    }
    next unless defined $compatibility;
    $osadl_pairs{"$x\0$y"} = {licenses => [$x, $y], compatibility => $compatibility, explanation => $explanation};
  }
}
my @osadl_pairs = map { $osadl_pairs{$_} }
  sort { $osadl_pairs{$a}{compatibility} cmp $osadl_pairs{$b}{compatibility} || $a cmp $b } keys %osadl_pairs;
$osadl_file->spew(to_json({source => $OSADL_URL, timestamp => $osadl->{timestamp}, pairs => \@osadl_pairs}) . "\n");
say qq(Updated @{[scalar @osadl_pairs]} OSADL incompatibility pairs in "$osadl_file");
