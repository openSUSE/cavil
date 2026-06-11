# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later
package Cavil::Model::Notes;
use Mojo::Base -base, -signatures;
use Exporter 'import';

our @EXPORT_OK = qw(NOTE_BODY_MAX_LENGTH);
use constant NOTE_BODY_MAX_LENGTH => 65535;

has 'pg';

# Notes are shared across all bot_packages rows that share a name. The
# originating package id (`package`) is kept as a "permalink" target so the UI
# can show "originally added on review #N" — but it can become NULL if that
# package row is later removed, and the note still belongs to the package
# name.

sub add ($self, $package_id, $package_name, $author_id, $body, $lawyer_only, $ai_assisted = 0) {
  my $row = $self->pg->db->insert(
    'package_notes',
    {
      package      => $package_id,
      package_name => $package_name,
      author       => $author_id,
      ai_assisted  => $ai_assisted ? 1 : 0,
      body         => $body,
      lawyer_only  => $lawyer_only ? 1 : 0
    },
    {returning => 'id'}
  )->hash;
  return $self->find($row->{id});
}

sub find ($self, $id) {
  my $rows = $self->_query('AND c.id = ?', [$id]);
  return $rows->[0];
}

sub list ($self, $package_name, %opts) {
  my $limit = $opts{limit} // 20;
  $limit = 1   if $limit < 1;
  $limit = 100 if $limit > 100;

  my @sql  = ('AND c.package_name = ?');
  my @args = ($package_name);

  push @sql, 'AND c.lawyer_only = false' unless $opts{include_lawyer_only};
  if (defined $opts{before_id}) {
    push @sql,  'AND c.id < ?';
    push @args, $opts{before_id};
  }

  my $rows = $self->_query(join(' ', @sql), \@args, 'ORDER BY c.id DESC LIMIT ?', [$limit + 1]);

  my $has_more = @$rows > $limit ? 1 : 0;
  splice @$rows, $limit if $has_more;
  return {notes => $rows, has_more => $has_more};
}

sub recent ($self, %opts) {
  my $limit = $opts{limit} // 20;
  $limit = 1   if $limit < 1;
  $limit = 100 if $limit > 100;

  my @sql;
  my @args;

  push @sql, 'AND c.lawyer_only = false' unless $opts{include_lawyer_only};
  if (defined $opts{before_id}) {
    push @sql,  'AND c.id < ?';
    push @args, $opts{before_id};
  }

  my $rows = $self->_query(join(' ', @sql), \@args, 'ORDER BY c.id DESC LIMIT ?', [$limit + 1]);

  my $has_more = @$rows > $limit ? 1 : 0;
  splice @$rows, $limit if $has_more;
  return {notes => $rows, has_more => $has_more};
}

sub review_context_for_report ($self, $package_name, $current_author_id, %opts) {
  my $where = {'package_notes.package_name' => $package_name};
  $where->{'package_notes.lawyer_only'} = 0 unless $opts{include_lawyer_only};
  if (defined $current_author_id) {
    $where->{-or}
      = [{'package_notes.author' => $current_author_id}, \q{bot_users.roles && ARRAY['admin', 'lawyer']::text[]}];
  }
  else {
    $where->{-bool} = \q{bot_users.roles && ARRAY['admin', 'lawyer']::text[]};
  }

  return $self->pg->db->select(
    ['package_notes', ['bot_users', id => 'author'], [-left => 'bot_packages', id => 'package']],
    [
      'package_notes.id',
      'package_notes.body',
      'package_notes.lawyer_only',
      'package_notes.ai_assisted',
      \'package_notes.package AS package_id',
      'package_notes.package_name',
      \'package_notes.author AS author_id',
      \'bot_users.login AS author_login',
      \'bot_users.fullname AS author_fullname',
      \'bot_users.roles AS author_roles',
      \'EXTRACT(EPOCH FROM package_notes.created) AS created_epoch',
      \'EXTRACT(EPOCH FROM package_notes.edited)  AS edited_epoch',
      \'bot_packages.state AS package_state',
      \'bot_packages.external_link AS package_external_link'
    ],
    $where,
    {order_by => {-desc => 'package_notes.id'}}
  )->hashes->to_array;
}

sub counts ($self, $package_name) {
  return $self->pg->db->query(
    'SELECT COUNT(*)::int AS total,
            COUNT(*) FILTER (WHERE lawyer_only = true)::int AS lawyer_only
       FROM package_notes WHERE package_name = ?', $package_name
  )->hash;
}

sub remove ($self, $id) {
  return $self->pg->db->query('DELETE FROM package_notes WHERE id = ? RETURNING id', $id)->rows;
}

sub edit ($self, $id, $body) {
  return undef
    unless $self->pg->db->query('UPDATE package_notes SET body = ?, edited = now() WHERE id = ? RETURNING id', $body,
    $id)->rows;
  return $self->find($id);
}

sub _query ($self, $extra_sql, $extra_args, $tail_sql = '', $tail_args = []) {
  my $sql = qq{
    SELECT c.id, c.body, c.lawyer_only, c.ai_assisted, c.package AS package_id, c.package_name,
           c.author AS author_id, u.login AS author_login, u.fullname AS author_fullname,
           u.roles AS author_roles,
           EXTRACT(EPOCH FROM c.created) AS created_epoch,
           EXTRACT(EPOCH FROM c.edited)  AS edited_epoch,
           p.state AS package_state, p.external_link AS package_external_link
      FROM package_notes c
      JOIN bot_users u ON c.author = u.id
      LEFT JOIN bot_packages p ON c.package = p.id
     WHERE 1 = 1 $extra_sql $tail_sql
  };
  return $self->pg->db->query($sql, @$extra_args, @$tail_args)->hashes->to_array;
}

1;
