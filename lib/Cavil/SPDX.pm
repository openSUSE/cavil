# Copyright (C) 2023 SUSE LLC
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

package Cavil::SPDX;
use Mojo::Base -base, -signatures;

use Cavil::Checkout;
use Cavil::Licenses qw(lic);
use Cavil::Util     qw(slurp_and_decode);
use Digest::SHA1;
use Mojo::File qw(path tempfile);
use Mojo::JSON qw(from_json);
use Mojo::Date;

use constant NO_ASSERTION => 'NOASSERTION';

my $SPDX_VERSION = '2.3';

has 'app';

sub generate_to_file ($self, $id, $file) {
  my $app             = $self->app;
  my $dir             = $app->packages->pkg_checkout_dir($id);
  my $checkout        = Cavil::Checkout->new($dir);
  my $reports         = $app->reports;
  my $specfile_report = $reports->specfile_report($id);
  my $db              = $app->pg->db;
  my $license_ref_num = 0;

  my $spdx_handle = path($file)->open('>>');
  my $spdx        = _SPDXWriter->new(handle => $spdx_handle);
  my $tmp         = tempfile(TEMPLATE => 'cavil.spdx.XXXXXXXXXX');
  my $refs        = _SPDXWriter->new(handle => $tmp->open('>>'));

  # Document
  $spdx->tag(SPDXVersion => "SPDX-$SPDX_VERSION");
  $spdx->tag(DataLicense => 'CC0-1.0');
  $spdx->br();

  # Creation
  $spdx->box('Creation Information');
  $spdx->tag(Creator => 'Tool: Cavil');
  $spdx->tag(Created => Mojo::Date->new->to_datetime);
  $spdx->br();

  # Package
  my $pkg = $db->query('SELECT * FROM bot_packages WHERE id = ?', $id)->hash;
  $spdx->box('Package Information');
  $spdx->tag(PackageName => $pkg->{name});
  if (my $main = $specfile_report->{main}) {
    my $version = $main->{version} // '';
    $spdx->tag(PackageVersion => $version) if $version =~ /^[0-9.]+$/;
    my $license = lic($main->{license} // '');
    $spdx->tag(PackageLicenseDeclared => $license->is_valid_expression ? $license->to_string : NO_ASSERTION);
    if (my $summary = $main->{summary}) { $spdx->tag(PackageDescription => $summary) }
    if (my $url     = $main->{url})     { $spdx->tag(PackageHomePage    => $url) }
  }
  $spdx->tag(PackageChecksum => 'MD5: ' . $pkg->{checkout_dir});
  $spdx->br();

  # Files
  $spdx->box('File Information');
  my $matched_files = {};
  for my $matched ($db->query('SELECT * FROM matched_files WHERE package = ?', $id)->hashes->each) {
    $matched_files->{$matched->{filename}} = $matched->{id};
  }
  for my $unpacked (@{$checkout->unpacked_files}) {
    my ($file, $mime) = @$unpacked;
    my $path = $dir->child('.unpacked', $file)->to_string;

    $spdx->comment('File');
    $spdx->br();
    $spdx->tag(FileName     => "./$file");
    $spdx->tag(FileChecksum => 'SHA1: ' . Digest::SHA->new('1')->addfile($path)->hexdigest);

    # Matches
    if (my $file_id = $matched_files->{$file}) {
      my @lines = ('', split "\n", slurp_and_decode($path));
      my %duplicates;
      my @copyright = grep { /copyright.*\d+/i && !$duplicates{$_} } @lines;

      for my $match ($db->query('SELECT * FROM pattern_matches WHERE file = ? ORDER BY id', $file_id)->hashes->each) {
        my $pattern = $db->query('SELECT * FROM license_patterns WHERE id = ?', $match->{pattern})->hash;
        my $snippet = _matched_snippet(\@lines, $match);

        # License or snippet for keyword
        if (my $license = $pattern->{spdx}) {
          $spdx->tag(LicenseInfoInFile => $license);
        }

        # Non-SPDX license
        else {
          my $unknown = $pattern->{license};
          $license_ref_num++;
          my $license = "LicenseRef-$unknown-$license_ref_num";
          $license =~ s/[^A-Za-z0-9.]+/-/g;

          $spdx->tag(LicenseInfoInFile => $license);

          $refs->comment('License Reference');
          $refs->br();
          $refs->tag(LicenseId      => $license);
          $refs->tag(LicenseName    => $unknown || NO_ASSERTION);
          $refs->tag(LicenseComment => "Risk: $pattern->{risk}");
          $refs->text(ExtractedText => $snippet);
          $refs->br();
        }
      }

      if (@copyright) {
        $spdx->text(FileCopyrightText => join("\n", @copyright));
      }
      else {
        $refs->tag(FileCopyrightText => NO_ASSERTION);
      }
    }

    # No matches
    else {
      $spdx->tag(LicenseInfoInFile => NO_ASSERTION);
      $spdx->tag(FileCopyrightText => NO_ASSERTION);
    }

    $spdx->br();
  }

  # Merge license references and main SPDX file
  if (-s $tmp) {
    $spdx->box('Other Licensing Information');
    my $tmp_handle = $tmp->open('<');
    my $buffer;
    $spdx_handle->syswrite($buffer) while $tmp_handle->sysread($buffer, 1024);
  }
}

sub _matched_snippet ($lines, $match) {
  return join "\n", @{$lines}[$match->{sline} ... $match->{eline}];
}

package _SPDXWriter;
use Mojo::Base -base, -signatures;

use Mojo::Util qw(encode);

sub append ($self, $text) { $self->{handle}->syswrite(encode('UTF-8', $text)) }

sub br ($self) { $self->append("\n") }

sub tag ($self, $name, $value) {
  if ($value =~ /\n/) {
    $self->text($name, $value);
  }
  else {
    $self->append("$name: $value\n");
  }
}

sub text ($self, $name, $value) {
  $self->append("$name: <text>$value</text>\n");
}

sub comment ($self, $text) { $self->append("##$text\n") }

sub box ($self, $text) {
  $self->comment('-----------------------------');
  $self->comment(" $text");
  $self->comment('-----------------------------');
  $self->br();
}

1;
