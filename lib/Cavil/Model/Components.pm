# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package Cavil::Model::Components;
use Mojo::Base -base, -signatures;

use Cavil::Checkout;
use Cavil::Components::Detector::NPM;

has [qw(app log pg)];
has detectors => sub ($self) {
  my $log = $self->log;
  return [Cavil::Components::Detector::NPM->new(log => $log)];
};

sub detect_for_package ($self, $id) {
  my $app  = $self->app;
  my $pkgs = $app->packages;

  my $dir      = $pkgs->pkg_checkout_dir($id);
  my $unpacked = $dir->child('.unpacked');
  my $checkout = Cavil::Checkout->new($dir);

  my @rows;
  for my $entry (@{$checkout->unpacked_files}) {
    my ($rel_path) = @$entry;
    for my $detector (@{$self->detectors}) {
      next unless $detector->matches_manifest($rel_path);
      my $abs_path = $unpacked->child($rel_path)->to_string;
      next unless -e $abs_path;

      my $components = eval { $detector->detect($abs_path, $unpacked, $rel_path) // [] };
      if (my $err = $@) {
        $self->log->warn("[components] Detector @{[ref $detector]} died on $rel_path: $err");
        next;
      }

      my $ecosystem = $detector->ecosystem;
      for my $component (@$components) {
        push @rows, {%$component, ecosystem => $ecosystem, manifest_path => $rel_path};
      }
    }
  }

  my $count = $self->_add($id, \@rows);
  $self->log->info("[$id] Detected $count vendored components");
  return $count;
}

sub purl_for ($self, $component) {
  for my $detector (@{$self->detectors}) {
    return $detector->purl($component) if $detector->ecosystem eq $component->{ecosystem};
  }
  return undef;
}

sub clear ($self, $pkg_id) {
  return $self->pg->db->delete('bot_package_components', {package => $pkg_id})->rows;
}

sub for_package ($self, $pkg_id, $options = {}) {
  my $where = 'WHERE package = ?';
  $where .= ' AND present = true' if $options->{present_only};
  return $self->pg->db->query(
    "SELECT id, ecosystem, manifest_path, name, version, license, source_url, checksum,
            is_dev, present, relation
       FROM bot_package_components
       $where
      ORDER BY ecosystem, name, version, id", $pkg_id
  )->hashes->to_array;
}

sub _add ($self, $pkg_id, $rows) {
  my $db = $self->pg->db;
  my $tx = $db->begin;
  $db->delete('bot_package_components', {package => $pkg_id});
  for my $row (@$rows) {
    $db->insert(
      'bot_package_components',
      {
        package       => $pkg_id,
        ecosystem     => $row->{ecosystem},
        manifest_path => $row->{manifest_path},
        name          => $row->{name},
        version       => $row->{version},
        license       => $row->{license},
        source_url    => $row->{source_url},
        checksum      => $row->{checksum},
        is_dev        => $row->{is_dev}  ? 1 : 0,
        present       => $row->{present} ? 1 : 0,
        relation      => $row->{relation} // 'CONTAINS'
      }
    );
  }
  $tx->commit;
  return scalar @$rows;
}

1;
