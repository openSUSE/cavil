# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package Cavil::Controller::CodeSearch;
use Mojo::Base 'Mojolicious::Controller', -signatures;

use JSON::Schema::Tiny qw(evaluate);

# Request-body schemas for the JSON endpoints. Fingerprints and hashes are strings (a 64-bit fingerprint does
# not survive JSON as a number), and the item caps live here so oversized requests are rejected in one place.
my %SCHEMA = (
  known => {
    type       => 'object',
    required   => ['hashes'],
    properties => {hashes => {type => 'array', maxItems => 1000, items => {type => 'string'}}}
  },
  search_batch => {
    type       => 'object',
    required   => ['queries'],
    properties => {
      limit   => {type => 'integer'},
      queries => {
        type     => 'array',
        maxItems => 100,
        items    => {
          type       => 'object',
          required   => ['fingerprints'],
          properties =>
            {fingerprints => {type => 'array', items => {type => 'string'}}, span => {type => 'integer', minimum => 1}}
        }
      }
    }
  }
);

sub index ($self) {
  return $self->reply->not_found unless $self->codesearch;
  $self->render;
}

sub search ($self) {
  return $self->render(json => {error => 'Code search is not enabled'}, status => 404) unless $self->codesearch;

  my $v = $self->validation;
  $v->required('snippet');
  $v->optional('limit')->num;
  $v->optional('offset')->num;
  return $self->reply->json_validation_error if $v->has_error;

  my $limit = $v->param('limit') // 10;
  $limit = 100 if $limit > 100;
  $limit = 1   if $limit < 1;
  my $offset = $v->param('offset') // 0;
  $offset = 0 if $offset < 0;

  $self->render(json => $self->fingerprints->search(scalar $v->param('snippet'), $limit, $offset));
}

# The winnowing parameters the client must use so its fingerprints match this instance's index.
sub config ($self) {
  return $self->render(json => {error => 'Code search is not enabled'}, status => 404) unless $self->codesearch;
  $self->render(json => {k => $self->fingerprints->k, w => $self->fingerprints->w});
}

# Batch content-hash lookup: {hashes => [...]} -> {<hash> => {licenses => [...], risk => N}}. Unknown hashes
# are omitted. This is the CLI's cheap recognition path, answered straight from an index.
sub known ($self) {
  return $self->render(json => {error => 'Code search is not enabled'}, status => 404) unless $self->codesearch;
  my $data = $self->_body($SCHEMA{known}) or return;

  $self->render(json => $self->fingerprints->known_hashes($data->{hashes}));
}

# Batch fingerprint search: {queries => [{id, fingerprints => [...], span => N}, ...]} -> {results => [...]}.
# The schema guarantees each query is an object with a fingerprints array, so the loop can trust its shape.
# Each result carries its query id and the same match shape as the single snippet search.
sub search_batch ($self) {
  return $self->render(json => {error => 'Code search is not enabled'}, status => 404) unless $self->codesearch;
  my $data = $self->_body($SCHEMA{search_batch}) or return;

  my $limit = $data->{limit} // 10;
  $limit = 100 if $limit > 100;
  $limit = 1   if $limit < 1;

  my $fingerprints = $self->fingerprints;
  my @results;
  for my $q (@{$data->{queries}}) {
    my $result = $fingerprints->search_fingerprints($q->{fingerprints}, $q->{span} // 1, $limit, 0);
    $result->{id} = $q->{id};
    push @results, $result;
  }

  $self->render(json => {results => \@results});
}

# Decode and schema-validate the JSON request body; render a 400 with the details and return undef on failure.
sub _body ($self, $schema) {
  my $data   = $self->req->json;
  my $result = evaluate($data, $schema);
  return $data if $result->{valid};
  $self->render(
    json   => {error => 'Invalid request', details => [map { $_->{error} } @{$result->{errors}}]},
    status => 400
  );
  return undef;
}

1;
