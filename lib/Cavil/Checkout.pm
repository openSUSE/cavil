# Copyright (C) 2018 SUSE Linux GmbH
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

package Cavil::Checkout;
use Mojo::Base -base;

use File::Unpack;
use Mojo::File 'path';
use Mojo::JSON qw(decode_json encode_json);
use Mojo::Util 'dumper';
use Cavil::Util qw(buckets slurp_and_decode);
use Cavil::Licenses 'lic';
use Cavil::PostProcess;

use constant DEBUG => $ENV{SUSE_CHECKOUT_DEBUG} || 0;

has 'dir';

my $BLACKLIST_MIME_RE = qr!
^(
  audio/|
  image/|
  video/|
  application/(
    application/vnd.oasis.opendocument|
    octet\-stream|
    ogg|
    msword|
    x\-dosexec|
    x\-gettext\-translation|
    x\-executable|
    x\-sharedlib|
    unknown|
    x\-archive|
    x\-dbm|
    x\-frame|   # xorg-modular/doc/xorg-docs/specs/XPRINT/xp_libraryTOC.doc
    x\-123|
    x\-tex\-tfm|
    mac\-binhex40|
    x\-shockwave\-flash|
    x\-kdelnk|   # .desktop file
    x\-tar|
    x\-unknown
  )|
  text/PGP
)
!x;

# TODO: Clean up, copied from old code
#
# This monstrous regexp is not exact RFC-822 conform, but quite close :-)
# mee@foo.-oo is illgal. host names should be @(\w([\w-]*\w)?\.)+\w([\w-]*\w)?
# This is filtered below in an additional regexp.
#
my $URL_RE = qr!
  \b(\S+\s\S+)\s+[\(<]?([\w\.\+%-]+@[\w-]+\.[\w\.-]+\w)[\)>]?\s |
  mailto:([\w\.\+%-]+@[\w-]+\.[\w\.-]+\w)["' ]*>\s*([^<@\s]+\s+[^<@\s]+)\s*< |
  \b([\w\.\+%-]+@[\w-]+\.[\w\.-]+\w)\b |
  \b((https?|ftp|file)://[\w-]+\.[\w\./:\\\+~-]+\w\??)\b
!ix;

sub keyword_report {
  my ($self, $matcher, $meta, $file) = @_;

  my $dir  = path($self->dir);
  my $base = $dir->child('.unpacked');

  $file = $base->child($file);
  return undef unless -r $file;

  _urls($file, $meta);

  return {path => $file->to_rel($base)->to_string, matches => $matcher->find_matches($file)};
}

sub new { shift->SUPER::new(dir => shift) }

sub specfile_report {
  my $self = shift;

  my $dir   = path($self->dir);
  my $name  = $dir->dirname->basename . '.spec';
  my $first = $dir->child($name);

  return {errors => ["Main specfile missing: $name"]} unless -f $first;
  my $specfile = _specfile($first);
  return {errors => ["Main specfile contains no license: $name"]} unless @{$specfile->{licenses}};

  $specfile->{license} = $specfile->{licenses}[0];
  my $info = {main => $specfile, sub => [$specfile]};
  for my $spec ($dir->list->grep(qr/\.spec$/)->each) {
    next if $spec eq $first;
    push @{$info->{sub}}, _specfile($spec);
  }

  _check($info);

  warn dumper $info if DEBUG;
  return $info;
}

sub unpack {
  my $self = shift;

  my $dir    = path($self->dir);
  my $unpack = $dir->child('.unpacked')->remove_tree;
  my $log    = $dir->child('.postprocessed.json');
  unlink $log;
  $log = $dir->child('.unpacked.json');
  unlink $log;

  # Reset signals just to be safe
  local $SIG{PIPE} = 'default';
  local $SIG{CHLD} = 'default';
  local $SIG{INT}  = 'default';
  local $SIG{TERM} = 'default';
  local $SIG{QUIT} = 'default';

  my $u = File::Unpack->new(
    verbose => 0,

    # chromium's tar is 5.4GB (uncompressed, as file::unpack
    # first xz -cd before extracting tar, we need to need that
    # much. And reserve some space for future growth)
    maxfilesize          => '7G',
    one_shot             => 0,
    no_op                => 0,
    world_readable       => 1,
    archive_name_as_dir  => 0,
    follow_file_symlinks => 0,
    destdir              => "$unpack",
    logfile              => "$log",
    log_type             => 'JSON',
    log_fullpath         => 0
  );
  $u->exclude(vcs => 1);
  $u->mime_helper_dir('/usr/share/File-Unpack/helper/');
  eval { $u->unpack($dir) };
  my $err = $@ || ($u->{error} ? join(', ', @{$u->{error}}) : undef);

  if ($err) {
    die $err;
    return;
  }

  my $unpacked  = decode_json($dir->child('.unpacked.json')->slurp);
  my $processor = Cavil::PostProcess->new($unpacked);
  $processor->postprocess;
  $dir->child('.postprocessed.json')->spurt(encode_json($processor->hash));
}

sub unpacked_files {
  my ($self, $bucket_size) = @_;

  my $dir      = path($self->dir);
  my $unpacked = decode_json($dir->child('.postprocessed.json')->slurp)->{unpacked};

  my @files;
  for my $file (sort keys %{$unpacked}) {

    my $mime = $unpacked->{$file}{mime};
    next if $mime =~ $BLACKLIST_MIME_RE;

    push @files, [$file, $mime];
  }

  return buckets(\@files, $bucket_size);
}

sub _add_once {
  my ($queue, $msg) = @_;
  return if grep { $_ eq $msg } @$queue;
  push @$queue, $msg;
}

sub _check {
  my ($info) = @_;

  $info->{errors}   = \my @errors;
  $info->{warnings} = \my @warnings;

  my $mlicense = $info->{main}{license};
  my $main     = lic($mlicense);
  if (my $err = $main->error) { push @errors, $err and return }
  _add_once(\@warnings, "Main license has license exception: $mlicense")         if $main->exception;
  _add_once(\@warnings, "Main license had to be normalized: $mlicense -> $main") if $main->normalized;

  for my $file (@{$info->{sub}}) {
    my $spec = $file->{file};
    for my $license (@{$file->{licenses}}) {
      my $sub = lic($license);
      if (my $err = $sub->error) { push @errors, $err and next }

      _add_once(\@warnings, "License from $spec has license exception: $license")        if $sub->exception;
      _add_once(\@warnings, "License from $spec had to be normalized: $license -> $sub") if $sub->normalized;

      _add_once(\@errors, "License from $spec is not part of main license: $license") unless $main->is_part_of($sub);
    }
  }
}

sub _specfile {
  my $file = shift;

  my $info = {file => $file->basename, licenses => [], '%doc' => [], '%license' => []};
  for my $line (split "\n", $file->slurp) {
    if    ($line =~ /^License:\s*(.+)\s*$/)  { push @{$info->{licenses}}, $1 }
    elsif ($line =~ /^\%doc\s*(.+)\s*$/)     { push @{$info->{'%doc'}}, $1 }
    elsif ($line =~ /^\%license\s*(.+)\s*$/) { push @{$info->{'%license'}}, $1 }
    elsif ($line =~ /^Version:\s*(.+)\s*$/)  { $info->{version} ||= $1 }
    elsif ($line =~ /^Summary:\s*(.+)\s*$/)  { $info->{summary} ||= $1 }
    elsif ($line =~ /^Group:\s*(.+)\s*$/)    { $info->{group} ||= $1 }
    elsif ($line =~ /^Url:\s*(.+)\s*$/)      { $info->{url} ||= $1 }
  }

  return $info;
}

# TODO: Clean up, copied from old code
#
# If defined, $prefix is prepended to $text; matches in prefix will result in
# negative offsets.
# Normal text offsets are always relative to the start of $text.
# This can be used to give the filename or other meta data that should match
# too.
#
sub _urls {
  my ($file, $meta) = @_;

  my $text = slurp_and_decode($file);
  return undef unless defined $text;

# urls with query string have their query strings removed. only the question
# mark char remains.
# urls with user@ are currently not supported.
  while ($text =~ /$URL_RE/g) {
    my ($name, $email, $email2, $name2, $email3, $url) = ($1, $2, $3, $4, $5, $6);
    $email = $email2 unless defined $email;
    $email = $email3 unless defined $email;
    $name  = $name2  unless defined $name;

    # name: want mixed case, no digits, little punctation
    # url and email: skip example.org adresses.

    $email = undef if defined $email and $email =~ m{(\@-|\@.*(\.-|-\.))};             # RFC 822 illegal
    $email = undef if defined $email and $email =~ m{[\@\.]example\.(net|com|org)};    # RFC 2606
    $url   = undef if defined $url   and $url   =~ m{[/\.]example\.(net|com|org)};     # RFC 2606
    $name = undef if defined $name and ($name eq lc $name or $name =~ m{[\(\):\d,\n\r]});

    # file:// urls not wanted in our context.
    $url = undef if defined $url and $url =~ m{^file:/};

    # put each url,email or cve in the list only once. (Once per file.)
    if (defined $email) {
      $email = lc $email;
      $meta->{emails}->{$email} ||= {name => undef, count => 0};
      $meta->{emails}->{$email}->{count}++;
      $meta->{emails}->{$email}->{name} ||= $name;
    }
    if (defined $url) {
      $url =~ s{^(\w+://.[^/])}{lc $1}e;
      $meta->{urls}->{$url} ||= 0;
      $meta->{urls}->{$url}++;
    }
  }

}

1;
