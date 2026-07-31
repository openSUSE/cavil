# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package Cavil::Model::Packages;
use Mojo::Base -base, -signatures;

use Cavil::Util qw(paginate PRIORITY_INCOMING PRIORITY_SWEEP PRIORITY_UPKEEP PRIORITY_WAITING);
use Mojo::File  qw(path);
use Mojo::Util  qw(dumper scope_guard);
use Text::Glob  qw(glob_to_regex);

has [qw(checkout_dir classifier log minion pg)];

sub add ($self, %args) {

  my $db     = $self->pg->db;
  my $source = {
    api_url => $args{api_url},
    project => $args{project},
    package => $args{package},
    srcmd5  => $args{srcmd5},
    type    => $args{type} // 'obs'
  };
  my $source_id = $db->insert('bot_sources', $source, {returning => 'id'})->hash->{id};

  my $pkg = {
    name            => $args{name},
    checkout_dir    => $args{checkout_dir},
    created         => $args{created} || scalar localtime,
    source          => $source_id,
    requesting_user => $args{requesting_user},
    priority        => $args{priority},
    state           => 'new',
    embargoed       => $args{embargoed} ? 1 : 0
  };
  return $db->insert('bot_packages', $pkg, {returning => 'id'})->hash->{id};
}

sub actions ($self, $link, $id) {

  # Requests with multiple actions are an OBS thing
  return [] if !$link || !($link =~ /^obs#/ || $link =~ /^ibs#/);

  return $self->pg->db->query(
    "select p.id, p.name, result, state, login,
       extract(epoch from created) as created_epoch, obsolete
     from bot_packages p left join bot_users u on p.reviewing_user = u.id
     where external_link = ? and p.id != ?
     order by p.id desc", $link, $id
  )->hashes->to_array;
}

sub all ($self) { $self->pg->db->select('bot_packages')->hashes }

# A plain re-analyze (no generation) touches no files and rewrites nothing but the report row, so the
# default priority is above every band in Cavil::Util, clear of even the highest a build can climb to: it
# is a few seconds of work standing between a reviewer and a corrected report, and making it wait for the
# queue would cost far more than it saves. The analyze that ends a build passes its own priority instead
# and stays in the build's band.
sub analyze ($self, $id, $priority = 100, $parents = [], $generation = 0) {

  # Without a generation this is a plain re-analyze of the live report, which deduplicates like any other
  # per-package job
  return $self->_enqueue('analyze', $id, $priority, $parents) unless $generation;

  # An analyze that promotes a build must never be deduplicated away against a plain re-analyze that
  # happens to be queued: the build's rows only become the live report when this exact job runs, so
  # dropping it would strand the generation and leave the package claimed by a build that never promotes
  my $pkg = $self->find($id);
  return $self->minion->enqueue(
    analyze => [$id, $generation] => {
      parents  => $parents,
      priority => $priority,
      notes    => {external_link => $pkg->{external_link}, package => $pkg->{name}, "pkg_$id" => 1}
    }
  );
}

# One owner at a time. Every job that rewrites a package's checkout or its report claims the package row
# before it starts and hands it back when it is done, so an unpack cannot pull the sources out from under
# an indexing run and two rebuilds cannot fight over one report. The owner is the id of the Minion job
# holding it, which buys three things a lock did not: there is no expiry to outlive a slow build (a
# reindex of a large package can run for hours), the build hands the package back in the very transaction
# that promotes its report, and a claim stranded by a worker that died is recovered the way admins already
# recover everything else - retrying the failed job in the Minion admin UI re-claims the package, because
# the claim it finds is its own.
sub claim ($self, $id, $job_id) {
  return !!$self->pg->db->query(
    'UPDATE bot_packages SET processing_job = ?
      WHERE id = ? AND (processing_job IS NULL OR processing_job = ?) RETURNING id', $job_id, $id, $job_id
  )->rows;
}

# Claim the package for as long as the caller's scope lives, for jobs that do all their work themselves. A
# report build spans four jobs and so claims and releases by hand instead.
sub claim_guard ($self, $id, $job_id) {
  return undef unless $self->claim($id, $job_id);
  return scope_guard sub { $self->release($id, $job_id) };
}

# Hand the package back, but only while we are still the owner: a job whose claim was taken over by the
# cleanup sweep must not clear the claim of whoever has it now on its way out.
sub release ($self, $id, $job_id) {
  $self->pg->db->query('UPDATE bot_packages SET processing_job = NULL WHERE id = ? AND processing_job = ?',
    $id, $job_id);
}

# Hand the package back at the end of a chain of jobs, and start the rebuild it owes. Reindexes requested
# while the package was busy are only written down (see request_reindex), so somebody has to act on them
# once it is free, and that is whoever lets go of it last - otherwise the request sits there until the
# nightly sweep, with the report page read-only the whole time. Only the successful path calls this; a job
# that dies just releases, and its retry hands back instead. The order is not delicate: an index job that
# is already queued for the package is deduplicated away, and a request arriving right after this ran
# finds the package free and enqueues its own build.
sub hand_back ($self, $id, $job_id) {
  $self->release($id, $job_id);

  # The rebuild runs at the priority whoever asked for it would have got, so a reviewer who clicked
  # Reindex while the package was busy is still ahead of the weekly sweep afterwards
  return unless defined(my $priority = $self->reindex_request($id));

  # Only clear the request once the build that answers it exists. A package that has become ineligible in
  # the meantime (obsoleted, never indexed) keeps it, and the sweep clears it along with the package.
  return unless ($self->reindex($id, $priority) // '') eq 'now';
  $self->log->info("[$id] Reindex was requested while the package was busy, queueing it now");
  $self->clear_reindex_request($id);
}

# Enqueue the classify job when this package has snippets awaiting the classifier, coalesced to a single
# pending run. The job is guarded and drains every package's snippets in one pass, so one queued run is
# enough however many packages were analyzed. Packages whose snippets are all classified (the reindex
# case) enqueue nothing, and so does an instance with no classifier configured to consume the snippets.
sub classify ($self, $id) {
  return unless $self->classifier->url;

  # Generation 0 only: this runs after the promote, so the build's rows are the live ones by now
  my $db = $self->pg->db;
  return unless $db->query(
    'SELECT 1 FROM file_snippets fs JOIN snippets s ON s.id = fs.snippet
      WHERE fs.package = ? AND fs.generation = 0 AND s.classified = FALSE AND s.approved = FALSE LIMIT 1', $id
  )->rows;

  my $minion = $self->minion;
  return if $minion->jobs({tasks => ['classify'], states => ['inactive']})->total;
  $minion->enqueue(classify => [] => {priority => PRIORITY_INCOMING});
}

sub cleanup ($self, $id, $job_id) {
  my $db  = $self->pg->db;
  my $log = $self->log;

  # The claim is what keeps anybody else out while the checkout is torn down, and it is taken before the
  # transaction below rather than inside it. Claiming is a row update of its own, so holding it and a
  # locked package row on two connections at once would be a deadlock waiting to happen.
  return unless my $guard = $self->claim_guard($id, $job_id);

  my $pkg = $db->select('bot_packages', ['name', 'checkout_dir', 'obsolete'], {id => $id})->hash;
  return if !$pkg || !$pkg->{obsolete};

  my $dir = path($self->checkout_dir, $pkg->{name}, $pkg->{checkout_dir});
  if (-d $dir) {
    $log->info("[$id] Removing checkout $pkg->{name}/$pkg->{checkout_dir}");
    $dir->remove_tree;
  }

  # Scoped so the transaction is finished before the guard hands the package back, whichever way this ends
  {
    my $tx = $db->begin;
    $db->query('UPDATE bot_packages SET cleaned = NOW() WHERE id = ?', $id);

    # No generation predicate on purpose: the package is obsolete and going away, so everything it owns
    # goes, including the rows of a reindex that was still building when it was superseded
    $db->query('delete from bot_reports where package = ?',        $id);
    $db->query('delete from emails where package = ?',             $id);
    $db->query('delete from urls where package = ?',               $id);
    $db->query('delete from package_components where package = ?', $id);
    $db->query('delete from pattern_matches where package = ?',    $id);
    $db->query('delete from matched_files where package = ?',      $id);
    $tx->commit;
  }
}

sub pkg_checkout_dir ($self, $id) {
  my $pkg = $self->find($id);
  return path($self->checkout_dir, $pkg->{name}, $pkg->{checkout_dir});
}

# Does the glob match at least one of the package's matched (reported) files? A glob only reduces
# noise if it covers files that actually appear in the report, and matched_files is a small,
# bounded set - so this check stays cheap even for packages with millions of files on disk, and
# it uses the same filename basis that dig_report applies globs against.
sub glob_matches_report_files ($self, $id, $glob) {
  local $Text::Glob::strict_wildcard_slash = 0;
  my $regex = glob_to_regex($glob);

  my $files = $self->pg->db->select('matched_files', ['filename'], {package => $id, generation => 0});
  while (my $file = $files->hash) {
    next unless $file->{filename} =~ $regex;
    $files->finish;
    return 1;
  }
  return 0;
}

sub find ($self, $id) {
  return $self->pg->db->select(
    ['bot_packages', [-left => 'bot_users', id => 'reviewing_user']],
    [
      'bot_packages.*',
      \'extract(epoch from bot_packages.created)  as created_epoch',
      \'extract(epoch from bot_packages.reviewed) as reviewed_epoch',
      \'extract(epoch from bot_packages.imported) as imported_epoch',
      \'extract(epoch from bot_packages.unpacked) as unpacked_epoch',
      \'extract(epoch from bot_packages.indexed)  as indexed_epoch',
      \'bot_users.login as login'
    ],
    {'bot_packages.id' => $id}
  )->hash;
}

sub find_by_link ($self, $link) {
  return $self->pg->db->query('SELECT id FROM bot_packages WHERE external_link = ? AND obsolete = FALSE', $link)
    ->arrays->flatten->to_array;
}

sub find_by_name_and_md5 ($self, $pkg, $md5) {
  return $self->pg->db->select('bot_packages', '*', {name => $pkg, checkout_dir => $md5})->hash;
}

sub flags ($self, $id, $generation = 0) {

  # Only include flags that have a field in the bot_packages table
  my @flags = qw(patent trademark export_restricted cla eula);
  my $flags = {map { $_ => 0 } @flags};

  my $results = $self->pg->db->query(
    qq{
      SELECT patent, trademark, export_restricted, cla, eula
      FROM pattern_matches pm JOIN license_patterns lp ON pm.pattern = lp.id
      WHERE pm.package = ? AND pm.generation = ? AND pm.ignored = false
        AND (lp.patent = true OR lp.trademark = true OR lp.export_restricted = true
             OR lp.cla = true OR lp.eula = true)
    }, $id, $generation
  )->hashes->to_array;
  for my $result (@$results) {
    for my $flag (@flags) {
      $flags->{$flag} = 1 if $result->{$flag};
    }
  }

  return $flags;
}

# Nothing to do when the report is already on disk, and nothing to do when one is already on its way. The
# queue itself is the record of the latter, the same way it is for every other job here: a job that fails,
# is removed or never gets dequeued takes its own claim to the work with it. A Minion lock used to stand in
# for that, and it outlived the job it belonged to - a build whose "analyzed" job failed left the lock
# behind for its full two days, and for those two days the package could not be given a report at all,
# because every attempt quietly refused to enqueue one and /spdx/<id> just kept saying "not ready".
#
# By default somebody is sitting in front of the download waiting for it, so it goes in at the top of the
# ladder in Cavil::Util. The build that ends in one passes its own priority and stays in its band.
sub generate_spdx_report ($self, $id, $options = {}) {
  return if $self->has_spdx_report($id);

  my $minion = $self->minion;
  return if $minion->jobs({tasks => ['spdx_report'], states => ['inactive', 'active'], notes => ["pkg_$id"]})->total;
  $minion->enqueue('spdx_report' => [$id] => {priority => PRIORITY_WAITING, notes => {"pkg_$id" => 1}, %$options});
}

sub has_file_stats ($self, $id) {
  return defined($self->pg->db->select('bot_packages', 'unpacked_files', {id => $id})->hash->{unpacked_files});
}

sub has_manual_review ($self, $name) {
  return !!$self->pg->db->query('SELECT COUNT(*) FROM bot_packages WHERE name = ? AND reviewing_user IS NOT NULL',
    $name)->array->[0];
}

sub has_spdx_report ($self, $id) {
  return -f $self->spdx_report_path($id);
}

sub history ($self, $name, $checksum, $id) {
  return $self->pg->db->query(
    "select p.id, external_link, result, state, login,
       extract(epoch from created) as created_epoch, obsolete
     from bot_packages p left join bot_users u on p.reviewing_user = u.id
     where name = ? and checksum = ? and p.id != ? and state != 'new'
     order by p.id desc", $name, $checksum, $id
  )->hashes->to_array;
}

sub ignore_line ($self, $options) {
  my $db       = $self->pg->db;
  my $inserted = $db->query(
    'insert into ignored_lines (hash, packname, owner, contributor) values (?, ?, ?, ?)
     on conflict do nothing returning id', $options->{hash}, $options->{package}, $options->{owner},
    $options->{contributor}
  )->hash;
  my $ignore_id
    = $inserted
    ? $inserted->{id}
    : $db->select('ignored_lines', 'id', {hash => $options->{hash}, packname => $options->{package}})->hash->{id};

  # A new ignored_lines row does not change file contents or pattern definitions, so a full reindex is
  # unnecessary. No generation predicate: pm.file = fs.file pins both sides to the same generation anyway,
  # and a reindex building right now should carry the ignore into the report it is about to promote.
  $db->query(
    'update pattern_matches pm
       set ignored = true, ignored_line = ?
       from file_snippets fs, snippets s, bot_packages bp
       where pm.file = fs.file
         and pm.package = fs.package
         and fs.snippet = s.id
         and pm.package = bp.id
         and s.hash = ?
         and bp.name = ?
         and bp.obsolete = false
         and bp.indexed is not null
         and pm.sline <= fs.eline
         and pm.eline >= fs.sline
         and pm.ignored = false', $ignore_id, $options->{hash}, $options->{package}
  );

  my $ids = $db->select('bot_packages', 'id', {name => $options->{package}, obsolete => 0, indexed => {'!=' => undef}})
    ->arrays->flatten->to_array;
  $self->analyze($_) for @$ids;
}

sub remove_ignored_line ($self, $id, $user) {
  return undef
    unless my $hash = $self->pg->db->delete('ignored_lines', {id => $id}, {returning => ['hash', 'packname']})->hash;
  $self->log->info(qq{User "$user" removed ignored match "$hash->{hash}"});

  $self->reindex_packages($hash->{packname});

  return 1;
}

sub imported ($self, $id) {
  $self->pg->db->query('UPDATE bot_packages SET imported = NOW(), cleaned = NULL WHERE id = ?', $id);
}

sub index ($self, @args) { $self->_enqueue('index', @args) }

sub indexed ($self, $id) {
  $self->pg->db->update('bot_packages', {indexed => \'now()'}, {id => $id});
}

# How far along the rebuild of this package is, for the progress bar on the report page. Kept on the
# package row so the page can poll it without asking Minion on every request from every open tab.
sub index_stage ($self, $id, $stage) {
  $self->pg->db->update('bot_packages', {index_stage => $stage}, {id => $id});
}

# Is this package still building the given generation? A build's claim on the package *is* its generation
# (both are the id of its index job), so this asks whether the build still owns what it is about to
# promote. A build the cleanup sweep has discarded, or one that was promoted already, must not be swapped
# in (again).
sub is_building ($self, $id, $generation) {
  return !!$self->pg->db->select('bot_packages', 'id', {id => $id, processing_job => $generation})->hash;
}

sub is_imported ($self, @args) { $self->_check_field('imported', @args) }
sub is_indexed  ($self, @args) { $self->_check_field('indexed',  @args) }
sub is_obsolete ($self, @args) { $self->_check_field('obsolete', @args) }
sub is_unpacked ($self, @args) { $self->_check_field('unpacked', @args) }

# Iteration number for the next SBOM of this package. The SBOM URI is derived from the package id and so
# stays the same every time the report is rebuilt - a reindex, a reclassified snippet or an edited pattern
# all change what the report says without changing what it is called. The counter is what lets a recipient
# tell two iterations apart. It counts generations rather than content changes, so a rebuild that happens
# to produce an identical report still advances it; comparing two reports to avoid that is not worth it.
sub next_sbom_version ($self, $id) {
  return $self->pg->db->query(
    'UPDATE bot_packages SET sbom_version = sbom_version + 1 WHERE id = ? RETURNING sbom_version', $id)
    ->hash->{sbom_version};
}

sub old_reviews ($self, $pkg) {
  return $self->pg->db->select(
    'bot_packages',
    'id,checksum',
    {
      name     => $pkg->{name},
      state    => [qw(acceptable acceptable_by_lawyer)],
      id       => {'!=' => $pkg->{id}},
      obsolete => 0,
      indexed  => {'!=' => undef}
    },
    {-desc => 'id'}
  )->hashes->to_array;
}

sub paginate_open_reviews ($self, $options) {
  my $db = $self->pg->db;

  my $search = '';
  if (length($options->{search}) > 0) {
    my $quoted = $db->dbh->quote("\%$options->{search}\%");
    $search = "AND (checksum ILIKE $quoted OR external_link ILIKE $quoted OR name ILIKE $quoted)";
  }

  my $priority = '';
  if ($options->{priority}) {
    my $quoted = $db->dbh->quote($options->{priority});
    $priority = "AND priority >= $quoted";
  }

  my $progress = '';
  if ($options->{in_progress} eq 'true') {
    $progress = 'AND (unpacked IS NULL OR indexed IS NULL)';
  }

  my $embargoed = '';
  if ($options->{not_embargoed} eq 'true') {
    $embargoed = 'AND embargoed = false';
  }

  my $results = $db->query(
    qq{
      SELECT id, name, EXTRACT(EPOCH FROM created) as created_epoch, EXTRACT(EPOCH FROM imported) as imported_epoch,
        EXTRACT(EPOCH FROM unpacked) as unpacked_epoch, EXTRACT(EPOCH FROM indexed) as indexed_epoch, external_link,
        priority, state, checksum, unresolved_matches, COUNT(*) OVER() AS total
      FROM bot_packages
      WHERE state = 'new' AND obsolete = FALSE $priority $search $progress $embargoed
      ORDER BY priority DESC, external_link, unresolved_matches, name
      LIMIT ? OFFSET ?
    }, $options->{limit}, $options->{offset}
  )->hashes->to_array;

  return paginate($results, $options);
}

sub paginate_product_reviews ($self, $name, $options) {
  my $db = $self->pg->db;

  return paginate([], $options) unless my $product = $db->select('bot_products', 'id', {name => $name})->hash;

  my $attention = '';
  if ($options->{attention} eq 'true') {
    $attention = "AND state IN ('unacceptable', 'new')";
  }

  my $unresolved = '';
  if ($options->{unresolved_matches} eq 'true') {
    $unresolved = "AND unresolved_matches > 0";
  }

  my $search = '';
  if (length($options->{search}) > 0) {
    my $quoted = $db->dbh->quote("\%$options->{search}\%");
    $search = "AND (checksum ILIKE $quoted OR state::text ILIKE $quoted OR name ILIKE $quoted)";
  }

  my $patent = '';
  if ($options->{patent} eq 'true') {
    $patent = 'AND patent = true';
  }

  my $trademark = '';
  if ($options->{trademark} eq 'true') {
    $trademark = 'AND trademark = true';
  }

  my $export_restricted = '';
  if ($options->{export_restricted} eq 'true') {
    $export_restricted = 'AND export_restricted = true';
  }

  my $cla = '';
  if ($options->{cla} eq 'true') {
    $cla = 'AND cla = true';
  }

  my $eula = '';
  if ($options->{eula} eq 'true') {
    $eula = 'AND eula = true';
  }

  my $results = $db->query(
    qq{
      SELECT bot_packages.name, bot_packages.id, EXTRACT(EPOCH FROM imported) as imported_epoch,
        EXTRACT(EPOCH FROM unpacked) as unpacked_epoch, EXTRACT(EPOCH FROM indexed) as indexed_epoch, state,
        checksum, unresolved_matches, COUNT(*) OVER() AS total
      FROM bot_package_products JOIN bot_packages ON (bot_packages.id = bot_package_products.package)
      WHERE bot_package_products.product = ? $search $attention $unresolved $patent $trademark $export_restricted
        $cla $eula
      ORDER BY bot_packages.id DESC
      LIMIT ? OFFSET ?
    }, $product->{id}, $options->{limit}, $options->{offset}
  )->hashes->to_array;

  return paginate($results, $options);
}

sub paginate_recent_reviews ($self, $options) {
  my $db = $self->pg->db;

  my $search = '';
  if (length($options->{search}) > 0) {
    my $quoted = $db->dbh->quote("\%$options->{search}\%");
    $search = "
      AND (
        p.checksum ILIKE $quoted
        OR p.external_link ILIKE $quoted
        OR p.name ILIKE $quoted
        OR p.state::text ILIKE $quoted
        OR p.result ILIKE $quoted
      )";
  }

  my $user = '';
  if ($options->{by_user} eq 'true') {
    $user = 'AND p.reviewing_user IS NOT NULL';
  }

  my $ai_assisted = '';
  if ($options->{ai_assisted} eq 'true') {
    $ai_assisted = 'AND p.ai_assisted = true';
  }

  my $unresolved = '';
  if ($options->{unresolved_matches} eq 'true') {
    $unresolved = "AND unresolved_matches > 0";
  }

  my $results = $db->query(
    qq{
      SELECT p.id, p.name, u.login, p.result, p.ai_assisted, EXTRACT(EPOCH FROM p.created) AS created_epoch,
        EXTRACT(EPOCH FROM p.reviewed) AS reviewed_epoch, EXTRACT(EPOCH FROM p.imported) as imported_epoch,
        EXTRACT(EPOCH FROM p.unpacked) as unpacked_epoch, EXTRACT(EPOCH FROM p.indexed) as indexed_epoch,
        external_link, priority, state, checksum, unresolved_matches, COUNT(*) OVER() AS total
       FROM bot_packages p
         LEFT JOIN bot_users u ON p.reviewing_user = u.id
       WHERE reviewed IS NOT NULL AND reviewed > NOW() - INTERVAL '90 DAYS' $search $user $ai_assisted $unresolved
       ORDER BY reviewed DESC
       LIMIT ? OFFSET ?
    }, $options->{limit}, $options->{offset}
  )->hashes->to_array;

  return paginate($results, $options);
}

sub paginate_review_search ($self, $name, $options) {
  my $db = $self->pg->db;

  # Generation 0 only: a reindex building alongside the live report is not yet what anybody is searching
  my $packages;
  if ($options->{pattern}) {
    $packages = $db->query('SELECT DISTINCT(package) FROM pattern_matches WHERE pattern = ? AND generation = 0',
      $options->{pattern})->arrays->flatten;
  }

  if ($options->{ignore}) {
    $packages = $db->query('SELECT DISTINCT(package) FROM pattern_matches WHERE ignored_line = ? AND generation = 0',
      $options->{ignore})->arrays->flatten;
  }

  # Find every package that ships a given vendored component (by name or purl, case-insensitive
  # substring - so "lodash" matches all versions and "pkg:npm/lodash@4.17.20" pins one). The term is
  # user input, so it is quoted.
  if (length($options->{component} // '') > 0) {
    my $like = $db->dbh->quote('%' . $options->{component} . '%');
    $packages
      = $db->query(
      "SELECT DISTINCT(package) FROM package_components WHERE generation = 0 AND (purl ILIKE $like OR name ILIKE $like)"
      )->arrays->flatten;
  }

  my $search = '';
  if (length($options->{search}) > 0) {
    my $quoted = $db->dbh->quote("\%$options->{search}\%");
    $search = qq{AND (
                   p.checksum ILIKE $quoted
                   OR p.result ILIKE $quoted
                   OR u.login ILIKE $quoted
                   OR p.state::text ILIKE $quoted
                 )};
  }

  my $obsolete = '';
  if ($options->{not_obsolete} eq 'true') {
    $obsolete = 'AND (obsolete IS FALSE)';
  }

  # Hide embargoed packages (used by the API, which must not expose them - mirrors paginate_open_reviews)
  my $embargoed = '';
  if (($options->{not_embargoed} // '') eq 'true') {
    $embargoed = 'AND (p.embargoed IS FALSE)';
  }

  my $results = $db->query(
    qq{
      SELECT p.id AS id, name AS package, state, checksum, p.result AS comment,
        EXTRACT(EPOCH FROM p.created) AS created_epoch, EXTRACT(EPOCH FROM p.imported) AS imported_epoch,
        EXTRACT(EPOCH FROM p.unpacked) AS unpacked_epoch, EXTRACT(EPOCH FROM p.indexed) AS indexed_epoch,
        u.login AS user,  unresolved_matches, COUNT(*) OVER() AS total
      FROM bot_packages p LEFT JOIN bot_users u ON p.reviewing_user = u.id
      WHERE (name = \$1 OR \$1 IS NULL) AND (p.id = ANY (\$2) OR \$2 IS NULL) $search $obsolete $embargoed
      ORDER BY id DESC
      LIMIT \$3 OFFSET \$4
    }, $name || undef, $packages, $options->{limit}, $options->{offset}
  )->hashes->to_array;

  return paginate($results, $options);
}

# For a set of package ids, return the vendored components matching a name/purl substring, grouped by
# package id. Used by the API component search to show which exact version each package ships.
sub matching_components ($self, $ids, $query) {
  return {} unless @$ids && length($query // '');

  my $like = '%' . $query . '%';
  my $rows = $self->pg->db->query(
    'SELECT package, type, name, version, purl, license FROM package_components
       WHERE package = ANY (?) AND generation = 0 AND (purl ILIKE ? OR name ILIKE ?)
     ORDER BY name, version', $ids, $like, $like
  )->hashes;

  my %by_package;
  for my $row ($rows->each) {
    push @{$by_package{$row->{package}}},
      {
      type    => $row->{type},
      name    => $row->{name},
      version => $row->{version},
      purl    => $row->{purl},
      license => $row->{license}
      };
  }

  return \%by_package;
}

# Stream every detected vendored component with its package and product for a full export, invoking
# $cb->($row) per row. A package in several products fans out to one row per product; a package in no
# product yields a single row with product => undef (the caller falls back to external_link). Embargoed
# and obsolete packages are excluded. A server-side cursor keeps client memory flat over the full set.
sub export_components ($self, $cb) {
  my $db = $self->pg->db;
  my $tx = $db->begin;

  $db->query(
    q{
    DECLARE cavil_component_export NO SCROLL CURSOR FOR
      SELECT p.name AS package, p.checkout_dir AS checkout_dir, p.external_link AS external_link,
             pc.type AS source, pc.name AS component, pc.version AS version,
             prod.name AS product
        FROM package_components pc
        JOIN bot_packages p                ON p.id = pc.package
        LEFT JOIN bot_package_products pp   ON pp.package = p.id
        LEFT JOIN bot_products prod         ON prod.id = pp.product
       WHERE pc.generation = 0 AND p.embargoed = FALSE AND p.obsolete = FALSE
       ORDER BY p.id, pc.name, pc.version
  }
  );

  while (1) {
    my $rows = $db->query('FETCH FORWARD 5000 FROM cavil_component_export')->hashes;
    last unless @$rows;
    $cb->($_) for @$rows;
  }

  $db->query('CLOSE cavil_component_export');
}

# Same deal as reindex_package_ids, one step further back: the list of packages a pattern matches is not
# even known yet, so finding it out is a job of its own
sub mark_matched_for_reindex ($self, $pid, $priority = PRIORITY_UPKEEP) {
  $self->minion->enqueue(reindex_matched_later => [$pid] => {priority => $priority - 1});
}

sub need_cleanup ($self) {
  return $self->pg->db->query('SELECT id FROM bot_packages WHERE obsolete IS TRUE AND cleaned IS NULL ORDER BY ID')
    ->arrays->flatten->to_array;
}

# Every package that is not in a clean, settled state as far as reindexing goes: one with rows from a
# report build that is not the live report, one still claimed by a job or stuck at a rebuild stage (a
# failed unpack leaves that behind), or one with a reindex request waiting to be picked up. Driven by
# partial indexes on the (huge) row tables, so the common answer - nothing at all - costs almost nothing.
sub unsettled_builds ($self) {
  return $self->pg->db->query(
    'SELECT DISTINCT package FROM matched_files      WHERE generation <> 0
      UNION SELECT DISTINCT package FROM urls               WHERE generation <> 0
      UNION SELECT DISTINCT package FROM emails             WHERE generation <> 0
      UNION SELECT DISTINCT package FROM package_components WHERE generation <> 0
      UNION SELECT id FROM bot_packages
              WHERE processing_job IS NOT NULL OR index_stage IS NOT NULL OR reindex_requested IS NOT NULL'
  )->arrays->flatten->to_array;
}

# Throw away every row that does not belong to the live report of this package and reset its build state,
# but only while the package is still owned by exactly who the caller saw owning it (including nobody).
# Called by the cleanup sweep once Minion has confirmed no job for the package is queued or running; the
# compare-and-swap closes the gap between that question and this answer, so a build that starts in between
# keeps both its claim and its rows. Returns the number of rows discarded, or undef when the package has
# moved on since - which also means two sweeps cannot both take the same package.
sub discard_builds ($self, $id, $owner) {
  my $db = $self->pg->db;

  my $tx = $db->begin;
  return undef unless $db->query(
    'UPDATE bot_packages SET processing_job = NULL, index_stage = NULL
      WHERE id = ? AND processing_job IS NOT DISTINCT FROM ? RETURNING id', $id, $owner
  )->rows;

  # matched_files last: pattern_matches and file_snippets cascade from it
  my $deleted = 0;
  $deleted += $db->query("DELETE FROM $_ WHERE package = ? AND generation <> 0", $id)->rows
    for qw(package_components urls emails matched_files);
  $tx->commit;

  return $deleted;
}

# Take the package away from whoever owns it, for an admin re-unpacking a package that is stuck. The rows
# of a build that was still in flight are left behind on purpose: they are invisible to readers, and the
# cleanup sweep collects them once Minion agrees nothing is working on the package any more.
sub force_release ($self, $id) {
  return !!$self->pg->db->query(
    'UPDATE bot_packages SET processing_job = NULL, index_stage = NULL
      WHERE id = ? AND (processing_job IS NOT NULL OR index_stage IS NOT NULL) RETURNING id', $id
  )->rows;
}

sub name_autocomplete ($self, $partial, $limit = 10) {
  return [] unless defined $partial && length $partial;

  my $prefix    = $partial . '%';
  my $substring = '%' . $partial . '%';

  # Blend prefix, substring and trigram matches (typo tolerance) into a single
  # ranking: exact prefixes first, then by trigram similarity, then by length.
  # The inner DISTINCT collapses the per-version rows in bot_packages down to
  # unique names and lets the gin_trgm_ops index serve both the ILIKE and the
  # "%" (similarity) lookups.
  return $self->pg->db->query(
    q{SELECT name FROM (
        SELECT DISTINCT name, similarity(name, ?) AS sml
          FROM bot_packages
         WHERE name ILIKE ? OR name % ?
      ) AS matches
      ORDER BY (name ILIKE ?) DESC, sml DESC, length(name), name
      LIMIT ?}, $partial, $substring, $partial, $prefix, $limit
  )->arrays->flatten->to_array;
}

sub git_import ($self, $id, $data, $priority = PRIORITY_INCOMING) {
  my $pkg = $self->find($id);
  return $self->minion->enqueue(
    git_import => [$id, $data] => {
      priority => $priority,
      attempts => 5,
      notes    => {external_link => $pkg->{external_link}, package => $pkg->{name}, "pkg_$id" => 1}
    }
  );
}

sub obs_import ($self, $id, $data, $priority = PRIORITY_INCOMING) {
  my $pkg = $self->find($id);
  return $self->minion->enqueue(
    obs_import => [$id, $data] => {
      priority => $priority,
      attempts => 5,
      notes    => {external_link => $pkg->{external_link}, package => $pkg->{name}, "pkg_$id" => 1}
    }
  );
}

sub obsolete_duplicate_new ($self) {
  my $db = $self->pg->db;

  # Mark all duplicate new packages as obsolete (same external_link and name)
  $db->query(
    q{
      UPDATE bot_packages
      SET obsolete = true, state = 'obsolete'
      WHERE id IN (
        SELECT a.id FROM (
          SELECT id, ROW_NUMBER() OVER (PARTITION BY external_link, name ORDER BY id DESC) row_no
          FROM bot_packages
          WHERE state = 'new' AND external_link IS NOT NULL
        ) AS a
        WHERE row_no > 1
      );
    }
  );
}

sub obsolete_if_not_in_product ($self, $id) {
  my $db = $self->pg->db;
  return undef if $db->query('select 1 from bot_package_products where package = ? limit 1', $id)->array;

  # Only set the obsolete flag, never overwrite the state. The state is the audit
  # trail of the last real review decision (e.g. a lawyer's "unacceptable"); the
  # boolean flag is what everything else uses to tell that a record is retired.
  $db->query(q{update bot_packages set obsolete = true where id = ? and state in ('new', 'unacceptable')}, $id);

  return 1;
}

sub obsolete_old_packages ($self, $days_to_keep_orphaned, $days_to_keep_orphaned_duplicates) {
  my $db = $self->pg->db;

  # Mark duplicate old packages not in products as obsolete
  $db->query(
    "UPDATE bot_packages SET obsolete = true WHERE id IN (
       SELECT id FROM (
         SELECT id, imported FROM (
           SELECT id, imported, ROW_NUMBER() OVER (PARTITION BY name ORDER BY id DESC) AS row_no
           FROM bot_packages LEFT JOIN bot_package_products ON bot_package_products.package = bot_packages.id
           WHERE state != 'new' AND checksum IS NOT NULL AND obsolete = false AND bot_package_products.product IS NULL
         ) AS a
         WHERE row_no > 1
       ) AS b
       WHERE imported < NOW() - (INTERVAL '1 days' * ?)
     )", $days_to_keep_orphaned_duplicates
  );

  # Mark all old packages not in products as obsolete
  $db->query(
    "UPDATE bot_packages SET obsolete = true WHERE id IN (
       SELECT id
       FROM bot_packages LEFT JOIN bot_package_products ON bot_package_products.package = bot_packages.id
       WHERE state != 'new' AND obsolete != true AND checksum IS NOT NULL AND obsolete = false
         AND imported < NOW() - (INTERVAL '1 days' * ?)
         AND bot_package_products.product IS NULL
     )", $days_to_keep_orphaned
  );
}

# Request a reindex. Returns 'now' when the job was enqueued, 'later' when the package was busy and the
# request was recorded to be picked up once it is free, and undef when the package is not eligible at all
# (gone, obsolete, or never indexed). A request is never silently dropped: reviewers create patterns in
# batches, and every one of those has to reach the packages it affects even when they are mid-rebuild.
sub reindex ($self, $id, $priority = PRIORITY_INCOMING, @args) {
  my $minion = $self->minion;
  my $db     = $self->pg->db;

  # Make sure package exists and is eligible for reindexing
  my $pkg = $db->select(
    'bot_packages',
    ['id', 'processing_job'],
    {id => $id, indexed => {'!=' => undef}, '-not_bool' => 'obsolete'}
  )->hash;
  return undef unless $pkg;

  # Busy: either somebody already owns the package, or an import/unpack is queued or running - that chain
  # will index the package itself, and an orphan reindex would race the unpack and fail "is not unpacked
  # yet" once the unpack clears the field. Either way the request is remembered rather than dropped, and
  # the job that is currently running picks it up when it finishes (see request_reindex).
  my $busy
    = defined $pkg->{processing_job}
    || $minion->jobs(
    {tasks => ['obs_import', 'git_import', 'unpack'], states => ['inactive', 'active'], notes => ["pkg_$id"]})->total;
  if ($busy) {
    $self->request_reindex($id, $priority);
    return 'later';
  }

  $self->index($id, $priority, @args);

  return 'now';
}

# Remember that this package still owes somebody a rebuild, for whoever frees it up to act on. Concurrent
# requests coalesce into this one timestamp, so a batch of new patterns costs one rebuild, and the record
# outlives the process that made it: whoever hands the package back picks it up (see hand_back), and
# failing that (a package that is no longer eligible for a rebuild at all) the cleanup sweep does. What
# coalescing must not do is lose the most impatient of the requests, so the rebuild they share is the one
# the highest of them asked for.
sub request_reindex ($self, $id, $priority = PRIORITY_UPKEEP) {
  $self->pg->db->query(
    'UPDATE bot_packages
     SET reindex_requested = NOW(), reindex_priority = GREATEST(COALESCE(reindex_priority, 0), ?)
     WHERE id = ?', $priority, $id
  );
}

# Is a reindex waiting for this package to become free? Read by the report page, so a reviewer whose
# pattern landed while the package was rebuilding sees that another rebuild is still coming.
sub reindex_requested ($self, $id) { defined $self->reindex_request($id) ? 1 : 0 }

# The same question with the answer whoever acts on the request needs: the priority it was made at, or
# undef when there is no request at all. Requests predating the priority column count as upkeep.
sub reindex_request ($self, $id) {
  my $pkg
    = $self->pg->db->select('bot_packages', ['reindex_priority'], {id => $id, reindex_requested => {'!=' => undef}})
    ->hash;
  return undef unless $pkg;
  return $pkg->{reindex_priority} // PRIORITY_UPKEEP;
}

# Clear a pending reindex request. Always called *after* the follow-up has been enqueued, so a crash in
# between leaves the request standing and it is simply picked up again, rather than being lost.
sub clear_reindex_request ($self, $id) {
  $self->pg->db->query('UPDATE bot_packages SET reindex_requested = NULL, reindex_priority = NULL WHERE id = ?', $id);
}

sub reindex_all ($self) {
  my $ids = $self->pg->db->query('select id from bot_packages where obsolete is not true')->arrays->flatten->to_array;
  $self->reindex_package_ids($ids, PRIORITY_SWEEP);
}

sub reindex_matched_packages ($self, $pid, $priority = PRIORITY_UPKEEP) {

  # Every generation, not just the live one: a package whose in-flight build matched the pattern needs the
  # reindex too, and enqueuing one for a package that turns out not to need it only costs a little work
  my $packages = $self->pg->db->query('select distinct package from pattern_matches where pattern = ?', $pid);
  $self->reindex_package_ids([map { $_->{package} } $packages->hashes->each], $priority);
}

sub reindex_packages ($self, $name) {
  my $ids = $self->pg->db->select('bot_packages', 'id', {name => $name})->arrays->flatten->to_array;
  $self->reindex($_, PRIORITY_UPKEEP) for @$ids;
}

# The priority is the one the rebuilds will run at. Turning the list into jobs is left to the queue
# because it can be tens of thousands of packages long, and those helper jobs sit one band below the
# rebuilds they produce, so a package that is already being rebuilt is finished first.
sub reindex_package_ids ($self, $ids, $priority = PRIORITY_UPKEEP) {
  my $minion = $self->minion;
  $minion->enqueue('index_later', [$_], {priority => $priority - 1}) for @$ids;
}

sub remove_spdx_report ($self, $id) {
  my $dir = $self->pkg_checkout_dir($id);

  # Remove the current report and its processed variant, plus legacy reports left behind by older Cavil
  # versions (uncompressed JSON, and pre-3.0.1 non-JSON tag-value)
  $dir->child($_)->remove for qw(
    .report.spdx.json.gz .report.processed.spdx.json.gz
    .report.spdx.json    .report.processed.spdx.json
    .report.spdx         .report.processed.spdx
  );
}

sub requests_for ($self, $id) {
  return $self->pg->db->query('SELECT external_link FROM bot_requests WHERE package = ? ORDER BY id DESC', $id)
    ->arrays->flatten->to_array;
}

sub spdx_report_path ($self, $id) {
  return $self->pkg_checkout_dir($id)->child('.report.spdx.json.gz');
}

# Size of the file a download of the report actually produces, which is the uncompressed one - the report
# is stored gzipped and handed to the browser that way, but what lands on disk is the JSON. Gzip records
# that in the last four bytes of the file, so it costs a seek rather than a decompression.
sub spdx_report_size ($self, $id) {
  my $path = $self->spdx_report_path($id);
  return undef unless my $compressed = -s $path;

  # ISIZE is the uncompressed size modulo 2^32, so it is only the answer while the report cannot have been
  # bigger than that. JSON gzips by roughly ten to one, leaving this bound with room to spare; above it we
  # would rather say nothing than name a size that has silently wrapped
  return undef if $compressed > 256 * 1024 * 1024;

  open my $fh, '<:raw', $path or return undef;
  seek $fh, -4, 2 or return undef;
  read($fh, my $isize, 4) == 4 or return undef;
  return unpack 'V', $isize;
}

sub states ($self, $name) {
  return $self->pg->db->query(
    'select checkout_dir as checkout, state from bot_packages
     where name = ? order by created desc', $name
  )->hashes->to_array;
}

sub stats {
  my $self = shift;

  my $stats = $self->pg->db->query(
    "SELECT
       (SELECT COUNT(*) FROM bot_packages WHERE obsolete = false) AS active_packages,
       (SELECT COUNT(*) FROM bot_packages WHERE obsolete = false AND embargoed = true) AS embargoed_packages,
       (SELECT COUNT(*) FROM bot_packages WHERE obsolete = false AND state = 'unacceptable') AS rejected_packages,
       (SELECT COUNT(*) FROM bot_packages WHERE obsolete = false AND state = 'new') AS open_reviews,
      (SELECT COALESCE(SUM(unresolved_matches), 0) FROM bot_packages WHERE obsolete = false) AS unresolved_matches,
       overall_reviews.performed AS performed_reviews,
       overall_reviews.manual AS manual_reviews,
       overall_reviews.automated AS automated_reviews,
       monthly_reviews.performed AS monthly_performed_reviews,
       monthly_reviews.manual AS monthly_manual_reviews,
       monthly_reviews.automated AS monthly_automated_reviews,
       (SELECT COUNT(*) FROM package_components WHERE generation = 0) AS package_components,
       (SELECT COUNT(*) FROM snippets) AS total_snippets,
       (SELECT COUNT(*) FROM license_patterns) AS total_license_patterns
     FROM (
       SELECT COUNT(*) AS performed,
         COUNT(*) FILTER (WHERE reviewing_user IS NOT NULL) AS manual,
         COUNT(*) FILTER (WHERE reviewing_user IS NULL) AS automated
       FROM bot_packages
       WHERE reviewed IS NOT NULL
     ) overall_reviews,
     (
       SELECT COUNT(*) AS performed,
         COUNT(*) FILTER (WHERE reviewing_user IS NOT NULL) AS manual,
         COUNT(*) FILTER (WHERE reviewing_user IS NULL) AS automated
       FROM bot_packages
       WHERE reviewed >= now() - INTERVAL '1 month'
     ) monthly_reviews"
  )->hash;

  $stats->{imported_activity} = $self->pg->db->query(
    "SELECT EXTRACT(EPOCH FROM bucket) AS bucket,
       TO_CHAR(bucket, 'HH24:00') AS label,
       COUNT(bot_packages.id) AS count
     FROM GENERATE_SERIES(
       DATE_TRUNC('hour', NOW()) - INTERVAL '23 hours',
       DATE_TRUNC('hour', NOW()),
       INTERVAL '1 hour'
     ) bucket
     LEFT JOIN bot_packages ON imported >= bucket AND imported < bucket + INTERVAL '1 hour'
     GROUP BY bucket
     ORDER BY bucket"
  )->hashes->to_array;

  $stats->{weekly_imported_activity} = $self->pg->db->query(
    "SELECT EXTRACT(EPOCH FROM bucket) AS bucket,
       TO_CHAR(bucket, 'Dy') AS label,
       COUNT(bot_packages.id) AS count
     FROM GENERATE_SERIES(
       DATE_TRUNC('day', NOW()) - INTERVAL '6 days',
       DATE_TRUNC('day', NOW()),
       INTERVAL '1 day'
     ) bucket
     LEFT JOIN bot_packages ON imported >= bucket AND imported < bucket + INTERVAL '1 day'
     GROUP BY bucket
     ORDER BY bucket"
  )->hashes->to_array;

  return $stats;
}

sub unpack ($self, @args) { $self->_enqueue('unpack', @args) }

sub unpacked ($self, $id) {
  $self->pg->db->update(
    'bot_packages',
    {unpacked => \'now()', unpacked_files => undef, unpacked_size => undef},
    {id       => $id}
  );
}

sub update ($self, $pkg) {
  my %updates = map { exists $pkg->{$_} ? ($_ => $pkg->{$_}) : () } (
    qw(created checksum priority state obsolete result notice diff_report reviewed reviewing_user external_link),
    qw(embargoed ai_assisted)
  );
  $updates{reviewed} = \'now()' if $pkg->{review_timestamp};
  return $self->pg->db->update('bot_packages', \%updates, {id => $pkg->{id}});
}

sub update_file_stats ($self, $id, $stats) {
  my $db = $self->pg->db;
  $db->update('bot_packages', {unpacked_files => $stats->{files}, unpacked_size => $stats->{size}}, {id => $id});
}

sub matched_files ($self, $id) {
  return $self->pg->db->query('SELECT filename FROM matched_files WHERE package = ? AND generation = 0', $id)
    ->arrays->flatten->to_array;
}

sub _check_field ($self, $field, $id) {
  return undef unless my $hash = $self->pg->db->select('bot_packages', [$field], {id => $id})->hash;
  return !!$hash->{$field};
}

sub _enqueue ($self, $task, $id, $priority = PRIORITY_INCOMING, $parents = [], $delay = 0) {
  my $minion = $self->minion;

  # Deduplicate jobs for same package. A job that is already waiting does the same work, so a second one
  # is not enqueued - but a request that outranks it moves it up the queue, or a reviewer clicking Reindex
  # would inherit the place of the weekly sweep that got there first. Minion has no way to change a
  # priority other than a retry, so the job shows up in the admin UI as retried once.
  if (my $queued = $minion->jobs({tasks => [$task], states => ['inactive'], notes => ["pkg_$id"]})->next) {
    if ($queued->{priority} < $priority && (my $job = $minion->job($queued->{id}))) {
      $job->retry({priority => $priority});
    }
    return undef;
  }

  my $pkg = $self->find($id);
  return $minion->enqueue(
    $task => [$id] => {
      delay    => $delay,
      parents  => $parents,
      priority => $priority,
      notes    => {external_link => $pkg->{external_link}, package => $pkg->{name}, "pkg_$id" => 1}
    }
  );
}

1;
