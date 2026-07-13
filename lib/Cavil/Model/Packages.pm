# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package Cavil::Model::Packages;
use Mojo::Base -base, -signatures;

use Cavil::Util qw(paginate);
use Mojo::File  qw(path);
use Mojo::Util  qw(dumper);
use Text::Glob  qw(glob_to_regex);

has [qw(checkout_dir log minion pg)];

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

sub analyze ($self, $id, $priority = 9, $parents = []) {
  return $self->_enqueue('analyze', $id, $priority, $parents);
}

sub cleanup ($self, $id) {
  my $db     = $self->pg->db;
  my $minion = $self->minion;
  my $log    = $self->log;

  my $tx  = $db->begin;
  my $pkg = $db->select('bot_packages', ['name', 'checkout_dir', 'obsolete'], {id => $id}, {for => 'update'})->hash;
  return if !$pkg || !$pkg->{obsolete} || !(my $guard = $minion->guard("processing_pkg_$id", 172800));

  my $dir = path($self->checkout_dir, $pkg->{name}, $pkg->{checkout_dir});
  if (-d $dir) {
    $log->info("[$id] Removing checkout $pkg->{name}/$pkg->{checkout_dir}");
    $dir->remove_tree;
  }
  $db->query('UPDATE bot_packages SET cleaned = NOW() WHERE id = ?', $id);

  $db->query('delete from bot_reports where package = ?',        $id);
  $db->query('delete from emails where package = ?',             $id);
  $db->query('delete from urls where package = ?',               $id);
  $db->query('delete from package_components where package = ?', $id);
  $db->query('delete from pattern_matches where package = ?',    $id);
  $db->query('delete from matched_files where package = ?',      $id);
  $tx->commit;
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

  my $files = $self->pg->db->select('matched_files', ['filename'], {package => $id});
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

sub flags ($self, $id) {

  # Only include flags that have a field in the bot_packages table
  my @flags = qw(patent trademark export_restricted cla eula);
  my $flags = {map { $_ => 0 } @flags};

  my $results = $self->pg->db->query(
    qq{
      SELECT patent, trademark, export_restricted, cla, eula
      FROM pattern_matches pm JOIN license_patterns lp ON pm.pattern = lp.id
      WHERE pm.package = ? AND pm.ignored = false
        AND (lp.patent = true OR lp.trademark = true OR lp.export_restricted = true
             OR lp.cla = true OR lp.eula = true)
    }, $id
  )->hashes->to_array;
  for my $result (@$results) {
    for my $flag (@flags) {
      $flags->{$flag} = 1 if $result->{$flag};
    }
  }

  return $flags;
}

sub generate_spdx_report ($self, $id, $options = {}) {
  return if $self->has_spdx_report($id);

  my $minion = $self->minion;
  $minion->enqueue('spdx_report' => [$id] => {priority => 6, notes => {"pkg_$id" => 1}, %$options})
    if $minion->lock("spdx_$id", 172800);
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

  # A new ignored_lines row does not change file contents or pattern definitions, so a full reindex is unnecessary
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
  $self->analyze($_, 9) for @$ids;
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

sub is_imported ($self, @args) { $self->_check_field('imported', @args) }
sub is_indexed  ($self, @args) { $self->_check_field('indexed',  @args) }
sub is_obsolete ($self, @args) { $self->_check_field('obsolete', @args) }
sub is_unpacked ($self, @args) { $self->_check_field('unpacked', @args) }

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

  my $packages;
  if ($options->{pattern}) {
    $packages = $db->query('SELECT DISTINCT(package) FROM pattern_matches WHERE pattern = ?', $options->{pattern})
      ->arrays->flatten;
  }

  if ($options->{ignore}) {
    $packages = $db->query('SELECT DISTINCT(package) FROM pattern_matches WHERE ignored_line = ?', $options->{ignore})
      ->arrays->flatten;
  }

  # Find every package that ships a given vendored component (by name or purl, case-insensitive
  # substring - so "lodash" matches all versions and "pkg:npm/lodash@4.17.20" pins one). The term is
  # user input, so it is quoted.
  if (length($options->{component} // '') > 0) {
    my $like = $db->dbh->quote('%' . $options->{component} . '%');
    $packages
      = $db->query("SELECT DISTINCT(package) FROM package_components WHERE purl ILIKE $like OR name ILIKE $like")
      ->arrays->flatten;
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
       WHERE package = ANY (?) AND (purl ILIKE ? OR name ILIKE ?)
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
       WHERE p.embargoed = FALSE AND p.obsolete = FALSE
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

sub mark_matched_for_reindex ($self, $pid, $priority = 0) {
  $self->minion->enqueue(reindex_matched_later => [$pid] => {priority => $priority});
}

sub need_cleanup ($self) {
  return $self->pg->db->query('SELECT id FROM bot_packages WHERE obsolete IS TRUE AND cleaned IS NULL ORDER BY ID')
    ->arrays->flatten->to_array;
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

sub git_import ($self, $id, $data, $priority = 5) {
  my $pkg = $self->find($id);
  return $self->minion->enqueue(
    git_import => [$id, $data] => {
      priority => $priority,
      attempts => 5,
      notes    => {external_link => $pkg->{external_link}, package => $pkg->{name}, "pkg_$id" => 1}
    }
  );
}

sub obs_import ($self, $id, $data, $priority = 5) {
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
  $db->query(
    q{update bot_packages set state = 'obsolete', obsolete = true where id = ? and state in ('new', 'unacceptable')},
    $id);

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

sub reindex ($self, $id, @args) {
  my $minion = $self->minion;

  # Protect from race conditions (even before creating a background job)
  return undef unless $minion->lock("processing_pkg_$id", 0);

  # Skip if an import or unpack is already queued or running - that chain will
  # index the package itself, and an orphan reindex would race the unpack and
  # fail "is not unpacked yet" once the unpack clears the field
  return undef
    if $minion->jobs(
    {tasks => ['obs_import', 'git_import', 'unpack'], states => ['inactive', 'active'], notes => ["pkg_$id"]})->total;

  # Make sure package exists and is eligible for reindexing
  return undef
    unless $self->pg->db->select('bot_packages', 'id',
    {id => $id, indexed => {'!=' => undef}, '-not_bool' => 'obsolete'})->hash;

  $self->index($id, @args);

  return 1;
}

sub reindex_all ($self) {
  my $ids = $self->pg->db->query('select id from bot_packages where obsolete is not true')->arrays->flatten->to_array;
  my $minion = $self->minion;
  $minion->enqueue(index_later => [$_] => {priority => 0}) for @$ids;
}

sub reindex_matched_packages ($self, $pid, $priority = 0) {
  my $package = $self->pg->db->query('select distinct package from pattern_matches where pattern = ?', $pid);
  my $minion  = $self->minion;
  for my $row ($package->hashes->each) {
    $minion->enqueue('index_later', [$row->{package}], {priority => $priority});
  }
}

sub reindex_packages ($self, $name) {
  my $ids = $self->pg->db->select('bot_packages', 'id', {name => $name})->arrays->flatten->to_array;
  $self->reindex($_, 3) for @$ids;
}

sub reindex_package_ids ($self, $ids, $priority = 0) {
  my $minion = $self->minion;
  $minion->enqueue('index_later', [$_], {priority => $priority}) for @$ids;
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
       (SELECT COUNT(*) FROM package_components) AS package_components,
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
  return $self->pg->db->query('SELECT filename FROM matched_files WHERE package = ?', $id)->arrays->flatten->to_array;
}

sub _check_field ($self, $field, $id) {
  return undef unless my $hash = $self->pg->db->select('bot_packages', [$field], {id => $id})->hash;
  return !!$hash->{$field};
}

sub _enqueue ($self, $task, $id, $priority = 5, $parents = [], $delay = 0) {
  my $minion = $self->minion;

  # Deduplicate jobs for same package
  return undef if $self->minion->jobs({tasks => [$task], states => ['inactive'], notes => ["pkg_$id"]})->total;

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
