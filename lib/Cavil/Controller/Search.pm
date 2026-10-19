# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package Cavil::Controller::Search;
use Mojo::Base 'Mojolicious::Controller', -signatures;

use Cavil::Util qw(parse_lookup);

sub search ($self) {
  my $validation = $self->validation;
  $validation->optional('q');
  return $self->reply->json_validation_error if $validation->has_error;

  # Logged on page load only, the results page polls. Shows how ids are really cited, to compare with the lookup rules.
  my $q = $validation->param('q');
  $self->log->info('Lookup without match: ' . ($q =~ s/\s+/ /gr)) if ($self->lookup_reviews($q) // [1])->@* == 0;

  $self->render('search/results');
}

sub autocomplete ($self) {
  my $validation = $self->validation;
  $validation->optional('q');
  return $self->reply->json_validation_error if $validation->has_error;

  my $suggestions = [];
  my $query       = $validation->param('q');
  if (defined $query && !parse_lookup($query)) {
    $suggestions = $self->packages->name_autocomplete($query);
  }

  $self->render(json => $suggestions);
}

1;
