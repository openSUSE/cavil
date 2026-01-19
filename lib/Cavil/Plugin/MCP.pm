# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later
package Cavil::Plugin::MCP;
use Mojo::Base 'Mojolicious::Plugin', -signatures;

use MCP::Server;

sub register ($self, $app, $config) {
  my $mcp = MCP::Server->new;
  $mcp->name('Cavil');
  $mcp->version('1.0.0');

  $mcp->tool(
    name         => 'cavil_get_open_reviews',
    description  => 'Get list of 20 highest priority open reviews, use "search" to limit results',
    input_schema => {type => 'object', properties => {search => {type => 'string'}}, required => []},
    code         => \&tool_cavil_get_open_reviews
  );
  $mcp->tool(
    name         => 'cavil_get_report',
    description  => 'Get legal report for a specific package',
    input_schema =>
      {type => 'object', properties => {package_id => {type => 'integer', minimum => 1}}, required => ['package_id']},
    code => \&tool_cavil_get_report
  );

  return $mcp->to_action;
}

sub tool_cavil_get_open_reviews ($tool, $args) {
  my $c       = _get_controller($tool);
  my $reviews = $c->packages->paginate_open_reviews(
    {limit => 20, offset => 0, in_progress => 'false', not_embargoed => 'true', search => $args->{search} // ''});
  return
    return $c->render_to_string('mcp/open_reviews', format => 'txt', reviews => $reviews->{page},
    total => $reviews->{total});
}

sub tool_cavil_get_report ($tool, $args) {
  my $id = $args->{package_id};
  my $c  = _get_controller($tool);
  return $tool->text_result('Package not found', 1) unless my $pkg = $c->packages->find($id);
  return $tool->text_result('Package is embargoed and may not be processed with AI', 1) if $pkg->{embargoed};

  return $tool->text_result('Package is being processed, please try again later', 1)
    if $c->app->minion->jobs({states => ['inactive', 'active'], notes => ["pkg_$id"]})->total;

  return $tool->text_result('Package is not yet indexed, please try again later', 1) unless $pkg->{indexed};

  return $tool->text_result('No report available', 1) unless defined((my $report = $c->helpers->mcp_report($id)));
  return $tool->text_result($report);
}

sub _get_controller ($tool) { $tool->context->{controller} }

1;
