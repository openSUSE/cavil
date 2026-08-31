# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package Cavil::Checkout;
use Mojo::Base -base, -signatures;

use File::Unpack2;
use File::Spec::Functions qw(catfile);
use Mojo::DOM;
use Mojo::File 'path';
use Mojo::Util 'dumper';
use Cavil::Util (
  qw(buckets decode_json_fast encode_json_fast expand_spec_macros extract_copyrights),
  qw(extract_urls_and_emails fs_bytes legal_review_notices original_filename parse_service_file read_lines),
  qw(slurp_and_decode)
);
use Cavil::Licenses 'lic';
use Cavil::PostProcess;
use Cavil::ReportUtil qw(is_license_filename);
use YAML::XS          qw(Load);

use constant DEBUG => $ENV{SUSE_CHECKOUT_DEBUG} || 0;

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

my $LICENSE_COMMENT_RE = qr/^\s*#\s*SPDX-License-Identifier\s*:\s*(.+)\s*$/;

# Plain "Dockerfile", multibuild flavors like "Dockerfile.driver-550", and named "foo.Dockerfile"
my $DOCKERFILE_RE = qr/^(?:Dockerfile(?:\..+)?|.+\.Dockerfile)$/;

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

sub specfile_report ($self, $opts = {}) {
  my $dir      = path($self->dir);
  my $basename = $dir->dirname->basename;
  my $unpacked = $dir->child('.unpacked');

  my $info = {main => undef, sub => [], errors => [], incomplete_checkout => 0};

  my $service_file = $unpacked->child('_service');

  my $specfile_name = $basename . '.spec';
  my $main_specfile = $unpacked->child($specfile_name);

  my $debian_control_file = $unpacked->child('debian/control');

  my $kiwifile_name = $basename . '.kiwi';
  my $main_kiwifile = $unpacked->child($kiwifile_name);

  my $dockerfile_name  = $basename . '.Dockerfile';
  my $main_dockerfile  = $unpacked->child('Dockerfile');
  my $named_dockerfile = $unpacked->child($dockerfile_name);

  my $helmchart_name = 'Chart.yaml';
  my $main_helmchart = $unpacked->child($helmchart_name);

  my $is_obsprj = _is_obsprj($unpacked);

  # Archive upload (no user-provided package metadata)
  if ($opts->{upload}) {

    my $root    = $unpacked;
    my @entries = $unpacked->list({dir => 1})->each;
    $root = $entries[0] if @entries == 1 && -d $entries[0];

    my $files          = $root->list->grep(sub { $_ !~ /\.processed\./ });
    my $debian_control = $root->child('debian/control');
    my $chart          = $root->child('Chart.yaml');
    my ($spec)         = $files->grep(qr/\.spec$/)->each;
    my ($kiwi)         = $files->grep(qr/\.kiwi$/)->each;
    my ($dockerfile)   = $files->grep(sub { $_->basename =~ $DOCKERFILE_RE })->each;

    # Auto-detect a main package file (any name), in priority order
    my $main;
    if    ($spec)              { $main = _specfile($spec) }
    elsif (-f $debian_control) { $main = _debian_files($debian_control) }
    elsif ($kiwi)              { $main = _kiwifile($kiwi) }
    elsif ($dockerfile)        { $main = _dockerfile($dockerfile) }
    elsif (-f $chart)          { $main = _helmchart($chart) }
    $main->{license} = $main->{licenses}[0] if $main && @{$main->{licenses}};

    # A package file is not required for an upload, so fall back to a minimal main
    $info->{main} = $main // {file => 'upload', type => 'upload', license => undef, licenses => []};

    # List all detected package files for display
    push @{$info->{sub}}, _debian_files($debian_control) if -f $debian_control;
    push @{$info->{sub}}, _helmchart($chart)             if -f $chart;
    push @{$info->{sub}}, _specfile($_)   for $files->grep(qr/\.spec$/)->each;
    push @{$info->{sub}}, _kiwifile($_)   for $files->grep(qr/\.kiwi$/)->each;
    push @{$info->{sub}}, _dockerfile($_) for $files->grep(sub { $_->basename =~ $DOCKERFILE_RE })->each;
  }

  else {

    # Service file
    if (-f $service_file) {
      my $services = parse_service_file($service_file->slurp);
      for my $service (@$services) {
        next if $service->{safe};
        $info->{incomplete_checkout} = 1;
        push @{$info->{errors}},
          "Checkout might be incomplete, remote service in _service file: $service->{name} (mode: $service->{mode})";
      }
    }

    # ObsPrj
    if ($is_obsprj) {
      push @{$info->{sub}}, $info->{main} = {file => 'workflow.config', type => 'obsprj', licenses => []};

      # Not a license problem but a completeness one, which is what the errors list is for: the packages
      # this product pulls in from subdirectories may not be in the checkout that was scanned.
      push @{$info->{errors}}, 'Checkout is a product in ObsPrj format and might contain packages in subdirectories';
    }

    # Main .spec file
    elsif (-f $main_specfile) {
      my $specfile = $info->{main} = _specfile($main_specfile);
      if (@{$specfile->{licenses}}) { $specfile->{license} = $specfile->{licenses}[0] }
      else {
        push @{$info->{errors}}, qq{Main specfile contains no license: $specfile_name (expected "License: ..." entry)};
      }
    }

    # Debian files
    elsif (-f $debian_control_file) {
      my $debian_files = $info->{main} = _debian_files($debian_control_file);
      if (@{$debian_files->{licenses}}) { $debian_files->{license} = $debian_files->{licenses}[0] }
      else {
        push @{$info->{errors}}, qq{Package contains no license: debian/copyright (expected "License: ..." entry)};
      }
    }

    # Main .kiwi file
    elsif (-f $main_kiwifile) {
      my $kiwifile = $info->{main} = _kiwifile($main_kiwifile);
      if (@{$kiwifile->{licenses}}) { $kiwifile->{license} = $kiwifile->{licenses}[0] }
      else {
        push @{$info->{errors}},
          qq{Main kiwifile contains no license: $kiwifile_name (expected <label name="org.opencontainers.image.licenses" value="..."> tag)};
      }
    }

    # Main .Dockerfile file
    elsif (-f $main_dockerfile) {
      my $dockerfile = $info->{main} = _dockerfile($main_dockerfile);
      if (@{$dockerfile->{licenses}}) { $dockerfile->{license} = $dockerfile->{licenses}[0] }
      else {
        push @{$info->{errors}},
          qq{Main Dockerfile contains no license: Dockerfile (expected "# SPDX-License-Identifier: ..." comment)};
      }
    }
    elsif (-f $named_dockerfile) {
      my $dockerfile = $info->{main} = _dockerfile($named_dockerfile);
      if (@{$dockerfile->{licenses}}) { $dockerfile->{license} = $dockerfile->{licenses}[0] }
      else {
        push @{$info->{errors}},
          qq{Main Dockerfile contains no license: $dockerfile_name (expected "# SPDX-License-Identifier: ..." comment)};
      }
    }

    # Main Chart.yaml file
    elsif (-f $main_helmchart) {
      my $helmchart = $info->{main} = _helmchart($main_helmchart);
      if (@{$helmchart->{licenses}}) { $helmchart->{license} = $helmchart->{licenses}[0] }
      else {
        push @{$info->{errors}},
          qq{Main Helm chart contains no license: $helmchart_name (expected "# SPDX-License-Identifier: ..." comment)};
      }

      # For now we only expect one Chart.yaml file
      push @{$info->{sub}}, $helmchart;
    }

    # No main files
    else {
      push @{$info->{errors}}, "Main package file missing: expected $specfile_name, debian/control, $kiwifile_name,"
        . " $dockerfile_name, Dockerfile, or Chart.yaml";
    }

    # Debian files
    push @{$info->{sub}}, _debian_files($debian_control_file) if -f $debian_control_file;

    # All .spec files
    my $files = $unpacked->list->grep(sub { $_ !~ /\.processed\./ });
    push @{$info->{sub}}, _specfile($_) for $files->grep(qr/\.spec$/)->each;

    # All .kiwi files
    push @{$info->{sub}}, _kiwifile($_) for $files->grep(qr/\.kiwi$/)->each;

    # All Dockerfiles
    push @{$info->{sub}}, _dockerfile($_) for $files->grep(sub { $_->basename =~ $DOCKERFILE_RE })->each;

    _check($info);
  }

  warn dumper $info if DEBUG;
  return $info;
}

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

sub _check ($info) {
  my $errors = $info->{errors};

  if (my $err = lic($info->{main}{license})->error) { push @$errors, $err and return }

  for my $file (@{$info->{sub}}) {
    for my $license (@{$file->{licenses}}) {
      if (my $err = lic($license)->error) { push @$errors, $err }
    }
  }
}

sub _debian_files ($file) {
  my $info = {file => 'debian', type => 'debian', licenses => []};

  for my $line (split "\n", $file->slurp) {
    if    ($line =~ /^Homepage:\s*(.+)\s*$/)          { $info->{url} = $1 }
    elsif ($line =~ /^Standards-Version:\s*(.+)\s*$/) { $info->{version} ||= $1 }
  }

  my $copyright_file = $file->sibling('copyright');
  if (-f $copyright_file) {
    for my $line (split "\n", $copyright_file->slurp) {
      if ($line =~ /^License:\s*(.+)\s*$/) { push @{$info->{licenses}}, $1 }
    }
  }

  return $info;
}

sub _dockerfile ($file) {
  my $content = $file->slurp;
  my $info    = {
    file                 => $file->basename,
    type                 => 'dockerfile',
    licenses             => [],
    legal_review_notices => legal_review_notices($content)
  };
  for my $line (split "\n", $content) {
    if    ($line =~ $LICENSE_COMMENT_RE)                                 { push @{$info->{licenses}}, $1 }
    elsif ($line =~ /^.*org.opencontainers.image.version="(.+)".*$/)     { $info->{version} ||= $1 }
    elsif ($line =~ /^.*org.opencontainers.image.description="(.+)".*$/) { $info->{summary} ||= $1 }
  }

  return $info;
}

sub _helmchart ($file) {
  my $content = $file->slurp;
  my $info
    = {file => $file->basename, type => 'helm', licenses => [], legal_review_notices => legal_review_notices($content)};
  for my $line (split "\n", $content) {
    if ($line =~ $LICENSE_COMMENT_RE) { push @{$info->{licenses}}, $1 }
  }

  my $data = eval { Load($content) };
  if (ref $data eq 'HASH') {
    if (my $version = $data->{version})     { $info->{version} = $version }
    if (my $summary = $data->{description}) { $info->{summary} = $summary }
    if (my $url     = $data->{home})        { $info->{url}     = $url }
  }

  return $info;
}

sub _is_obsprj ($unpacked) {
  my $config = $unpacked->child('workflow.config');
  return 0 unless -f $config;
  return 0 unless my $data = eval { decode_json_fast($config->slurp) };
  return 0 unless ref $data eq 'HASH' && exists $data->{Workflows} && exists $data->{GitProjectName};
  return 1;
}

sub _kiwifile ($file) {
  my $info = {file => $file->basename, type => 'kiwi', licenses => []};
  my $dom  = Mojo::DOM->new($file->slurp);

  # Licenses
  for my $label ($dom->find('label[name="org.opencontainers.image.licenses"]')->each) {
    next unless my $value = $label->{value};
    push @{$info->{licenses}}, $value;
  }

  # Version
  if (my $version = $dom->at('image preferences version')) { $info->{version} = $version->text }

  # Summary
  if (my $summary = $dom->at('image description specification')) { $info->{summary} = $summary->text }

  # URL
  if (my $url = $dom->at('image description contact')) { $info->{url} = $url->text }

  return $info;
}

sub _specfile ($file) {
  my $content = expand_spec_macros($file->slurp);
  my $info    = {
    file                 => $file->basename,
    type                 => 'spec',
    licenses             => [],
    sources              => [],
    '%doc'               => [],
    '%license'           => [],
    legal_review_notices => legal_review_notices($content)
  };
  for my $line (split "\n", $content) {
    if    ($line =~ /^License:\s*(.+)\s*$/)        { push @{$info->{licenses}},   $1 }
    elsif ($line =~ /^Source(?:\d+)?:\s*(.+)\s*$/) { push @{$info->{sources}},    $1 }
    elsif ($line =~ /^\%doc\s*(.+)\s*$/)           { push @{$info->{'%doc'}},     $1 }
    elsif ($line =~ /^\%license\s*(.+)\s*$/)       { push @{$info->{'%license'}}, $1 }
    elsif ($line =~ /^Version:\s*(.+)\s*$/)        { $info->{version} ||= $1 }
    elsif ($line =~ /^Summary:\s*(.+)\s*$/)        { $info->{summary} ||= $1 }
    elsif ($line =~ /^Group:\s*(.+)\s*$/)          { $info->{group}   ||= $1 }
    elsif ($line =~ /^Url:\s*(.+)\s*$/i)           { $info->{url}     ||= $1 }
  }

  return $info;
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
