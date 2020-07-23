# Copyright (C) 2018-2020 SUSE LLC
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, see <http://www.gnu.org/licenses/>.

package Cavil::Test;
use Mojo::Base -base;

use Mojo::File qw(tempdir);
use Mojo::Pg;
use Mojo::URL;
use Mojo::Util qw(scope_guard);

sub new {
  my ($class, %options) = @_;

  # Database
  my $self = $class->SUPER::new(options => \%options);
  $self->{pg}       = Mojo::Pg->new($options{online});
  $self->{db_guard} = $self->_prepare_db($options{schema});

  # Checkout dir
  $self->{checkout_dir} = tempdir;

  return $self;
}

sub checkout_dir { shift->{checkout_dir} }

sub default_config {
  my $self = shift;
  return {
    secrets                => ['just_a_test'],
    checkout_dir           => $self->checkout_dir,
    tokens                 => ['test_token'],
    pg                     => $self->postgres_url,
    acceptable_risk        => 3,
    index_bucket_average   => 100,
    cleanup_bucket_average => 50,
    min_files_short_report => 20,
    max_email_url_size     => 26,
    max_task_memory        => 5_000_000_000,
    max_worker_rss         => 100000,
    max_expanded_files     => 100
  };
}

sub postgres_url {
  my $self = shift;
  return Mojo::URL->new($self->{options}{online})->query([search_path => $self->{options}{schema}])->to_unsafe_string;
}

sub _prepare_db {
  my ($self, $name) = @_;

  # Isolate tests
  my $pg = $self->{pg};
  $pg->db->query("drop schema if exists $name cascade");
  $pg->db->query("create schema $name");

  # Clean up once we are done
  return scope_guard sub { $pg->db->query("drop schema $name cascade") };
}

1;
