# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later
package Cavil::Controller::Notes;
use Mojo::Base 'Mojolicious::Controller', -signatures;

use Cavil::Model::Notes qw(NOTE_BODY_MAX_LENGTH);
use Cavil::Util         qw(validate_tags);
use Mojo::JSON          qw(from_json true false);

sub list ($self) {
  my $id  = $self->stash('id');
  my $pkg = $self->packages->find($id);
  return $self->render(json => {error => 'Package not found'}, status => 404) unless $pkg;

  my $v = $self->validation;
  $v->optional('limit')->num;
  $v->optional('before_id')->num;
  $v->optional('relevant_only')->in('0', '1');
  return $self->reply->json_validation_error if $v->has_error;

  my $relevant_only       = ($v->param('relevant_only') // '0') eq '1';
  my $include_lawyer_only = $self->_can_see_lawyer_only;
  my $page                = $self->notes->list(
    $pkg->{name},
    include_lawyer_only => $include_lawyer_only,
    limit               => $v->param('limit'),
    before_id           => $v->param('before_id'),
    relevant_only       => $relevant_only,
    package_id          => $id,
    checksum            => $pkg->{checksum}
  );
  my $counts  = $self->notes->counts($pkg->{name});
  my $user_id = $self->_current_user_id;

  # Visible relevant count drives the "Only relevant notes" toggle (shown only
  # when there are non-relevant notes to hide) and its "N of M" hint.
  my $relevant
    = $self->notes->relevant_count($pkg->{name}, $id, $pkg->{checksum}, include_lawyer_only => $include_lawyer_only);

  $self->render(
    json => {
      notes    => [map { $self->_format_note($_, $user_id, $pkg->{checksum}) } @{$page->{notes}}],
      has_more => $page->{has_more}    ? \1               : \0,
      total    => $include_lawyer_only ? $counts->{total} : $counts->{total} - $counts->{lawyer_only},
      relevant => $relevant,

      # Hide the lawyer-only count from viewers who can't see those notes,
      # otherwise the tab amber tint leaks their existence.
      lawyer_only         => $include_lawyer_only         ? $counts->{lawyer_only} : 0,
      can_lawyer_only     => $self->_can_post_lawyer_only ? \1                     : \0,
      can_see_lawyer_only => $include_lawyer_only         ? \1                     : \0
    }
  );
}

sub create ($self) {
  my $id  = $self->stash('id');
  my $pkg = $self->packages->find($id);
  return $self->render(json => {error => 'Package not found'}, status => 404) unless $pkg;

  my $v = $self->validation;
  $v->required('body')->size(1, NOTE_BODY_MAX_LENGTH);
  $v->optional('lawyer_only')->in('0', '1');
  return $self->reply->json_validation_error if $v->has_error;

  my $body        = $v->param('body');
  my $lawyer_only = ($v->param('lawyer_only') // '0') eq '1' ? 1 : 0;
  return $self->render(json => {error => 'Not allowed to post lawyer-only notes'}, status => 403)
    if $lawyer_only && !$self->_can_post_lawyer_only;

  my ($tags, $tag_error) = validate_tags($self->_tags_from_params);
  return $self->render(json => {error => $tag_error}, status => 400) if $tag_error;

  my $author = $self->users->find(login => $self->current_user)
    or return $self->render(json => {error => 'Unknown user'}, status => 403);

  my $note = $self->notes->add($id, $pkg->{name}, $author->{id}, $body, $lawyer_only, 0, $tags);
  $self->render(json => {note => $self->_format_note($note, $author->{id})});
}

sub recent ($self) {
  return $self->render unless ($self->stash('format') // 'html') eq 'json';

  my $v = $self->validation;
  $v->optional('limit')->num;
  $v->optional('before_id')->num;
  return $self->reply->json_validation_error if $v->has_error;

  # An invalid filter (too many/long tags) shouldn't 400 a list view; just
  # ignore it and show the unfiltered page.
  my ($tags) = validate_tags($self->_tags_from_params);

  my $include_lawyer_only = $self->_can_see_lawyer_only;
  my $page                = $self->notes->recent(
    include_lawyer_only => $include_lawyer_only,
    limit               => $v->param('limit'),
    before_id           => $v->param('before_id'),
    tags                => $tags
  );
  my $user_id = $self->_current_user_id;

  $self->render(
    json => {
      notes               => [map { $self->_format_note($_, $user_id) } @{$page->{notes}}],
      has_more            => $page->{has_more}            ? \1 : \0,
      can_lawyer_only     => $self->_can_post_lawyer_only ? \1 : \0,
      can_see_lawyer_only => $include_lawyer_only         ? \1 : \0
    }
  );
}

sub tags ($self) {
  my $tags = $self->notes->all_tags(include_lawyer_only => $self->_can_see_lawyer_only);
  $self->render(json => {tags => $tags});
}

sub remove ($self) {
  my $id   = $self->stash('id');
  my $note = $self->notes->find($id);
  return $self->render(json => {error => 'Note not found'}, status => 404) unless $note;

  my $author = $self->users->find(login => $self->current_user)
    or return $self->render(json => {error => 'Unknown user'}, status => 403);
  my $is_owner   = $author->{id} == $note->{author_id};
  my $can_curate = $self->current_user_can('curate');
  return $self->render(json => {error => 'Not allowed to remove this note'}, status => 403)
    unless $is_owner || $can_curate;

  my $removed = $self->notes->remove($id);
  $self->render(json => {removed => $removed ? \1 : \0});
}

sub update ($self) {
  my $id   = $self->stash('id');
  my $note = $self->notes->find($id);
  return $self->render(json => {error => 'Note not found'}, status => 404) unless $note;

  my $v = $self->validation;
  $v->required('body')->size(1, NOTE_BODY_MAX_LENGTH);
  return $self->reply->json_validation_error if $v->has_error;

  my $author = $self->users->find(login => $self->current_user)
    or return $self->render(json => {error => 'Unknown user'}, status => 403);

  # Authors can edit their own notes. Admins can edit anyone's (so they can
  # fix typos in lawyer-only notes etc.). Lawyer-only flag is intentionally
  # not editable here - flipping it would mean retroactively hiding content
  # that other people may already have referenced.
  my $is_owner   = $author->{id} == $note->{author_id};
  my $can_curate = $self->current_user_can('curate');
  return $self->render(json => {error => 'Not allowed to edit this note'}, status => 403)
    unless $is_owner || $can_curate;

  my $raw_tags = $self->_tags_from_params;
  my ($tags, $tag_error) = validate_tags($raw_tags);
  return $self->render(json => {error => $tag_error}, status => 400) if $tag_error;
  my $tags_arg = defined $raw_tags ? $tags : undef;

  my $updated = $self->notes->edit($id, $v->param('body'), $tags_arg);
  return $self->render(json => {error => 'Edit failed'}, status => 500) unless $updated;
  $self->render(json => {note => $self->_format_note($updated, $author->{id})});
}

# Renders a markdown preview without persisting anything. Used by the note
# form's Write/Preview tabs.
sub preview ($self) {
  my $v = $self->validation;
  $v->required('body')->size(1, NOTE_BODY_MAX_LENGTH);
  return $self->reply->json_validation_error if $v->has_error;
  $self->render(json => {html => $self->markdown_to_safe_html($v->param('body'))});
}

sub _can_post_lawyer_only ($self) {
  return $self->current_user_can('curate') ? 1 : 0;
}

# Lawyer-only notes are visible only to admins and lawyers; everyone else
# sees the public subset.
sub _can_see_lawyer_only ($self) { $self->_can_post_lawyer_only }

sub _format_note ($self, $row, $user_id, $current_checksum = undef) {
  my $body_html  = $self->markdown_to_safe_html($row->{body});
  my $can_curate = $self->current_user_can('curate');
  my $is_owner   = $user_id && $row->{author_id} == $user_id;

  # True when this note comes from a review with a license report identical to
  # the one being viewed (same bot_packages.checksum) - so it applies verbatim.
  # Only meaningful in the per-package report view, which passes a checksum.
  my $same_report
    = (defined $current_checksum && defined $row->{package_checksum} && $row->{package_checksum} eq $current_checksum)
    ? \1
    : \0;

  return {
    id            => $row->{id},
    body          => $row->{body},
    body_html     => $body_html,
    lawyer_only   => $row->{lawyer_only} ? \1 : \0,
    ai_assisted   => $row->{ai_assisted} ? \1 : \0,
    same_report   => $same_report,
    tags          => $row->{tags} // [],
    package_name  => $row->{package_name},
    can_delete    => ($is_owner || $can_curate) ? \1 : \0,
    can_edit      => ($is_owner || $can_curate) ? \1 : \0,
    created_epoch => $row->{created_epoch} + 0,
    edited_epoch  => $row->{edited_epoch} ? $row->{edited_epoch} + 0 : undef,
    author        => {
      id       => $row->{author_id},
      login    => $row->{author_login},
      fullname => $row->{author_fullname},
      badge    => _author_badge($row->{author_roles})
    },
    original_package => {
      id            => $row->{package_id},
      state         => $row->{package_state},
      obsolete      => $row->{package_obsolete} ? \1 : \0,
      external_link => $row->{package_external_link}
    }
  };
}

# Highest-precedence role wins, GitHub-style. Lawyer outranks admin (legal
# expertise is the stronger signal for a legal-review note) outranks plain
# user. Returns undef for bots or other roles so the UI can omit the chip.
sub _author_badge ($roles) {
  return undef unless $roles && @$roles;
  my %has = map { $_ => 1 } @$roles;
  return 'lawyer' if $has{lawyer};
  return 'admin'  if $has{admin};
  return 'user'   if $has{user};
  return undef;
}

sub _tags_from_params ($self) {
  my $req = $self->req;

  # The Vue UI ships tags as a JSON-encoded string because mojojs/user-agent
  # comma-joins arrayref form values instead of repeating the param. Try the
  # JSON shape first so the UI round-trip is exact, then fall back to the
  # repeating-param convention used by Perl test clients.
  if (defined(my $json = $req->param('tags_json'))) {
    return [] if $json eq '';
    my $parsed = eval { from_json($json) };
    return undef if $@ || ref $parsed ne 'ARRAY';
    return $parsed;
  }

  my @keys = $req->params->names->@*;
  return undef unless grep { $_ eq 'tags' || $_ eq 'tags[]' } @keys;
  my @values = map { $req->every_param($_)->@* } grep { $_ eq 'tags' || $_ eq 'tags[]' } @keys;
  return \@values;
}

sub _current_user_id ($self) {
  my $login = $self->current_user;
  return undef unless $login;
  my $user = $self->users->find(login => $login);
  return $user ? $user->{id} : undef;
}

1;
