# Copyright 2018-2026 SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package Cavil::Classifier;
use Mojo::Base -base, -signatures;

use Carp 'croak';
use Mojo::UserAgent;

has ua    => sub { Mojo::UserAgent->new(inactivity_timeout => 600) };
has token => sub {''};
has type  => sub {'legacy'};
has 'url';

my $PROMPT = <<'EOF';
You are a helpful lawyer. Analyze the code or documentation snippet enclosed
in "[CODE]" and "[/CODE]" tokens to determine if it contains legal text that
was written with the intention of describing how the code should be used.
Answer only with "yes" or "no".

User:
[CODE]// SPDX-License-Identifier: MIT[/CODE]
Assistant:
yes

User:
[CODE]// Released under BSD-2-clause license[/CODE]
Assistant:
yes

User:
[CODE]# Released under BSD-3-clause license[/CODE]
Assistant:
yes

User:
[CODE]Hello World[/CODE]
Assistant:
no

User:
[CODE]Foo Bar Baz[/CODE]
Assistant:
no

User:
[CODE]GPL License Version 2.0[/CODE]
Assistant:
yes

User:
[CODE]// Copyright 2024
//Licensed as BSD-3-clause
[/CODE]
Assistant:
yes

User:
[CODE]my $foo = 23;[/CODE]
Assistant:
no

User:
[CODE]
# SPDX-License-Identifier: MIT
my $foo = 23;
[/CODE]
Assistant:
yes

User:
[CODE]if (license === true) {[/CODE]
Assistant:
no

Analyze the following code or documentation snippet. Answer only with "yes" or "no".
EOF

sub classify ($self, $text) {
  croak 'No classifier configured' unless my $url = $self->url;
  my $type = $self->type;
  return $self->_classify_legacy($url, $text)    if $type eq 'legacy';
  return $self->_classify_llama_cpp($url, $text) if $type eq 'llama_cpp';
  croak "Unknown classifier type: $type";
}

sub _classify_legacy ($self, $url, $text) {
  return $self->ua->post($url => {Authorization => 'Token ' . $self->token} => json => $text)->result->json;
}

sub _classify_llama_cpp ($self, $url, $text) {
  my $input = {prompt => _prompt($text), max_tokens => 1, temperature => 0.0, n_probs => 1};
  my $res = $self->ua->post("$url/completion" => {Authorization => 'Bearer ' . $self->token} => json => $input)->result;
  my $output = $res->json;
  return $output unless $res->is_success;

  my $is_license = ($output->{content} // '') eq 'no' ? 0 : 1;
  my $confidence = sprintf '%.2f', exp($output->{completion_probabilities}[0]{logprob} // 0) * 100;
  return {license => $is_license, confidence => $confidence};
}

sub _prompt ($text) {
  return "$PROMPT\nUser:\n\[CODE\]$text\[/CODE\]\nAssistant:\n";
}

1;
