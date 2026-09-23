# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package Cavil::Checkout;
use Mojo::Base -base, -signatures;

use File::Unpack2;
use File::Spec::Functions qw(catfile);
use Mojo::File 'path';
use Cavil::Util (qw(buckets decode_json_fast encode_json_fast extract_copyrights extract_urls_and_emails fs_bytes),
  qw(original_filename read_lines slurp_and_decode));
use Cavil::PostProcess;
use Cavil::ReportUtil qw(is_license_filename);

# Aggregated legal documents are the one place notices are not clustered at the top of the file
use constant LEGAL_DOCUMENT_SIZE => 1_000_000;

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

# Matching ran against the ".processed" copy, so the recorded line numbers mean nothing in the original
sub evidence_text ($self, $row) {
  my $base    = path($self->dir)->child('.unpacked');
  my $scanned = $base->child(fs_bytes($row->{filename}))->to_string;
  my $path    = _original_file($scanned);

  my ($sline, $eline) = ($row->{sline}, $row->{eline});
  if ($path ne $scanned) {
    my $lines = Cavil::PostProcess->new->original_lines($path, [$sline, $eline]);
    ($sline, $eline) = ($lines->{$sline}, $lines->{$eline});
    return () unless $sline && $eline;
  }

  my $text = eval { read_lines($path, $sline, $eline) };
  return () unless defined $text && length $text;
  return ($text, path($path)->to_rel($base)->to_string . "#L$sline-L$eline");
}

sub is_unpacked ($self) { -d path($self->dir)->child('.unpacked') }

sub keyword_report ($self, $matcher, $meta, $file) {
  my $dir  = path($self->dir);
  my $base = $dir->child('.unpacked');

  $file = $base->child($file);
  return undef unless -r $file;

  _text_metadata($base, $file, $meta);

  return {path => $file->to_rel($base)->to_string, matches => $matcher->find_matches($file)};
}

sub new ($class, $dir) { $class->SUPER::new(dir => $dir) }

sub unpack ($self, $options = {}) {
  my $dir    = path($self->dir);
  my $unpack = $dir->child('.unpacked')->remove_tree;

  # Cavil's own derived documents (Cavil::Model::Packages::DOCUMENTS), stale the moment the tree is rebuilt.
  # Deleted rather than excluded from the unpack: an exclusion glob matches every directory level, so a
  # package shipping its own ".report.*" file would silently lose it from the index. Unpacking ours is not
  # cosmetic either - it decompresses a NOTICE of pure license text back into the package.
  $_->remove for $dir->list({hidden => 1})->grep(sub { $_->basename =~ /^\.report\./ })->each;
  my $log = $dir->child('.postprocessed.json');
  unlink $log;
  $log = $dir->child('.unpacked.json');
  unlink $log;

  # Reset signals just to be safe
  local $SIG{PIPE} = 'DEFAULT';
  local $SIG{CHLD} = 'DEFAULT';
  local $SIG{INT}  = 'DEFAULT';
  local $SIG{TERM} = 'DEFAULT';
  local $SIG{QUIT} = 'DEFAULT';

  my $u = File::Unpack2->new(
    verbose => 0,

    maxfilesize          => '30G',
    one_shot             => 0,
    no_op                => 0,
    world_readable       => 1,
    archive_name_as_dir  => 0,
    follow_file_symlinks => 0,

    # Kill a mime helper that makes NO I/O progress at all for 5 minutes. This is safe even for
    # huge legit archives (chromium's 30G tarball): a real extraction keeps advancing an fd or
    # emitting output, so it is never touched - only a genuinely stuck helper (blocked on a fifo,
    # deadlocked pipe, ...) is reaped. We deliberately do NOT set the absolute max_files /
    # max_total_bytes / helper_timeout caps, which would clip legitimately huge packages.
    stall_timeout => 300,

    destdir      => "$unpack",
    logfile      => "$log",
    log_type     => 'JSON',
    log_fullpath => 0
  );

  # Zstandard, requires zstd
  $u->mime_helper('application=zstd', qr{(?:zst)}, [qw(/usr/bin/zstd -d -c -f %(src)s)], qw(> %(destfile)s));

  $u->exclude(vcs => 1);

  if (my $exclude = $options->{exclude}) {
    $u->exclude($_) for @$exclude;
  }
  eval { $u->unpack($dir) };
  my $err = $@ || ($u->{error} ? join(', ', @{$u->{error}}) : undef);

  if ($err) {
    die $err;
    return;
  }

  my $unpacked = decode_json_fast($dir->child('.unpacked.json')->slurp);
  $unpacked->{unpacked} = _byte_names($unpacked->{unpacked});
  my $processor = Cavil::PostProcess->new($unpacked);
  $processor->postprocess;
  $dir->child('.postprocessed.json')->spew(encode_json_fast($processor->hash));

  # Whatever we had read before is what the previous unpack produced
  delete $self->{_unpacked};
}

# The file list of a big package is several megabytes and an index job reads it twice in a row, once
# for the stats and once for the buckets, so hold on to it for the life of the checkout object
sub _unpacked ($self) {
  return $self->{_unpacked}
    //= _byte_names(decode_json_fast(path($self->dir)->child('.postprocessed.json')->slurp)->{unpacked});
}

# File names are recorded as the bytes found on disk, and JSON decoding turns those into characters: a
# name holding any byte above 0x7f then opens nothing, and postprocess erases every file it cannot open.
# Hand every reader the bytes back, so one name works for the filesystem, the database and the report.
sub _byte_names ($unpacked) {
  return {map { fs_bytes($_) => $unpacked->{$_} } keys %$unpacked};
}

sub unpacked_file_stats ($self) {
  my $dir      = scalar $self->dir;
  my $unpacked = $self->_unpacked;

  my $stats = {files => scalar keys %$unpacked, size => 0};
  for my $file (keys %{$unpacked}) {
    $stats->{size} += (-s catfile($dir, '.unpacked', $file)) // 0;
  }

  return $stats;
}

sub unpacked_files ($self, $bucket_size = undef) {
  my $unpacked = $self->_unpacked;

  my @files;
  for my $file (sort keys %{$unpacked}) {

    # Second line of defence, for a tree an older Cavil unpacked before the removal above existed
    next if $file =~ m{^\.report\.};

    my $mime = $unpacked->{$file}{mime};
    next if $mime =~ $BLACKLIST_MIME_RE;

    push @files, [$file, $mime];
  }

  return \@files unless defined $bucket_size;

  return buckets(\@files, $bucket_size);
}

sub _text_metadata ($base, $file, $meta) {
  my $text = slurp_and_decode($file);
  return undef unless defined $text;
  extract_urls_and_emails($text, $meta);

  # Never the ".processed" copy: its line wrapping splits a notice from the holder it names, leaving
  # "Copyright (c) 2019" with the names gone. Re-reading is skipped where it would read the same bytes.
  my $original = _original_file($file);
  $text = _copyright_text($original) // $text if $original ne $file || is_license_filename($original);

  my $name = path($original)->to_rel($base)->to_string;
  push @{$meta->{copyrights}{$_}}, $name for keys %{extract_copyrights($text)};

  return undef;
}

# Matching runs against the ".processed" copy, but reading content wants the file it was made from
sub _original_file ($path) {
  my $original = original_filename($path);
  return $original ne $path && -f $original ? $original : $path;
}

sub _copyright_text ($path) {
  return undef unless -f $path;
  return eval { is_license_filename($path) ? slurp_and_decode($path, LEGAL_DOCUMENT_SIZE) : slurp_and_decode($path) };
}

1;
