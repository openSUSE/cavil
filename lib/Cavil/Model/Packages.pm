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
use Mojo::Base -base;

use Mojo::File 'path';
use Mojo::Util 'dumper';

has [qw(checkout_dir minion pg)];

sub add {
  my ($self, %args) = @_;

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

sub actions {
  my ($self, $link, $id) = @_;

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

sub all { shift->pg->db->select('bot_packages')->hashes }

sub analyze {
  my ($self, $id, $priority, $parents) = (shift, shift, shift // 9, shift || []);
  return $self->_enqueue('analyze', $id, $priority, $parents);
}

sub find {
  my ($self, $id) = @_;
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

sub find_by_name {
  my ($self, $name) = @_;
  return $self->pg->db->select(
    ['bot_packages', [-left => 'bot_users', id => 'reviewing_user']],
    [
      'bot_packages.*',
      \'extract(epoch from bot_packages.created) as created_epoch',
      \'extract(epoch from bot_packages.reviewed) as reviewed_epoch',
      \'bot_users.login as login'
    ],
    {name => $name}
  )->hashes;
}

sub find_by_name_and_md5 {
  my ($self, $pkg, $md5) = @_;
  return $self->pg->db->select('bot_packages', '*', {name => $pkg, checkout_dir => $md5})->hash;
}

sub history {
  my ($self, $name, $checksum, $id) = @_;
  return $self->pg->db->query(
    "select p.id, external_link, result, state, login,
       extract(epoch from created) as created_epoch, obsolete
     from bot_packages p left join bot_users u on p.reviewing_user = u.id
     where name = ? and checksum = ? and p.id != ? and state != 'new'
     order by p.id desc", $name, $checksum, $id
  )->hashes->to_array;
}

sub ignore_line {
  my ($self, $package, $hash) = @_;

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

sub imported {
  my ($self, $id) = @_;
  $self->pg->db->update('bot_packages', {imported => \'now()'}, {id => $id});
}

sub index { shift->_enqueue('index', @_) }

sub indexed {
  my ($self, $id) = @_;
  $self->pg->db->update('bot_packages', {indexed => \'now()'}, {id => $id});
}

sub is_imported { shift->_check_timestamp('imported', @_) }
sub is_indexed  { shift->_check_timestamp('indexed',  @_) }
sub is_unpacked { shift->_check_timestamp('unpacked', @_) }

sub list {
  my ($self, $state, $pkg) = @_;

  # Do not show obsolete packages
  my %where;
  $where{'-not_bool'} = 'obsolete';

  $where{state} = $state if $state;
  $where{name}  = $pkg   if $pkg;

  return $self->pg->db->select(['bot_packages', [-left => 'bot_users', id => 'reviewing_user']],
    [\'bot_packages.*', \'extract(epoch from bot_packages.created) as created_epoch', \'bot_users.login'], \%where)
    ->hashes->to_array;
}

sub mark_matched_for_reindex {
  my ($self, $pid, $priority) = (shift, shift, shift // 0);
  $self->minion->enqueue(reindex_matched_later => [$pid] => {priority => $priority});
}

sub name_suggestions {
  my ($self, $partial) = @_;
  my $like = '%' . $partial . '%';
  return $self->pg->db->select(
    'bot_packages', [\'distinct(name)'],
    {-and  => [{name => \[' ilike ?', $like]}, {name => {'!=' => $partial}}]},
    {limit => 100}
  )->arrays->flatten->to_array;
}

sub obs_import {
  my ($self, $id, $data, $priority) = (shift, shift, shift, shift // 5);
  my $pkg = $self->find($id);
  return $self->minion->enqueue(obs_import => [$id, $data] =>
      {priority => $priority, notes => {external_link => $pkg->{external_link}, package => $pkg->{name}}});
}

sub recent {
  my $self = shift;
  return $self->pg->db->query(
    'select p.*, u.login, extract(epoch from p.created) as created_epoch,
       extract(epoch from p.reviewed) as reviewed_epoch
     from bot_packages p
       left join bot_users u on p.reviewing_user = u.id
     where reviewed is not null
     order by reviewed desc
     limit 100'
  )->hashes->to_array;
}

sub reindex {
  my ($self, $id, $priority) = @_;

  # Protect from race conditions (even before creating a background job)
  return undef unless $self->minion->lock("processing_pkg_$id", 0);

  # Make sure package exists and is eligible for reindexing
  return undef
    unless $self->pg->db->select('bot_packages', 'id',
    {id => $id, indexed => {'!=' => undef}, '-not_bool' => 'obsolete'})->hash;

  $self->index($id, $priority);

  return 1;
}

sub reindex_all {
  my $self = shift;
  my $ids  = $self->pg->db->query('select id from bot_packages where obsolete is not true')->arrays->flatten->to_array;
  my $minion = $self->minion;
  $minion->enqueue(index_later => [$_] => {priority => 0}) for @$ids;
}

sub reindex_matched_packages {
  my ($self, $pid, $priority) = (shift, shift, shift // 0);

  my $package = $self->pg->db->query('select distinct package from pattern_matches where pattern = ?', $pid);
  my $minion  = $self->minion;
  for my $row ($package->hashes->each) {
    $minion->enqueue('index_later', [$row->{package}], {priority => $priority});
  }
}

sub states {
  my ($self, $name) = @_;
  return $self->pg->db->query(
    'select checkout_dir as checkout, state from bot_packages
     where name = ? order by created desc', $name
  )->hashes->to_array;
}

sub unpack { shift->_enqueue('unpack', @_) }

sub unpacked {
  my ($self, $id) = @_;
  $self->pg->db->update('bot_packages', {unpacked => \'now()'}, {id => $id});
}

sub update {
  my ($self, $pkg) = @_;
  my %updates = map { exists $pkg->{$_} ? ($_ => $pkg->{$_}) : () }
    (qw(created checksum priority state obsolete result), qw(reviewing_user external_link));
  $updates{reviewed} = \'now()' if $pkg->{review_timestamp};
  return $self->pg->db->update('bot_packages', \%updates, {id => $pkg->{id}});
}

sub keyword_files {
  my ($self, $id) = @_;
  return $self->pg->db->select('matched_files', 'id,filename', {package => $id})->hashes;
}

sub _check_timestamp {
  my ($self, $field, $id) = @_;
  return undef unless my $hash = $self->pg->db->select('bot_packages', [$field], {id => $id})->hash;
  return !!$hash->{$field};
}

sub _enqueue {
  my ($self, $task, $id, $priority, $parents, $delay) = (shift, shift, shift, shift // 5, shift || [], shift // 0);
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
