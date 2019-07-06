# Copyright (C) 2018,2019 SUSE Linux GmbH
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

package Cavil::Task::Index;
use Mojo::Base 'Mojolicious::Plugin';

use Cavil::Checkout;
use Spooky::Patterns::XS;
use Time::HiRes 'time';

sub register {
  my ($self, $app) = @_;
  $app->minion->add_task(index                 => \&_index);
  $app->minion->add_task(index_batch           => \&_index_batch);
  $app->minion->add_task(index_later           => \&_index_later);
  $app->minion->add_task(indexed               => \&_indexed);
  $app->minion->add_task(reindex_all           => \&_reindex_all);
  $app->minion->add_task(reindex_matched_later => \&_reindex_matched_later);
}

sub _dump_snippet {
  my ($path, $first_line, $last_line) = @_;

  my %lines;
  for (my $line = $first_line; $line <= $last_line; $line += 1) {
    $lines{$line} = 1;
  }

  my $ctx = Spooky::Patterns::XS::init_hash(0, 0);
  for my $row (@{Spooky::Patterns::XS::read_lines($path, \%lines)}) {
    $ctx->add($row->[2] . "\n");
  }
  return $ctx->hex;
}

sub _find_near_line {
  my ($lines, $line, $line_delta, $delta) = @_;
  for (my $count = 0; $count < $line_delta; $count++, $line += $delta) {
    return $line if defined $lines->{$line};
  }
  return undef;
}

sub _index {
  my ($job, $id) = @_;

  my $app     = $job->app;
  my $log     = $app->log;
  my $dir     = $app->package_checkout_dir($id);
  my $batches = Cavil::Checkout->new($dir)
    ->unpacked_files($app->config->{index_bucket_average});

  # Clean up
  my $db = $app->pg->db;
  $db->delete('matched_files', {package => $id});
  $db->delete('urls',          {package => $id});
  $db->delete('emails',        {package => $id});

  # Split up files into batches
  my $minion    = $app->minion;
  my $parent_id = $job->id;
  my $prio      = $job->info->{priority};
  my @children  = map {
    $minion->enqueue(index_batch => [$id, $_] =>
        {parents => [$parent_id], priority => $prio + 1})
  } @$batches;
  $minion->enqueue(
    indexed => [$id] => {parents => \@children, priority => $prio + 2});

  $log->info("[$id] Made @{[scalar @$batches]} batches for $dir");
}

sub _index_batch_file {
  my ($matcher, $checkout, $db, $package, $keywords, $meta, $dir, $path, $mime)
    = @_;

  my $report = $checkout->keyword_report($matcher, $meta, $path);
  return unless $report;

  my $file_id;
  my $keyword_missed;

  for my $match (@{$report->{matches}}) {
    $file_id ||= $db->insert(
      'matched_files',
      {package   => $package, filename => $path, mimetype => $mime},
      {returning => 'id'}
    )->hash->{id};
    my ($mid, $ls, $le) = @$match;

    $keyword_missed ||= $keywords->{$mid};

    # package is kind of duplicated in file, but the join is just too expensive
    $db->insert(
      'pattern_matches',
      {
        file    => $file_id,
        package => $package,
        pattern => $mid,
        sline   => $ls,
        eline   => $le
      }
    );
  }
  return unless $keyword_missed;

  # extract missed snippets
  my %needed_lines;

  # pick uncategorized matches first
  for my $match (@{$report->{matches}}) {
    my ($mid, $ls, $le) = @$match;
    next unless $keywords->{$mid};
    my $line = $ls - 1;
    while ($line <= $le + 1) {
      $needed_lines{$line++} = 1;
    }
  }

  # possible skip between the keyword areas
  my $delta = 6;

  # extend to near matches
  for my $match (@{$report->{matches}}) {
    my ($mid, $ls, $le) = @$match;
    my $prev_line   = _find_near_line(\%needed_lines, $ls - 2, $delta, -1);
    my $follow_line = _find_near_line(\%needed_lines, $le + 2, $delta, +1);
    next unless $prev_line || $follow_line;
    $prev_line   ||= $ls;
    $follow_line ||= $le;
    for (my $line = $prev_line; $line <= $follow_line; $line++) {
      $needed_lines{$line} = 1;
    }
  }

  $path = $dir->child('.unpacked', $path);

  # process snippet areas
  my $prev_line;
  my $first_snippet_line;
  for my $line (sort { $a <=> $b } keys %needed_lines) {
    if ($prev_line && $line - $prev_line > 1) {
      _dump_snippet($path, $first_snippet_line, $prev_line);
      $first_snippet_line = undef;
    }
    $first_snippet_line ||= $line;
    $prev_line = $line;
  }
  _dump_snippet($path, $first_snippet_line, $prev_line) if $first_snippet_line;
}

sub _index_batch {
  my ($job, $id, $batch) = @_;

  my $app = $job->app;
  my $log = $app->log;
  $app->plugins->emit_hook('before_task_index_batch');

  my $dir      = $app->package_checkout_dir($id);
  my $checkout = Cavil::Checkout->new($dir);

  my $start   = time;
  my $db      = $app->pg->db;
  my $matcher = Spooky::Patterns::XS::init_matcher();
  my $keywords
    = $db->select('license_patterns', 'id', {license_string => undef});
  my %keyword_patterns;
  map { $keyword_patterns{$_->{id}} = 1 } @{$keywords->hashes};

  my $packagename
    = $db->select('bot_packages', 'name', {id => $id})->hash->{name};
  $app->patterns->load_unspecific($matcher);
  $app->patterns->load_specific($matcher, $packagename);
  my $preptime = time - $start;

  my %meta = (emails => {}, urls => {});
  for my $file (@$batch) {
    my ($path, $mime) = @$file;
    _index_batch_file($matcher, $checkout, $db, $id, \%keyword_patterns,
      \%meta, $dir, $path, $mime);
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
         do update set hits = emails.hits + $4', $id, $email, $e->{name},
      $e->{count}
    );
  }
  my $total = time - $start;
  $log->info(
    sprintf(
      "[$id] Indexed batch of @{[scalar @$batch]} files from $dir (%.02f prep, %.02f total)",
      $preptime, $total
    )
  );
}

sub _index_later {
  my ($job, $id) = @_;
  $job->app->packages->reindex($id, $job->info->{priority} + 1);
}

sub _indexed {
  my ($job, $id) = @_;

  my $pkgs = $job->app->packages;
  $pkgs->indexed($id);

  # Next step - always high prio because the renderer
  # relies on it
  $pkgs->analyze($id, 9, [$job->id]);
}

sub _reindex_all {
  my $job = shift;
  $job->app->packages->reindex_all;
}

sub _reindex_matched_later {
  my ($job, $pid) = @_;
  $job->app->packages->reindex_matched_packages($pid, $job->info->{priority});
}

1;
