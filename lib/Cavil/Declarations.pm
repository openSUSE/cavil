# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package Cavil::Declarations;
use Mojo::Base -base, -signatures;

use Exporter 'import';
use Mojo::File 'path';
use Cavil::Bom::Registry;
use Cavil::Declarations::Spec;
use Cavil::Declarations::Debian;
use Cavil::Declarations::Kiwi;
use Cavil::Declarations::Dockerfile;
use Cavil::Declarations::Helm;
use Cavil::Declarations::ObsPrj;
use Cavil::Util qw(original_filename parse_service_file safe_string);

our @EXPORT_OK = qw(is_root_file single_root);

# Distribution packaging outranks the upstream project's own manifest, in this order
has detectors => sub ($self) {
  [
    Cavil::Declarations::Spec->new,       Cavil::Declarations::Debian->new, Cavil::Declarations::Kiwi->new,
    Cavil::Declarations::Dockerfile->new, Cavil::Declarations::Helm->new,   Cavil::Declarations::ObsPrj->new
  ];
};
has registry => sub { Cavil::Bom::Registry->new };

sub detect ($self, $dir) {
  my $name     = path($dir)->dirname->basename;
  my $unpacked = path($dir)->child('.unpacked');
  return {declarations => [], incomplete_checkout => []} unless -d $unpacked;

  my $single = single_root($unpacked);
  my @files  = grep { is_root_file($_, $single) && original_filename($_) eq $_ }
    map { $_->to_rel($unpacked)->to_string } $unpacked->list_tree({max_depth => 3})->each;

  my $registry = $self->registry;
  my @declarations;
  for my $detector (@{$self->detectors}, undef) {
    my @matched = $detector ? grep { $_ =~ $detector->file } @files : grep { $registry->is_self_manifest($_) } @files;
    for my $rel (_by_rank($name, @matched)) {
      my $file = $unpacked->child(split '/', $rel);
      next unless -f $file && -s $file < 4_000_000;
      my @records = $detector ? eval { $detector->parse($file) } : _upstream($registry, $file, $rel);
      push @declarations, map { _sanitize({%$_, format => $_->{format} // $detector->format, file => $rel}) } @records;
    }
  }

  # The primary declaration goes first, the first one declaring a license
  my ($primary) = grep { defined $declarations[$_]{license} } 0 .. $#declarations;
  unshift @declarations, splice @declarations, $primary, 1 if $primary;

  my $service    = $unpacked->child('_service');
  my $services   = -f $service ? parse_service_file($service->slurp) : [];
  my @incomplete = map { {name => $_->{name}, mode => $_->{mode}} } grep { !$_->{safe} } @$services;

  return {declarations => \@declarations, incomplete_checkout => \@incomplete};
}

# A file describes the package itself when its project directory is the top of the source tree: the unpacked
# root, or the one directory a conventional name-version/ tarball unpacks to. Several top-level directories
# are archives unpacked side by side, so a file one level down belongs to one of them, not to the package.
# Python metadata and Debian packaging sit in a subdirectory of the project they describe.
sub is_root_file ($path, $single_root) {
  my @dirs = split '/', $path;
  pop @dirs;
  pop @dirs if @dirs && $dirs[-1] =~ /^(?:debian|.+\.(?:egg-info|dist-info))$/;
  return @dirs == 0 || (@dirs == 1 && $single_root);
}

sub single_root ($unpacked) {
  return 0 unless -d $unpacked;
  return (grep { -d $_ } $unpacked->list({dir => 1})->each) == 1;
}

# The file named after the package wins within a format, then the shallowest
sub _by_rank ($name, @paths) {
  my $named = qr{(?:^|/)\Q$name\E\.[^/]+$};
  return
    map { $_->[0] }
    sort { $a->[1] <=> $b->[1] || $a->[0] cmp $b->[0] } map { [$_, ($_ =~ $named ? 0 : 10) + tr{/}{}] } @paths;
}

sub _sanitize ($record) {
  for my $field (qw(name version license url summary)) {
    my $value = $record->{$field};
    $value = join ' ', split ' ', $value if defined $value && !ref $value;
    if (safe_string($value) && length $value) { $record->{$field} = $value }
    else                                      { delete $record->{$field} }
  }
  return $record;
}

sub _upstream ($registry, $file, $rel) {
  return () unless defined(my $content = eval { $file->slurp });
  return
    map { {format => $_->{type}, name => $_->{name}, version => $_->{version}, license => $_->{license}} }
    @{$registry->detect_file($rel, \$content)};
}

1;
