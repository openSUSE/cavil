# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package Cavil::Classifier;
use Mojo::Base -base, -signatures;

use Carp 'croak';
use Mojo::UserAgent;

has ua    => sub { Mojo::UserAgent->new(inactivity_timeout => 600) };
has token => sub {''};
has type  => sub {'legacy'};
has 'url';

# Exactly the Alpaca template the Cavil models are fine-tuned with (spaces included), on the first 2048 characters of
# a snippet like in training; other wording or longer input costs accuracy and speed
my $PROMPT
  = "Below is an instruction that describes a task, paired with an input that provides further context. Write a"
  . " response that appropriately completes the request.\n\n### Instruction:\n Analyze the code or documentation"
  . ' snippet enclosed in "[CODE]" and "[/CODE]" tokens to determine if it contains legal text that was written with'
  . ' the intention of describing how the code should be used. Answer only with "yes" or "no". '
  . "\n\n### Input:\n[CODE]%s[/CODE]\n\n### Response:\n";

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

sub _prompt ($text) { sprintf $PROMPT, substr $text, 0, 2048 }

1;
