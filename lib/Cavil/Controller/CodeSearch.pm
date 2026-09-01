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
    properties => {
      hashes           => {type => 'array', maxItems => 1000, items => {type => 'string'}},
      exclude_packages => {type => 'array', maxItems => 100,  items => {type => 'string'}}
    }
  },
  search_batch => {
    type       => 'object',
    required   => ['queries'],
    properties => {
      limit            => {type => 'integer'},
      exclude_packages => {type => 'array', maxItems => 100, items => {type => 'string'}},
      queries          => {
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

# Fingerprints a single search_batch request may ask about in total. Each query is capped on its own
# (max_fingerprints) and each fingerprint reads at most df_cap carriers, but a batch multiplies those, so
# without a budget one request can occupy a web worker for minutes. Ten full-size queries is the ceiling; the
# client chunks well below it, and many small queries still batch wide.
use constant MAX_BATCH_FINGERPRINTS => 50_000;

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
  my $fp = $self->fingerprints;
  $self->render(
    json => {k => $fp->k, w => $fp->w, generation => $fp->generation, max_fingerprints => $fp->max_fingerprints});
}

# Batch content-hash lookup: {hashes => [...]} -> {<hash> => {licenses => [...], risk => N}}. Unknown hashes
# are omitted. This is the CLI's cheap recognition path, answered straight from an index. exclude_packages drops
# carriers by name, so an engineer scanning their own package does not see it match itself.
sub known ($self) {
  return $self->render(json => {error => 'Code search is not enabled'}, status => 404) unless $self->codesearch;
  my $data = $self->_body($SCHEMA{known}) or return;

  $self->render(json => $self->fingerprints->known_hashes($data->{hashes}, 0, $data->{exclude_packages}));
}

# Batch fingerprint search: {queries => [{id, fingerprints => [...], span => N}, ...]} -> {results => [...]}.
# The schema guarantees each query is an object with a fingerprints array, so the loop can trust its shape.
# Each result carries its query id and the same match shape as the single snippet search.
sub search_batch ($self) {
  return $self->render(json => {error => 'Code search is not enabled'}, status => 404) unless $self->codesearch;
  my $data = $self->_body($SCHEMA{search_batch}) or return;

  my $budget = 0;
  $budget += scalar @{$_->{fingerprints}} for @{$data->{queries}};
  return $self->render(
    json   => {error => 'Too many fingerprints in one request', limit => MAX_BATCH_FINGERPRINTS},
    status => 400
  ) if $budget > MAX_BATCH_FINGERPRINTS;

  my $limit = $data->{limit} // 10;
  $limit = 100 if $limit > 100;
  $limit = 1   if $limit < 1;

  my $fingerprints = $self->fingerprints;
  my $exclude      = $data->{exclude_packages};
  my @results;
  for my $q (@{$data->{queries}}) {
    my $result = $fingerprints->search_fingerprints($q->{fingerprints}, $q->{span} // 1, $limit, 0, 0, $exclude);
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
