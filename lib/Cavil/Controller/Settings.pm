# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package Cavil::Controller::Settings;
use Mojo::Base 'Mojolicious::Controller', -signatures;

# A section can only read and change its own keys
my %SECTION_KEYS = (
  'auto-accept' => [qw(acceptable_packages acceptable_risk auto_accept_risk)],
  sbom          => [qw(sbom_creator_email sbom_creator_name sbom_creator_url)]
);

sub add_bot_token ($self) {
  my $v = $self->validation;
  $v->optional('description', 'trim');
  $v->optional('token',       'trim');
  return $self->reply->json_validation_error if $v->has_error;

  my %token  = (description => $v->param('description') // '', token => $v->param('token') || undef);
  my $tokens = $self->bot_tokens;
  if (my $error = $tokens->invalid(\%token)) { return $self->render(json => {error => $error}, status => 400) }
  return $self->render(json => {error => 'This token already exists'}, status => 400)
    unless $tokens->add(\%token, $self->current_user);
  return $self->render(json => 'ok');
}

sub add_exclusion ($self) {
  my $v = $self->validation;
  $v->required('package_glob', 'trim')->like(qr/^\S+$/);
  $v->required('file',         'trim')->like(qr/^\S+$/);
  $v->optional('reason', 'trim');
  return $self->reply->json_validation_error if $v->has_error;

  my %rule
    = (package_glob => $v->param('package_glob'), file => $v->param('file'), reason => $v->param('reason') // '');
  my $exclusions = $self->unpack_exclusions;
  if (my $error = $exclusions->invalid(\%rule)) { return $self->render(json => {error => $error}, status => 400) }
  return $self->render(json => {error => 'This file is already excluded for these packages'}, status => 400)
    unless $exclusions->add(\%rule, $self->current_user);
  return $self->render(json => 'ok');
}

sub first ($self) {
  $self->redirect_to('/settings/api-keys');
}

sub list_bot_tokens ($self) {
  $self->render(
    json => {
      tokens      => $self->bot_tokens->list,
      last_change => $self->audit_log->last_event(['bot_token.added', 'bot_token.removed'])
    }
  );
}

sub remove_bot_token ($self) {
  return $self->render(json => {error => 'Bot token does not exist'}, status => 400)
    unless $self->bot_tokens->remove($self->param('id'), $self->current_user);
  return $self->render(json => 'ok');
}

sub remove_exclusion ($self) {
  return $self->render(json => {error => 'Excluded file does not exist'}, status => 400)
    unless $self->unpack_exclusions->remove($self->param('id'), $self->current_user);
  return $self->render(json => 'ok');
}

sub section ($self) {
  $self->render(json => $self->_section_summary($self->stash('section')));
}

sub show ($self) {
  $self->render('settings/show', section => $self->stash('section'));
}

sub status ($self) { $self->render(json => {checks => $self->app->status->checks}) }

sub update_section ($self) {
  my $keys = $SECTION_KEYS{$self->stash('section')};
  my $body = $self->req->json;
  return $self->render(json => {error => 'Invalid request'}, status => 400)
    unless ref $body eq 'HASH' && ref($body->{values} // {}) eq 'HASH' && ref($body->{reset} // []) eq 'ARRAY';
  my ($values, $reset) = ($body->{values} // {}, $body->{reset} // []);

  my %own    = map { $_ => 1 } @$keys;
  my %errors = map { $_ => 'Not part of this section' } grep { !$own{$_} } keys %$values, @$reset;
  return $self->render(json => {errors => \%errors}, status => 400) if %errors;

  my $result = $self->settings->update($self->current_user, $values, $reset);
  return $self->render(json => {errors => $result->{errors}}, status => 400) if $result->{errors};

  my $rechecked = $self->packages->analyze_held($result->{old}, $result->{new});
  $self->render(json => {%{$self->_section_summary($self->stash('section'))}, rechecked => $rechecked});
}

sub _section_summary ($self, $section) {
  my $keys    = $SECTION_KEYS{$section};
  my $summary = $self->settings->summary(@$keys);
  $summary->{last_change} = $self->audit_log->last_event(['settings.changed'], $keys);
  $summary->{fallbacks}   = $self->app->spdx->creator if $section eq 'sbom';
  return $summary;
}

1;
