# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later
use Mojo::Base -strict, -signatures;

use Test::More;
use Cavil::Role qw(all_capabilities all_roles capabilities_for role_has_capability roles_with_capability);

subtest 'role -> capability map' => sub {
  is_deeply capabilities_for('user'),        ['view'],                                  'user is view only';
  is_deeply capabilities_for('classifier'),  [qw(classify view)],                       'classifier adds classify';
  is_deeply capabilities_for('contributor'), [qw(propose view)],                        'contributor adds propose';
  is_deeply capabilities_for('manager'),     [qw(review view)],                         'manager adds review';
  is_deeply capabilities_for('admin'), [qw(classify curate infra propose review view)], 'admin is curator + infra';
  is_deeply capabilities_for('lawyer'), [qw(classify curate propose review review_lawyer view)],
    'lawyer is curator + review_lawyer';
};

subtest 'admin and lawyer differ by exactly one capability each' => sub {
  my %admin       = map  { $_ => 1 } @{capabilities_for('admin')};
  my %lawyer      = map  { $_ => 1 } @{capabilities_for('lawyer')};
  my @admin_only  = grep { !$lawyer{$_} } sort keys %admin;
  my @lawyer_only = grep { !$admin{$_} } sort keys %lawyer;
  is_deeply \@admin_only,  ['infra'],         'only admin has infra';
  is_deeply \@lawyer_only, ['review_lawyer'], 'only lawyer has review_lawyer';
};

subtest 'roles_with_capability drives the route gates' => sub {
  is_deeply roles_with_capability('infra'),         ['admin'],                      'infra is admin only';
  is_deeply roles_with_capability('review_lawyer'), ['lawyer'],                     'review_lawyer is lawyer only';
  is_deeply roles_with_capability('curate'),        [qw(admin lawyer)],             'curate is admin + lawyer';
  is_deeply roles_with_capability('review'),        [qw(admin lawyer manager)],     'review adds manager';
  is_deeply roles_with_capability('propose'),       [qw(admin contributor lawyer)], 'propose adds contributor';
  is_deeply roles_with_capability('classify'),      [qw(admin classifier lawyer)],  'classify adds classifier';
};

subtest 'union and helpers' => sub {
  is_deeply capabilities_for(qw(admin lawyer)), [qw(classify curate infra propose review review_lawyer view)],
    'a user with both roles gets the union';
  ok role_has_capability('lawyer', 'review_lawyer'), 'lawyer has review_lawyer';
  ok !role_has_capability('admin', 'review_lawyer'), 'admin does not have review_lawyer';
  is_deeply capabilities_for('bot'), [], 'unknown/internal role grants no web capabilities';
  is_deeply all_roles,               [qw(admin classifier contributor lawyer manager user)], 'all roles';
};

done_testing;
