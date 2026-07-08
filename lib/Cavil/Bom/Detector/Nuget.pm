# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package Cavil::Bom::Detector::Nuget;
use Mojo::Base -base, -signatures;

use Mojo::DOM;

# Every NuGet package carries a "<id>.nuspec" manifest; it is present both loose and inside an unpacked
# .nupkg (a zip), so it is a reliable per-package presence signal
sub files ($self) { return (qr{(?:^|/)[^/]+\.nuspec$}) }

sub parse ($self, $path, $content) {
  my $dom  = Mojo::DOM->new->xml(1)->parse($$content);
  my $meta = $dom->at('package > metadata') or return [];

  my $name    = _text($meta->at('id'));
  my $version = _text($meta->at('version'));
  return [] unless defined $name && length $name && defined $version && length $version;

  # A .nuspec doubles as a build template that ships in source trees with unresolved placeholder tokens,
  # e.g. id "ANTLR4.Runtime.cpp.vs$vs$.static", version "$version$$pre$". Accept only a real NuGet id
  # (alphanumerics, dot, hyphen, underscore) and a version that starts with a digit, so templates are
  # ignored instead of reported as bogus components.
  return [] unless $name    =~ /^[A-Za-z0-9._-]+$/;
  return [] unless $version =~ /^[0-9][0-9A-Za-z.+-]*$/;

  return [
    {
      type    => 'nuget',
      name    => $name,
      version => $version,
      purl    => "pkg:nuget/$name\@$version",
      license => _license($meta),
      source  => $path
    }
  ];
}

# Modern nuspecs use <license type="expression">MIT</license> (an SPDX expression); the old <licenseUrl>
# is not a licence identifier, so it is left for Cavil's own detection to backfill.
sub _license ($meta) {
  my $license = $meta->at('license[type="expression"]') or return undef;
  return _text($license);
}

sub _text ($node) {
  return undef unless $node;
  my $text = $node->text;
  $text =~ s/^\s+|\s+$//g;
  return length $text ? $text : undef;
}

1;
