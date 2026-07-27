# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package Cavil::Model::CommentTemplates;
use Mojo::Base -base, -signatures;

use Cavil::Util qw(paginate);

has [qw(log pg)];

sub add ($self, $name, $body, $author) {
  my $db = $self->pg->db;
  my $id = $db->query('SELECT id FROM bot_users WHERE login = ?', $author)->hash->{id};
  return $db->insert('comment_templates', {name => $name, body => $body, author => $id}, {returning => 'id'})
    ->hash->{id};
}

# Unpaginated, for the template picker in the comment editor
sub all ($self) {
  return $self->pg->db->query('SELECT id, name, body FROM comment_templates ORDER BY name')->hashes->to_array;
}

sub edit ($self, $id, $name, $body) {
  my $rows
    = $self->pg->db->query('UPDATE comment_templates SET name = ?, body = ?, edited = now() WHERE id = ? RETURNING id',
    $name, $body, $id)->rows;
  return undef unless $rows;
  return $self->find($id);
}

sub find ($self, $id) {
  return $self->pg->db->select('comment_templates', ['id', 'name', 'body', 'author'], {id => $id})->hash;
}

sub find_name ($self, $name) {
  my $hash = $self->pg->db->select('comment_templates', 'id', {name => $name})->hash;
  return $hash ? $hash->{id} : undef;
}

sub paginate_templates ($self, $options) {
  my $db = $self->pg->db;

  my $search = '';
  if (length($options->{search}) > 0) {
    my $quoted = $db->dbh->quote("\%$options->{search}\%");
    $search = "WHERE ct.name ILIKE $quoted OR ct.body ILIKE $quoted";
  }

  # LEFT JOIN because templates that shipped with Cavil have no author
  my $results = $db->query(
    qq{
      SELECT ct.id, ct.name, ct.body, EXTRACT(EPOCH FROM ct.created) AS created_epoch,
        EXTRACT(EPOCH FROM ct.edited) AS edited_epoch, bu.login, COUNT(*) OVER() AS total
      FROM comment_templates ct LEFT JOIN bot_users bu ON (ct.author = bu.id)
      $search
      ORDER BY ct.name
      LIMIT ? OFFSET ?
    }, $options->{limit}, $options->{offset}
  )->hashes->to_array;

  return paginate($results, $options);
}

sub remove ($self, $id, $user) {
  return undef unless my $hash = $self->pg->db->delete('comment_templates', {id => $id}, {returning => ['name']})->hash;
  $self->log->info(qq{User "$user" removed comment template "$hash->{name}"});
  return 1;
}

1;
