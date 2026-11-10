# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package Cavil::Model::Settings;
use Mojo::Base -base, -signatures;

use Cavil::Model::AuditLog qw(audit_event);
use Mojo::JSON             qw(encode_json);

# The only place defaults exist, the table holds overrides. A stored value is checked again on every read, because
# falling back to the default could be looser than what an admin chose.
my %SETTINGS = (
  auto_accept         => {default => 1,                                                           check => \&_bool},
  acceptable_risk     => {default => 4,                                                           check => \&_risk},
  auto_accept_risk    => {default => 2,                                                           check => \&_risk},
  acceptable_packages => {default => [qw(000product 000release-packages 000package-groups)],      check => \&_names},
  separate_packages   => {default => [],                                                          check => \&_names},
  acceptable_files    => {default => [qw(_aggregate _scmsync.obsinfo .gitattributes .gitignore)], check => \&_files},
  sbom_creator_name   => {default => '',                                                          check => \&_line},
  sbom_creator_email  => {default => '',                                                          check => \&_email},
  sbom_creator_url    => {default => '',                                                          check => \&_url},
  days_to_keep_orphaned_packages           => {default => 60, check => _count(1, 3650)},
  days_to_keep_orphaned_duplicate_packages => {default => 7,  check => _count(1, 3650)},
  hours_to_keep_ephemeral_packages         => {default => 24, check => _count(1, 8760)}
);

has 'pg';

sub defaults ($self) {
  return {map { $_ => _default($_) } keys %SETTINGS};
}

sub get ($self) { return $self->_effective($self->_stored($self->pg->db)) }

# The "Never group these packages" names as a set, read with the caller's handle
sub separate_in ($db) {
  my $row   = $db->select('settings', ['value'], {name => 'separate_packages'})->expand->hash;
  my $names = $row ? _checked('separate_packages', $row->{value}) : _default('separate_packages');
  return {map { $_ => 1 } @$names};
}

sub summary ($self, @keys) {
  my $stored    = $self->_stored($self->pg->db);
  my $effective = $self->_effective($stored);
  my $defaults  = $self->defaults;
  return {
    values   => {map { $_ => $effective->{$_} } @keys},
    defaults => {map { $_ => $defaults->{$_} } @keys},
    custom   => [sort grep { exists $stored->{$_} } @keys]
  };
}

sub update ($self, $login, $values, $reset = []) {
  my %errors = map { $_ => 'Unknown setting' } grep { !$SETTINGS{$_} } keys %$values, @$reset;
  return {errors => \%errors} if %errors;

  my $db = $self->pg->db;
  my $tx = $db->begin;

  # A default has no row to lock
  $db->query('SELECT pg_advisory_xact_lock(?)', 0x5e771465);
  my $stored = $self->_stored($db);
  my $old    = $self->_effective($stored);

  my %new = %$old;
  for my $key (keys %$values) {
    my ($value, $error) = $SETTINGS{$key}{check}->($values->{$key});
    defined $error ? ($errors{$key} = $error) : ($new{$key} = $value);
  }
  $new{$_} = _default($_) for @$reset;
  $errors{auto_accept_risk} = 'Cannot be higher than the risk for packages reviewed before'
    if !%errors && $new{auto_accept_risk} > $new{acceptable_risk};
  $errors{days_to_keep_orphaned_duplicate_packages} = 'Cannot be longer than finished reviews are kept'
    if !%errors && $new{days_to_keep_orphaned_duplicate_packages} > $new{days_to_keep_orphaned_packages};
  return {errors => \%errors} if %errors;

  $db->query('INSERT INTO settings (name, value) VALUES (?, ?) ON CONFLICT (name) DO UPDATE SET value = EXCLUDED.value',
    $_, {json => $new{$_}})
    for keys %$values;
  my @reset = grep { exists $stored->{$_} } @$reset;
  $db->delete('settings', {name => \@reset}) if @reset;

  my %changes
    = map { $_ => [$old->{$_}, $new{$_}] } grep { encode_json($old->{$_}) ne encode_json($new{$_}) } keys %new;
  if (%changes || @reset) {
    audit_event(
      $db,
      type  => 'settings.changed',
      actor => $db->select('bot_users', 'id', {login => $login})->hash->{id},
      data  => {changes => \%changes, @reset ? (reset => [sort @reset]) : ()}
    );
  }
  $tx->commit;

  return {old => $old, new => \%new};
}

sub value ($self, $key) {
  die "Unknown setting: $key\n" unless $SETTINGS{$key};
  my $row = $self->pg->db->select('settings', ['value'], {name => $key})->expand->hash;
  return $row ? _checked($key, $row->{value}) : _default($key);
}

sub _bool ($value) {
  $value = 0 + $value if ref $value eq 'JSON::PP::Boolean';
  return defined $value && !ref $value && $value =~ /^[01]$/ ? 0 + $value : (undef, 'Must be on or off');
}

sub _checked ($key, $value) {
  my ($checked, $error) = $SETTINGS{$key}{check}->($value);
  die "Stored setting $key is invalid: $error\n" if defined $error;
  return $checked;
}

sub _count ($min, $max) {
  return sub ($value) {
    return
         defined $value
      && !ref $value
      && $value =~ /^[0-9]{1,9}$/
      && $value >= $min
      && $value <= $max ? 0 + $value : (undef, "Must be a whole number from $min to $max");
  };
}

sub _default ($key) {
  my $default = $SETTINGS{$key}{default};
  return ref $default ? [@$default] : $default;
}

sub _effective ($self, $stored) {
  return {map { $_ => exists $stored->{$_} ? _checked($_, $stored->{$_}) : _default($_) } keys %SETTINGS};
}

sub _email ($value) {
  my ($line, $error) = _line($value);
  return (undef, $error) if defined $error;
  return length $line && $line !~ /^[^@\s]+@[^@\s]+\.[^@\s]+$/ ? (undef, 'Must be an email address') : $line;
}

sub _line ($value) {
  return (undef, 'Must be a single line of at most 200 characters')
    unless defined $value && !ref $value && $value !~ /[\r\n]/ && length $value <= 200;
  return $value =~ s/^\s+|\s+$//gr;
}

sub _files ($value) { _list($value, 'file names', qr{[\s/]}, 'File names cannot contain spaces or slashes') }

sub _list ($value, $what, $bad, $error) {
  return (undef, "Must be a list of $what") unless ref $value eq 'ARRAY' && !grep { !defined || ref } @$value;
  my %seen;
  my @names = grep { length && !$seen{$_}++ } map {s/^\s+|\s+$//gr} @$value;
  return grep({ $_ =~ $bad } @names) ? (undef, $error) : \@names;
}

sub _names ($value) { _list($value, 'package names', qr/\s/, 'Package names cannot contain spaces') }

sub _risk ($value) {
  return defined $value && !ref $value && $value =~ /^\d$/ ? 0 + $value : (undef, 'Must be a risk level from 0 to 9');
}

sub _url ($value) {
  my ($line, $error) = _line($value);
  return (undef, $error) if defined $error;
  return length $line && $line !~ m{^https?://\S+$} ? (undef, 'Must be a web address starting with https://') : $line;
}

sub _stored ($self, $db) {
  my $rows = $db->select('settings', ['name', 'value'], {name => [keys %SETTINGS]})->expand->hashes;
  return {map { $_->{name} => $_->{value} } @$rows};
}

1;
