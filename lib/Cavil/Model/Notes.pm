# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package Cavil::Model::Notes;
use Mojo::Base -base, -signatures;
use Cavil::Util qw(paginate);
use Exporter 'import';

our @EXPORT_OK = qw(NOTE_BODY_MAX_LENGTH);
use constant NOTE_BODY_MAX_LENGTH => 65535;

has 'pg';

# Notes belong to a package name; the nullable package id is only a permalink.
# Pinned notes apply to every review and stay outside keyset pagination.

sub add ($self, $package_id, $package_name, $author_id, $body, $lawyer_only, $ai_assisted = 0, $tags = undef) {
  my $row = $self->pg->db->insert(
    'package_notes',
    {
      package      => $package_id,
      package_name => $package_name,
      author       => $author_id,
      ai_assisted  => $ai_assisted ? 1 : 0,
      body         => $body,
      lawyer_only  => $lawyer_only ? 1 : 0,
      tags         => $tags // []
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

  push @sql, 'AND c.pinned = false' if $opts{exclude_pinned};

  if (defined $opts{before_id}) {
    push @sql,  'AND c.id < ?';
    push @args, $opts{before_id};
  }

  if ($opts{relevant_only}) {
    if (defined $opts{checksum}) {
      push @sql, 'AND (c.pinned = true OR c.package = ? OR p.checksum = ?)';
      push @args, $opts{package_id}, $opts{checksum};
    }
    else {
      push @sql,  'AND (c.pinned = true OR c.package = ?)';
      push @args, $opts{package_id};
    }
  }

  my $rows = $self->_query(join(' ', @sql), \@args, 'ORDER BY c.id DESC LIMIT ?', [$limit + 1]);

  my $has_more = @$rows > $limit ? 1 : 0;
  splice @$rows, $limit if $has_more;
  return {notes => $rows, has_more => $has_more};
}

# A separate query prevents pinned rows from crossing keyset cursors.
sub pinned_for_package ($self, $package_name, %opts) {
  my @sql  = ('AND c.package_name = ?', 'AND c.pinned = true');
  my @args = ($package_name);
  push @sql, 'AND c.lawyer_only = false' unless $opts{include_lawyer_only};
  return $self->_query(join(' ', @sql), \@args, 'ORDER BY c.id DESC');
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
  if (defined $opts{tags} && @{$opts{tags}}) {
    push @sql,  'AND c.tags @> ?::text[]';
    push @args, $opts{tags};
  }

  my $rows = $self->_query(join(' ', @sql), \@args, 'ORDER BY c.id DESC LIMIT ?', [$limit + 1]);

  my $has_more = @$rows > $limit ? 1 : 0;
  splice @$rows, $limit if $has_more;
  return {notes => $rows, has_more => $has_more};
}

sub all_tags ($self, %opts) {
  my $where = $opts{include_lawyer_only} ? '' : 'WHERE lawyer_only = false';
  return $self->pg->db->query(
    qq{
    SELECT unnest(tags) AS tag, COUNT(*)::int AS count
      FROM package_notes
      $where
     GROUP BY tag
     ORDER BY count DESC, tag
  }
  )->hashes->to_array;
}

sub paginate_for_package ($self, $package_name, %opts) {
  my $limit  = $opts{limit}  // 20;
  my $offset = $opts{offset} // 0;

  my @sql  = ('AND c.package_name = ?');
  my @args = ($package_name);

  push @sql, 'AND c.lawyer_only = false' unless $opts{include_lawyer_only};
  if (defined $opts{tags} && @{$opts{tags}}) {
    push @sql,  'AND c.tags @> ?::text[]';
    push @args, $opts{tags};
  }
  if ($opts{relevant_only}) {
    if (defined $opts{checksum}) {
      push @sql, 'AND (c.pinned = true OR c.package = ? OR p.checksum = ?)';
      push @args, $opts{package_id}, $opts{checksum};
    }
    else {
      push @sql,  'AND (c.pinned = true OR c.package = ?)';
      push @args, $opts{package_id};
    }
  }

  # Offset pagination, so unlike list() this one can just sort pinned notes to
  # the front without breaking a cursor.
  my $sql = qq{
    SELECT c.id, c.body, c.lawyer_only, c.ai_assisted, c.pinned, c.tags, c.package AS package_id, c.package_name,
           c.author AS author_id, u.login AS author_login, u.roles AS author_roles,
           EXTRACT(EPOCH FROM c.created) AS created_epoch,
           EXTRACT(EPOCH FROM c.edited)  AS edited_epoch,
           p.state AS package_state, p.obsolete AS package_obsolete,
           p.external_link AS package_external_link, p.checksum AS package_checksum,
           COUNT(*) OVER() AS total
      FROM package_notes c
      JOIN bot_users u ON c.author = u.id
      LEFT JOIN bot_packages p ON c.package = p.id
     WHERE 1 = 1 } . join(' ', @sql) . qq{
     ORDER BY c.pinned DESC, c.id DESC
     LIMIT ? OFFSET ?
  };

  my $rows = $self->pg->db->query($sql, @args, $limit, $offset)->hashes->to_array;
  return paginate($rows, {offset => $offset});
}

sub counts ($self, $package_name) {
  return $self->pg->db->query(
    'SELECT COUNT(*)::int AS total,
            COUNT(*) FILTER (WHERE lawyer_only = true)::int AS lawyer_only,
            COUNT(*) FILTER (WHERE pinned = true)::int AS pinned
       FROM package_notes WHERE package_name = ?', $package_name
  )->hash;
}

sub relevant_count ($self, $package_name, $package_id, $checksum, %opts) {
  my @sql  = ('c.package_name = ?');
  my @args = ($package_name);
  push @sql, 'c.lawyer_only = false' unless $opts{include_lawyer_only};
  if (defined $checksum) {
    push @sql, '(c.pinned = true OR c.package = ? OR p.checksum = ?)';
    push @args, $package_id, $checksum;
  }
  else {
    push @sql,  '(c.pinned = true OR c.package = ?)';
    push @args, $package_id;
  }
  my $sql = 'SELECT COUNT(*)::int AS relevant FROM package_notes c
              LEFT JOIN bot_packages p ON c.package = p.id WHERE ' . join(' AND ', @sql);
  return $self->pg->db->query($sql, @args)->hash->{relevant};
}

# Newest note id that carries $tag AND is relevant to the given review (native or
# identical license report), or undef. Powers the server-side idempotency guard
# in cavil_create_note: a relevant tagged note means this exact report (or one
# with identical license findings) was already annotated, so a re-run must skip.
# Pinning deliberately does not widen this the way it widens relevant_only: the
# question here is "was this report annotated", and a pinned note from an
# unrelated report would suppress the annotation that report never got.
sub relevant_tagged_note ($self, $package_name, $package_id, $checksum, $tag, %opts) {
  my @sql  = ('c.package_name = ?', 'c.tags @> ?::text[]');
  my @args = ($package_name, [$tag]);
  push @sql, 'c.lawyer_only = false' unless $opts{include_lawyer_only};
  if (defined $checksum) {
    push @sql, '(c.package = ? OR p.checksum = ?)';
    push @args, $package_id, $checksum;
  }
  else {
    push @sql,  'c.package = ?';
    push @args, $package_id;
  }
  my $sql = 'SELECT c.id FROM package_notes c
              LEFT JOIN bot_packages p ON c.package = p.id WHERE '
    . join(' AND ', @sql) . ' ORDER BY c.id DESC LIMIT 1';
  my $row = $self->pg->db->query($sql, @args)->hash;
  return $row ? $row->{id} : undef;
}

sub remove ($self, $id) {
  return $self->pg->db->query('DELETE FROM package_notes WHERE id = ? RETURNING id', $id)->rows;
}

sub edit ($self, $id, $body, $tags = undef) {
  my $rows;
  if (defined $tags) {
    $rows
      = $self->pg->db->query('UPDATE package_notes SET body = ?, tags = ?, edited = now() WHERE id = ? RETURNING id',
      $body, $tags, $id)->rows;
  }
  else {
    $rows
      = $self->pg->db->query('UPDATE package_notes SET body = ?, edited = now() WHERE id = ? RETURNING id', $body, $id)
      ->rows;
  }
  return undef unless $rows;
  return $self->find($id);
}

# Pinning is curation, not an edit; preserve the content timestamp.
sub set_pinned ($self, $id, $pinned) {
  my $rows
    = $self->pg->db->query('UPDATE package_notes SET pinned = ? WHERE id = ? RETURNING id', $pinned ? 1 : 0, $id)->rows;
  return undef unless $rows;
  return $self->find($id);
}

sub pinned_count ($self, $package_name) {
  return $self->pg->db->query('SELECT COUNT(*)::int AS pinned FROM package_notes WHERE package_name = ? AND pinned',
    $package_name)->hash->{pinned};
}

sub _query ($self, $extra_sql, $extra_args, $tail_sql = '', $tail_args = []) {
  my $sql = qq{
    SELECT c.id, c.body, c.lawyer_only, c.ai_assisted, c.pinned, c.tags, c.package AS package_id, c.package_name,
           c.author AS author_id, u.login AS author_login, u.roles AS author_roles,
           EXTRACT(EPOCH FROM c.created) AS created_epoch,
           EXTRACT(EPOCH FROM c.edited)  AS edited_epoch,
           p.state AS package_state, p.obsolete AS package_obsolete,
           p.external_link AS package_external_link, p.checksum AS package_checksum
      FROM package_notes c
      JOIN bot_users u ON c.author = u.id
      LEFT JOIN bot_packages p ON c.package = p.id
     WHERE 1 = 1 $extra_sql $tail_sql
  };
  return $self->pg->db->query($sql, @$extra_args, @$tail_args)->hashes->to_array;
}

1;
