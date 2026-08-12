# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package Cavil::Role;
use Mojo::Base -strict, -signatures;

use Exporter 'import';

our @EXPORT_OK = qw(all_capabilities all_roles capabilities_for role_has_capability roles_with_capability);

# Authorization gates resolve capabilities here instead of naming roles.
my %ROLE_CAPABILITIES = (
  user        => [qw(view)],
  classifier  => [qw(view classify)],
  contributor => [qw(view propose)],
  manager     => [qw(view review)],
  admin       => [qw(view classify propose curate review infra)],
  lawyer      => [qw(view classify propose curate review review_lawyer)],
);

# Internal identities such as `bot` are not web roles and grant no capabilities.
sub capabilities_for (@roles) {
  my %caps;
  for my $role (@roles) { $caps{$_} = 1 for @{$ROLE_CAPABILITIES{$role} // []} }
  return [sort keys %caps];
}

sub role_has_capability ($role, $cap) {
  return (grep { $_ eq $cap } @{$ROLE_CAPABILITIES{$role} // []}) ? 1 : 0;
}

# Keep route gates capability-based as roles evolve.
sub roles_with_capability ($cap) {
  return [sort grep { role_has_capability($_, $cap) } keys %ROLE_CAPABILITIES];
}

sub all_roles () { return [sort keys %ROLE_CAPABILITIES] }

sub all_capabilities () { return capabilities_for(keys %ROLE_CAPABILITIES) }

1;
