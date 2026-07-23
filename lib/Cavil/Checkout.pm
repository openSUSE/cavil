# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package Cavil::Checkout;
use Mojo::Base -base, -signatures;

use File::Unpack2;
use File::Spec::Functions qw(catfile);
use Mojo::DOM;
use Mojo::File 'path';
use Mojo::JSON qw(decode_json encode_json);
use Mojo::Util 'dumper';
use Cavil::Util qw(buckets expand_spec_macros parse_service_file slurp_and_decode);
use Cavil::Licenses 'lic';
use Cavil::PostProcess;
use YAML::XS qw(Load);

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

my $LICENSE_COMMENT_RE = qr/^\s*#\s*SPDX-License-Identifier\s*:\s*(.+)\s*$/;

sub is_unpacked ($self) { -d path($self->dir)->child('.unpacked') }

sub keyword_report ($self, $matcher, $meta, $file) {
  my $dir  = path($self->dir);
  my $base = $dir->child('.unpacked');

  $file = $base->child($file);
  return undef unless -r $file;

  _urls($file, $meta);

  return {path => $file->to_rel($base)->to_string, matches => $matcher->find_matches($file)};
}

sub new ($class, $dir) { $class->SUPER::new(dir => $dir) }

sub specfile_report ($self, $opts = {}) {
  my $dir      = path($self->dir);
  my $basename = $dir->dirname->basename;
  my $unpacked = $dir->child('.unpacked');

  my $info = {main => undef, sub => [], errors => [], warnings => [], incomplete_checkout => 0};

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

    # Look one level into the unpacked tree (through a single wrapper directory like
    # "foo-1.0.0/") for a package file we can auto-detect metadata from
    my $root    = $unpacked;
    my @entries = $unpacked->list({dir => 1})->each;
    $root = $entries[0] if @entries == 1 && -d $entries[0];

    my $files          = $root->list->grep(sub { $_ !~ /\.processed\./ });
    my $debian_control = $root->child('debian/control');
    my $chart          = $root->child('Chart.yaml');
    my ($spec)         = $files->grep(qr/\.spec$/)->each;
    my ($kiwi)         = $files->grep(qr/\.kiwi$/)->each;
    my ($dockerfile)   = $files->grep(sub { $_->basename =~ qr/^(?:Dockerfile|.+\.Dockerfile)$/ })->each;

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
    push @{$info->{sub}}, _specfile($_) for $files->grep(qr/\.spec$/)->each;
    push @{$info->{sub}}, _kiwifile($_) for $files->grep(qr/\.kiwi$/)->each;
    push @{$info->{sub}}, _dockerfile($_)
      for $files->grep(sub { $_->basename =~ qr/^(?:Dockerfile|.+\.Dockerfile)$/ })->each;
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
      push @{$info->{sub}},      $info->{main} = {file => 'workflow.config', type => 'obsprj', licenses => []};
      push @{$info->{warnings}}, 'Checkout is a product in ObsPrj format and might contain packages in subdirectories';
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

    # All .Dockerfile files
    push @{$info->{sub}}, _dockerfile($_)
      for $files->grep(sub { $_->basename =~ qr/^(?:Dockerfile|.+\.Dockerfile)$/ })->each;

    _check($info);
  }

  warn dumper $info if DEBUG;
  return $info;
}

sub unpack ($self, $options = {}) {
  my $dir    = path($self->dir);
  my $unpack = $dir->child('.unpacked')->remove_tree;
  my $log    = $dir->child('.postprocessed.json');
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

    # chromium's tar is 23GB (uncompressed, as file::unpack2
    # first xz -cd before extracting tar, we need to need that
    # much. And reserve some space for future growth)
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

  # Never unpack Cavil's own generated SPDX report that lives in the checkout dir. On a re-unpack it
  # would otherwise be exploded into .unpacked (and line-wrapped by postprocess) on every pass -
  # pure waste, as these reports can be huge. The compact .report.spdx.json.gz stays in the checkout
  # dir untouched; it is simply not unpacked. Matches both the .report.spdx.* and legacy
  # .report.processed.spdx.* names.
  $u->exclude(add => '.report*.spdx*');

  if (my $exclude = $options->{exclude}) {
    $u->exclude($_) for @$exclude;
  }
  eval { $u->unpack($dir) };
  my $err = $@ || ($u->{error} ? join(', ', @{$u->{error}}) : undef);

  if ($err) {
    die $err;
    return;
  }

  my $unpacked  = decode_json($dir->child('.unpacked.json')->slurp);
  my $processor = Cavil::PostProcess->new($unpacked);
  $processor->postprocess;
  $dir->child('.postprocessed.json')->spew(encode_json($processor->hash));
}

sub unpacked_file_stats ($self) {
  my $dir      = scalar $self->dir;
  my $unpacked = decode_json(path($self->dir)->child('.postprocessed.json')->slurp)->{unpacked};

  my $stats = {files => scalar keys %$unpacked, size => 0};
  for my $file (keys %{$unpacked}) {
    $stats->{size} += (-s catfile($dir, '.unpacked', $file)) // 0;
  }

  return $stats;
}

sub unpacked_files ($self, $bucket_size = undef) {
  my $dir      = path($self->dir);
  my $unpacked = decode_json($dir->child('.postprocessed.json')->slurp)->{unpacked};

  my @files;
  for my $file (sort keys %{$unpacked}) {

    # Cavil's own SPDX report can reappear when a checkout is unpacked more than once: the previous
    # .report.spdx.json[.gz] is unpacked again, and postprocess may line-wrap the uncompressed copy
    # into .report.spdx.processed.json. Never index any of these - the ".processed" marker can land
    # after ".report" or after ".spdx" depending on which name postprocess rewrote.
    next if $file =~ /\.report(?:\.processed)?\.spdx(?:\.processed)?(?:\.json)?(?:\.gz)?$/;

    my $mime = $unpacked->{$file}{mime};
    next if $mime =~ $BLACKLIST_MIME_RE;

    push @files, [$file, $mime];
  }

  return \@files unless defined $bucket_size;

  return buckets(\@files, $bucket_size);
}

sub _add_once ($queue, $msg) {
  return if grep { $_ eq $msg } @$queue;
  push @$queue, $msg;
}

sub _check ($info) {
  my $errors   = $info->{errors};
  my $warnings = $info->{warnings};

  my $mlicense = $info->{main}{license};
  my $main     = lic($mlicense);
  if (my $err = $main->error) { push @$errors, $err and return }
  _add_once($warnings, "Main license has license exception: $mlicense")         if $main->exception;
  _add_once($warnings, "Main license had to be normalized: $mlicense -> $main") if $main->normalized;

  for my $file (@{$info->{sub}}) {
    my $spec = $file->{file};
    for my $license (@{$file->{licenses}}) {
      my $sub = lic($license);
      if (my $err = $sub->error) { push @$errors, $err and next }

      _add_once($warnings, "License from $spec has license exception: $license")        if $sub->exception;
      _add_once($warnings, "License from $spec had to be normalized: $license -> $sub") if $sub->normalized;

      _add_once($warnings, "License from $spec is not part of main license: $license") unless $main->is_part_of($sub);
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
  my $info = {file => $file->basename, type => 'dockerfile', licenses => []};
  for my $line (split "\n", $file->slurp) {
    if    ($line =~ $LICENSE_COMMENT_RE)                                 { push @{$info->{licenses}}, $1 }
    elsif ($line =~ /^.*org.opencontainers.image.version="(.+)".*$/)     { $info->{version} ||= $1 }
    elsif ($line =~ /^.*org.opencontainers.image.description="(.+)".*$/) { $info->{summary} ||= $1 }
  }

  return $info;
}

sub _helmchart ($file) {
  my $info = {file => $file->basename, type => 'helm', licenses => []};
  for my $line (split "\n", $file->slurp) {
    if ($line =~ $LICENSE_COMMENT_RE) { push @{$info->{licenses}}, $1 }
  }

  my $data = eval { Load($file->slurp) };
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
  return 0 unless my $data = eval { decode_json($config->slurp) };
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
  my $info = {
    file                 => $file->basename,
    type                 => 'spec',
    licenses             => [],
    sources              => [],
    '%doc'               => [],
    '%license'           => [],
    legal_review_notices => []
  };
  for my $line (split "\n", expand_spec_macros($file->slurp)) {

    # Standard metadata fields
    if    ($line =~ /^License:\s*(.+)\s*$/)        { push @{$info->{licenses}},   $1 }
    elsif ($line =~ /^Source(?:\d+)?:\s*(.+)\s*$/) { push @{$info->{sources}},    $1 }
    elsif ($line =~ /^\%doc\s*(.+)\s*$/)           { push @{$info->{'%doc'}},     $1 }
    elsif ($line =~ /^\%license\s*(.+)\s*$/)       { push @{$info->{'%license'}}, $1 }
    elsif ($line =~ /^Version:\s*(.+)\s*$/)        { $info->{version} ||= $1 }
    elsif ($line =~ /^Summary:\s*(.+)\s*$/)        { $info->{summary} ||= $1 }
    elsif ($line =~ /^Group:\s*(.+)\s*$/)          { $info->{group}   ||= $1 }
    elsif ($line =~ /^Url:\s*(.+)\s*$/i)           { $info->{url}     ||= $1 }

    # Legal review notices, non-standard but used in SUSE packages
    elsif ($line =~ /^\s*#+\s*Legal-Review-Notice:\s*(.+)\s*$/i) { push @{$info->{legal_review_notices}}, $1 }
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
sub _urls ($file, $meta) {
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
    $name  = undef if defined $name  and ($name eq lc $name or $name =~ m{[\(\):\d,\n\r]});

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
