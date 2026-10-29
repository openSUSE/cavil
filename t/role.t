# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Mojo::Base -strict, -signatures;

use Test::More;
use Cavil::Role qw(all_capabilities all_roles capabilities_for role_conflict role_has_capability roles_with_capability);

subtest 'role -> capability map' => sub {
  is_deeply capabilities_for('user'),        ['view'],                     'user is view only';
  is_deeply capabilities_for('uploader'),    [qw(upload_ephemeral view)],  'uploader adds upload_ephemeral';
  is_deeply capabilities_for('classifier'),  [qw(classify view)],          'classifier adds classify';
  is_deeply capabilities_for('contributor'), [qw(propose view)],           'contributor adds propose';
  is_deeply capabilities_for('manager'),     [qw(recommend review view)],  'manager adds review';
  is_deeply capabilities_for('agent'),       [qw(propose recommend view)], 'agent proposes and recommends';
  is_deeply capabilities_for('admin'), [qw(classify curate infra propose recommend review upload_ephemeral view)],
    'admin is curator + infra';
  is_deeply capabilities_for('lawyer'),
    [qw(classify curate propose recommend review review_lawyer upload_ephemeral view)],
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
  is_deeply roles_with_capability('infra'),            ['admin'],                  'infra is admin only';
  is_deeply roles_with_capability('review_lawyer'),    ['lawyer'],                 'review_lawyer is lawyer only';
  is_deeply roles_with_capability('curate'),           [qw(admin lawyer)],         'curate is admin + lawyer';
  is_deeply roles_with_capability('review'),           [qw(admin lawyer manager)], 'review adds manager';
  is_deeply roles_with_capability('propose'),          [qw(admin agent contributor lawyer)], 'propose adds contributor';
  is_deeply roles_with_capability('recommend'),        [qw(admin agent lawyer manager)],     'recommend adds agent';
  is_deeply roles_with_capability('classify'),         [qw(admin classifier lawyer)],        'classify adds classifier';
  is_deeply roles_with_capability('upload_ephemeral'), [qw(admin lawyer uploader)], 'upload_ephemeral adds uploader';
};

subtest 'union and helpers' => sub {
  is_deeply capabilities_for(qw(admin lawyer)),
    [qw(classify curate infra propose recommend review review_lawyer upload_ephemeral view)],
    'a user with both roles gets the union';
  ok role_has_capability('lawyer', 'review_lawyer'), 'lawyer has review_lawyer';
  ok !role_has_capability('admin', 'review_lawyer'), 'admin does not have review_lawyer';
  is_deeply capabilities_for('bot'), [], 'unknown/internal role grants no web capabilities';
  is_deeply all_roles,               [qw(admin agent classifier contributor lawyer manager uploader user)], 'all roles';
};

subtest 'bot accounts and people never share roles' => sub {
  is role_conflict('agent', 'user'),           undef,    'agent next to the default role';
  is role_conflict('user', 'agent'),           undef,    'default role next to agent';
  is role_conflict('agent', 'user', 'lawyer'), 'lawyer', 'agent on a person';
  is role_conflict('lawyer', 'user', 'agent'), 'agent',  'a person role on a bot account';
  is role_conflict('admin', 'user', 'lawyer'), undef,    'people roles combine';
  is role_conflict('agent', 'agent'),          undef,    'adding agent twice';
};

done_testing;
