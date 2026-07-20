# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package Cavil::Role;
use Mojo::Base -strict, -signatures;

use Exporter 'import';

our @EXPORT_OK = qw(all_capabilities all_roles capabilities_for role_has_capability roles_with_capability);

# The single source of truth for authorization. Roles are named bundles of capabilities; every gate
# (route, controller check, frontend flag, MCP scope) should be expressed in terms of a capability and
# resolved through this map, never by reaching for a specific role name. See the Access Levels section
# of docs/Architecture.md.
#
# `user` and `admin` are the base roles; the rest are extensions that add capabilities. `admin` and
# `lawyer` share the "curator core" (view/classify/propose/curate/review); `admin` additionally has
# `infra` (Minion dashboard, uploads) while `lawyer` additionally has `review_lawyer` (the legal
# sign-off that produces `acceptable_by_lawyer`). So the two differ by exactly one capability each.
my %ROLE_CAPABILITIES = (
  user        => [qw(view)],
  classifier  => [qw(view classify)],
  contributor => [qw(view propose)],
  manager     => [qw(view review)],
  admin       => [qw(view classify propose curate review infra)],
  lawyer      => [qw(view classify propose curate review review_lawyer)],
);

# Capabilities held by (the union of) the given roles. Unknown roles (e.g. the internal `bot` API
# identity, which is not a web role) contribute nothing.
sub capabilities_for (@roles) {
  my %caps;
  for my $role (@roles) { $caps{$_} = 1 for @{$ROLE_CAPABILITIES{$role} // []} }
  return [sort keys %caps];
}

sub role_has_capability ($role, $cap) {
  return (grep { $_ eq $cap } @{$ROLE_CAPABILITIES{$role} // []}) ? 1 : 0;
}

# The roles that grant a capability, as a sorted arrayref. This is what feeds Auth#check's
# `roles => [...]` (any-of) gate, so a route is gated by capability without naming roles inline.
sub roles_with_capability ($cap) {
  return [sort grep { role_has_capability($_, $cap) } keys %ROLE_CAPABILITIES];
}

sub all_roles () { return [sort keys %ROLE_CAPABILITIES] }

sub all_capabilities () { return capabilities_for(keys %ROLE_CAPABILITIES) }

1;
