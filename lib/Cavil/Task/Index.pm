# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package Cavil::Task::Index;
use Mojo::Base 'Mojolicious::Plugin', -signatures;

use Cavil::Bom::Registry;
use Cavil::Checkout;
use Cavil::FileIndexer;
use Cavil::PatternEngine;
use Time::HiRes 'time';

sub register ($self, $app, $config) {
  $app->minion->add_task(index                 => \&_index);
  $app->minion->add_task(index_batch           => \&_index_batch);
  $app->minion->add_task(index_later           => \&_index_later);
  $app->minion->add_task(indexed               => \&_indexed);
  $app->minion->add_task(reindex_all           => \&_reindex_all);
  $app->minion->add_task(reindex_matched_later => \&_reindex_matched_later);
}

sub _index ($job, $id) {
  my $app    = $job->app;
  my $minion = $app->minion;
  my $pkgs   = $app->packages;
  my $log    = $app->log;

  # Protect from race conditions: an orphan reindex job can race a concurrent
  # re-import that has reset "unpacked" to NULL; back off and let the unpack
  # chain finish instead of failing (which would queue duplicate work on retry)
  unless ($pkgs->is_unpacked($id)) {
    my $retries = $job->retries;
    return $job->fail("Package $id is not unpacked yet (gave up after $retries retries)") if $retries >= 10;
    return $job->retry({delay => 60});
  }
  return $job->finish("Package $id is already being processed") unless $minion->lock("processing_pkg_$id", 172800);

  # Clean up (make sure not to leak a Postgres connection)
  {
    my $db = $app->pg->db;
    $db->update('bot_packages', {indexed => undef, checksum => undef}, {id => $id});
    $db->delete('matched_files',      {package => $id});
    $db->delete('urls',               {package => $id});
    $db->delete('emails',             {package => $id});
    $db->delete('package_components', {package => $id});
    $db->delete('bot_reports',        {package => $id});

    $pkgs->remove_spdx_report($id);
  }

  my $dir      = $pkgs->pkg_checkout_dir($id);
  my $checkout = Cavil::Checkout->new($dir);

  # Update file stats
  unless ($pkgs->has_file_stats($id)) {
    my $stats = $checkout->unpacked_file_stats;
    $pkgs->update_file_stats($id, $stats);
  }

  # Split up files into batches
  my $batches   = $checkout->unpacked_files($app->config->{index_bucket_average});
  my $parent_id = $job->id;
  my $prio      = $job->info->{priority};
  my @children  = map {
    $minion->enqueue(
      index_batch => [$id, $_] => {parents => [$parent_id], priority => $prio + 1, notes => {"pkg_$id" => 1}})
  } @$batches;
  $minion->enqueue(indexed => [$id] => {parents => \@children, priority => $prio + 2, notes => {"pkg_$id" => 1}});

  $log->info("[$id] Made @{[scalar @$batches]} batches for $dir");
}

sub _index_batch ($job, $id, $batch) {
  my $app = $job->app;
  my $log = $app->log;
  $app->plugins->emit_hook('before_task_index_batch');

  my $start = time;

  my $db       = $app->pg->db;
  my $fi       = Cavil::FileIndexer->new($app, $id, $db);
  my $preptime = time - $start;

  my $registry    = Cavil::Bom::Registry->new;
  my $single_root = _single_unpacked_root($fi->dir);
  my %meta        = (emails => {}, urls => {}, components => {});

  # Wrap the whole batch in one transaction: the per-file inserts (matched_files,
  # pattern_matches, file_snippets) plus the URL/email/component upserts below would otherwise
  # each autocommit separately, one round-trip per row. Committing once also makes the batch
  # atomic, so a mid-batch failure and Minion retry cannot leave half-inserted rows behind.
  my $tx = $db->begin;

  for my $file (@$batch) {
    my ($path, $mime) = @$file;
    $fi->file(\%meta, $path, $mime);
    _detect_components($fi, $registry, \%meta, $path, $single_root);
  }

  # URLs
  my $max = $app->config->{max_email_url_size};
  for my $url (sort keys %{$meta{urls}}) {
    next if length($url) > $max;
    $db->query(
      'insert into urls (package, url, hits) values ($1, $2, $3)
         on conflict (package, md5(url))
         do update set hits = urls.hits + $3', $id, $url, $meta{urls}{$url}
    );
  }

  # Email addresses
  for my $email (sort keys %{$meta{emails}}) {
    next if length($email) > $max;
    my $e = $meta{emails}{$email};
    $db->query(
      'insert into emails (package, email, name, hits)
           values ($1, $2, $3, $4)
         on conflict (package, md5(email))
         do update set hits = emails.hits + $4', $id, $email, $e->{name}, $e->{count}
    );
  }

  # Vendored subcomponents (identity from the embedded metadata file's content, deduped by purl across
  # the parallel batches via the upsert)
  for my $purl (sort keys %{$meta{components}}) {
    my $c = $meta{components}{$purl};
    $db->query(
      'insert into package_components (package, purl, type, name, version, license, source, complete)
           values ($1, $2, $3, $4, $5, $6, $7, true)
         on conflict (package, md5(purl))
         do update set license = coalesce(package_components.license, excluded.license)', $id, $purl, $c->{type},
      $c->{name}, $c->{version}, $c->{license}, $c->{source}
    );
  }

  $tx->commit;

  my $total = time - $start;
  my $dir   = $fi->dir;
  $log->info(
    sprintf("[$id] Indexed batch of @{[scalar @$batch]} files from $dir (%.02f prep, %.02f total)", $preptime, $total));
}

# The unpacked tree is a "single wrapper" when it has exactly one top-level directory (a conventional
# name-version/ source tarball). Multiple top-level directories mean several archives were unpacked side
# by side (a common OBS shape, since archive_name_as_dir is off and archives land directly under
# .unpacked), so a manifest one level down is a separate archive, not the primary root.
sub _single_unpacked_root ($dir) {
  my $unpacked = $dir->child('.unpacked');
  return 0 unless -d $unpacked;
  my $dirs = grep { -d $_ } $unpacked->list({dir => 1})->each;
  return $dirs == 1 ? 1 : 0;
}

# Recognise a vendored component from its embedded metadata file (e.g. package.json, Cargo.toml). Identity
# comes from the file content, so obscured/renamed/deep directory names do not matter.
sub _detect_components ($fi, $registry, $meta, $path, $single_root) {

  # The scanner re-emits any over-long-lined text file as "<name>.processed.<ext>" and lists only that
  # variant to the indexer (Cavil::PostProcess), so a metadata file with one long line (common in a
  # composer installed.json) would otherwise be invisible here. Detect on the canonical name and read the
  # original file (kept on disk) - never the processed copy, whose injected line breaks corrupt structured
  # metadata such as JSON.
  (my $orig = $path) =~ s{\.processed(\.[^./]+)$}{$1};
  $orig =~ s{\.processed$}{};

  return unless $registry->matches($orig);

  # A package manifest (package.json, Cargo.toml, ...) that describes the primary artifact under review
  # must not be reported as a vendored subcomponent, or the SBOM lists the package as a dependency of
  # itself. Such a manifest sits at the top of the source tree: at the unpacked root (depth 0), or one
  # level in when the tree is a single wrapper directory (a conventional name-version/ tarball). But when
  # several archives are unpacked side by side (multiple top-level directories), a depth-1 manifest is a
  # *separate* vendored archive (e.g. serde-1.0.197/Cargo.toml) and must be kept. Listing files (Go's
  # vendor/modules.txt) never describe the primary and are never skipped.
  #
  # Depth is measured against the package-root directory the manifest identifies. Python ships its
  # metadata inside a <name>.egg-info/ or <name>.dist-info/ directory, so the package root is one level
  # up from the metadata file - otherwise a project's own PKG-INFO/METADATA would sit at depth 2 and
  # self-list. For every other ecosystem the package root is simply the manifest's own directory.
  my $root = $orig =~ s{/[^/]*$}{}r;
  $root =~ s{(?:^|/)[^/]+\.(?:egg-info|dist-info)$}{};
  my $depth = $root eq '' ? 0 : ($root =~ tr{/}{}) + 1;
  return if $registry->is_self_manifest($orig) && ($depth == 0 || ($depth == 1 && $single_root));

  my $file = $fi->dir->child('.unpacked', $orig);
  return unless -f $file && -s $file < 4_000_000;
  return unless defined(my $content = eval { $file->slurp });

  $meta->{components}{$_->{purl}} //= $_ for @{$registry->detect_file($orig, \$content)};
}

sub _index_later ($job, $id) {
  $job->app->packages->reindex($id, $job->info->{priority} + 1);
}

sub _indexed ($job, $id) {
  my $app    = $job->app;
  my $minion = $job->minion;
  my $pkgs   = $job->app->packages;

  # Protect from race conditions
  $minion->unlock("processing_pkg_$id");

  $pkgs->indexed($id);

  # Next step - always high prio because the renderer
  # relies on it
  return $pkgs->analyze($id, 9, [$job->id]);
}

sub _reindex_all ($job) {
  $job->app->packages->reindex_all;
}

sub _reindex_matched_later ($job, $pid) {
  $job->app->packages->reindex_matched_packages($pid, $job->info->{priority});
}

1;
