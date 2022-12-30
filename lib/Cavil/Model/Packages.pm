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

package Cavil::Model::Packages;
use Mojo::Base -base, -signatures;

use Cavil::Util qw(paginate);
use Mojo::File 'path';
use Mojo::Util 'dumper';

has [qw(checkout_dir minion pg)];

sub add ($self, %args) {

  my $db = $self->pg->db;
  my $source
    = {api_url => $args{api_url}, project => $args{project}, package => $args{package}, srcmd5 => $args{srcmd5}};
  my $source_id = $db->insert('bot_sources', $source, {returning => 'id'})->hash->{id};

  my $pkg = {
    name            => $args{name},
    checkout_dir    => $args{checkout_dir},
    created         => $args{created} || scalar localtime,
    source          => $source_id,
    requesting_user => $args{requesting_user},
    priority        => $args{priority},
    state           => 'new'
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

sub find ($self, $id) {
  return $self->pg->db->select(
    ['bot_packages', [-left => 'bot_users', id => 'reviewing_user']],
    [
      'bot_packages.*',
      \'extract(epoch from bot_packages.created) as created_epoch',
      \'extract(epoch from bot_packages.reviewed) as reviewed_epoch',
      \'bot_users.login as login'
    ],
    {'bot_packages.id' => $id}
  )->hash;
}

sub find_by_name_and_md5 ($self, $pkg, $md5) {
  return $self->pg->db->select('bot_packages', '*', {name => $pkg, checkout_dir => $md5})->hash;
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

sub ignore_line ($self, $package, $hash) {

  my $db = $self->pg->db;
  $db->query(
    'insert into ignored_lines (hash, packname) values (?, ?)
     on conflict do nothing', $hash, $package
  );

  # as it affects all packages with the name, we need to update all reports
  my $ids = $db->select('bot_packages', [qw(id checksum)], {name => $package});
  while (my $pkg = $ids->hash) {
    $self->analyze($pkg->{id}) if $pkg->{checksum};
  }
}

sub imported ($self, $id) {
  $self->pg->db->update('bot_packages', {imported => \'now()'}, {id => $id});
}

sub index ($self, @args) { $self->_enqueue('index', @args) }

sub indexed ($self, $id) {
  $self->pg->db->update('bot_packages', {indexed => \'now()'}, {id => $id});
}

sub is_imported ($self, @args) { $self->_check_timestamp('imported', @args) }
sub is_indexed  ($self, @args) { $self->_check_timestamp('indexed',  @args) }
sub is_unpacked ($self, @args) { $self->_check_timestamp('unpacked', @args) }

sub paginate_open_reviews ($self, $options) {
  my $db = $self->pg->db;

  my $search = '';
  if (length($options->{search}) > 0) {
    my $quoted = $db->dbh->quote("\%$options->{search}\%");
    $search = "AND (checksum ILIKE $quoted OR external_link ILIKE $quoted OR name ILIKE $quoted)";
  }

  my $progress = '';
  if ($options->{in_progress} eq 'true') {
    $progress = 'AND (unpacked IS NULL OR indexed IS NULL)';
  }

  my $results = $db->query(
    qq{
      SELECT id, name, EXTRACT(EPOCH FROM created) as created_epoch, EXTRACT(EPOCH FROM imported) as imported_epoch,
        EXTRACT(EPOCH FROM unpacked) as unpacked_epoch, EXTRACT(EPOCH FROM indexed) as indexed_epoch, external_link,
        priority, state, checksum, COUNT(*) OVER() AS total
      FROM bot_packages
      WHERE state = 'new' AND obsolete = FALSE $search $progress
      ORDER BY priority DESC, external_link, created DESC, name
      LIMIT ? OFFSET ?
    }, $options->{limit}, $options->{offset}
  )->hashes->to_array;

  return paginate($results, $options);
}

sub paginate_product_reviews ($self, $name, $options) {
  my $db = $self->pg->db;

  return paginate([], $options) unless my $product = $db->select('bot_products', 'id', {name => $name})->hash;

  my $search = '';
  if (length($options->{search}) > 0) {
    my $quoted = $db->dbh->quote("\%$options->{search}\%");
    $search = "AND (checksum ILIKE $quoted OR state::text ILIKE $quoted OR name ILIKE $quoted)";
  }

  my $results = $db->query(
    qq{
      SELECT bot_packages.name, bot_packages.id, EXTRACT(EPOCH FROM imported) as imported_epoch,
        EXTRACT(EPOCH FROM unpacked) as unpacked_epoch, EXTRACT(EPOCH FROM indexed) as indexed_epoch, state,
        checksum, COUNT(*) OVER() AS total
      FROM bot_package_products JOIN bot_packages ON (bot_packages.id = bot_package_products.package)
      WHERE bot_package_products.product = ? $search
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

  my $results = $db->query(
    qq{
      SELECT p.id, p.name, u.login, p.result,  EXTRACT(EPOCH FROM p.created) AS created_epoch,
        EXTRACT(EPOCH FROM p.reviewed) AS reviewed_epoch, EXTRACT(EPOCH FROM p.imported) as imported_epoch,
        EXTRACT(EPOCH FROM p.unpacked) as unpacked_epoch, EXTRACT(EPOCH FROM p.indexed) as indexed_epoch,
        external_link, priority, state, checksum, COUNT(*) OVER() AS total
       FROM bot_packages p
         LEFT JOIN bot_users u ON p.reviewing_user = u.id
       WHERE reviewed IS NOT NULL AND reviewed > NOW() - INTERVAL '90 DAYS' $search $user
       ORDER BY reviewed DESC
       LIMIT ? OFFSET ?
    }, $options->{limit}, $options->{offset}
  )->hashes->to_array;

  return paginate($results, $options);
}

sub paginate_review_search ($self, $name, $options) {
  my $db = $self->pg->db;

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

  my $results = $db->query(
    qq{
      SELECT p.id AS id, state, checksum, p.result AS comment, EXTRACT(EPOCH FROM p.created) AS created_epoch,
        EXTRACT(EPOCH FROM p.imported) AS imported_epoch, EXTRACT(EPOCH FROM p.unpacked) AS unpacked_epoch,
        EXTRACT(EPOCH FROM p.indexed) AS indexed_epoch,
        u.login AS login, COUNT(*) OVER() AS total
      FROM bot_packages p LEFT JOIN bot_users u ON p.reviewing_user = u.id
      WHERE name = ? $search
      ORDER BY id DESC
      LIMIT ? OFFSET ?
    }, $name, $options->{limit}, $options->{offset}
  )->hashes->to_array;

  return paginate($results, $options);
}

sub mark_matched_for_reindex ($self, $pid, $priority = 0) {
  $self->minion->enqueue(reindex_matched_later => [$pid] => {priority => $priority});
}

sub name_suggestions ($self, $partial) {
  my $like = '%' . $partial . '%';
  return $self->pg->db->select(
    'bot_packages', [\'distinct(name)'],
    {-and  => [{name => \[' ilike ?', $like]}, {name => {'!=' => $partial}}]},
    {limit => 100}
  )->arrays->flatten->to_array;
}

sub obs_import ($self, $id, $data, $priority = 5) {
  my $pkg = $self->find($id);
  return $self->minion->enqueue(obs_import => [$id, $data] =>
      {priority => $priority, notes => {external_link => $pkg->{external_link}, package => $pkg->{name}}});
}

sub obsolete_if_not_in_product ($self, $id) {
  my $db = $self->pg->db;
  return undef if $db->query('select 1 from bot_package_products where package = ? limit 1', $id)->array;
  $db->query(
    q{update bot_packages set state = 'obsolete', obsolete = true where id = ? and state in ('new', 'unacceptable')},
    $id);

  return 1;
}

sub reindex ($self, $id, @args) {

  # Protect from race conditions (even before creating a background job)
  return undef unless $self->minion->lock("processing_pkg_$id", 0);

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

sub states ($self, $name) {
  return $self->pg->db->query(
    'select checkout_dir as checkout, state from bot_packages
     where name = ? order by created desc', $name
  )->hashes->to_array;
}

sub unpack ($self, @args) { $self->_enqueue('unpack', @args) }

sub unpacked ($self, $id) {
  $self->pg->db->update('bot_packages', {unpacked => \'now()'}, {id => $id});
}

sub update ($self, $pkg) {
  my %updates = map { exists $pkg->{$_} ? ($_ => $pkg->{$_}) : () }
    (qw(created checksum priority state obsolete result), qw(reviewing_user external_link));
  $updates{reviewed} = \'now()' if $pkg->{review_timestamp};
  return $self->pg->db->update('bot_packages', \%updates, {id => $pkg->{id}});
}

sub keyword_files ($self, $id) {
  return $self->pg->db->select('matched_files', 'id,filename', {package => $id})->hashes;
}

sub _check_timestamp ($self, $field, $id) {
  return undef unless my $hash = $self->pg->db->select('bot_packages', [$field], {id => $id})->hash;
  return !!$hash->{$field};
}

sub _enqueue ($self, $task, $id, $priority = 5, $parents = [], $delay = 0) {
  my $pkg = $self->find($id);
  return $self->minion->enqueue(
    $task => [$id] => {
      delay    => $delay,
      parents  => $parents,
      priority => $priority,
      notes    => {external_link => $pkg->{external_link}, package => $pkg->{name}, "pkg_$id" => 1}
    }
  );
}

1;
