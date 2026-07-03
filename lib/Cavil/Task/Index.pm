# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package Cavil::Task::Index;
use Mojo::Base 'Mojolicious::Plugin', -signatures;

use Cavil::Bom::Registry;
use Cavil::Checkout;
use Cavil::FileIndexer;
use Spooky::Patterns::XS;
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

  my $fi       = Cavil::FileIndexer->new($app, $id);
  my $preptime = time - $start;

  my $registry = Cavil::Bom::Registry->new;
  my %meta     = (emails => {}, urls => {}, components => {});
  for my $file (@$batch) {
    my ($path, $mime) = @$file;
    $fi->file(\%meta, $path, $mime);
    _detect_components($fi, $registry, \%meta, $path);
  }

  # URLs
  my $db  = $app->pg->db;
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

  my $total = time - $start;
  my $dir   = $fi->dir;
  $log->info(
    sprintf("[$id] Indexed batch of @{[scalar @$batch]} files from $dir (%.02f prep, %.02f total)", $preptime, $total));
}

# Recognise a vendored component from its embedded metadata file (e.g. package.json, Cargo.toml). Identity
# comes from the file content, so obscured/renamed/deep directory names do not matter.
sub _detect_components ($fi, $registry, $meta, $path) {
  return unless $registry->matches($path);

  # The project's own top-level manifest (at the source root, or directly inside the single top-level
  # directory a source archive unpacks to) describes the primary artifact under review, not a vendored
  # dependency. Skip it, otherwise the SBOM would list the package as a subcomponent of itself. Genuine
  # vendored components always sit deeper, nested inside a dependency directory (even an obscured one).
  return if ($path =~ tr{/}{}) <= 1;

  my $file = $fi->dir->child('.unpacked', $path);
  return unless -f $file && -s $file < 4_000_000;
  return unless defined(my $content = eval { $file->slurp });

  $meta->{components}{$_->{purl}} //= $_ for @{$registry->detect_file($path, \$content)};
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
