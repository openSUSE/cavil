# Copyright (C) 2018 SUSE Linux GmbH
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

package Cavil::OBS;
use Mojo::Base -base, -signatures;

use Carp qw(croak);
use Digest::MD5;
use Mojo::File qw(path);
use Mojo::UserAgent;
use Mojo::URL;
use Cavil::Util qw(obs_ssh_auth);

has config => sub { {} };
has ua     => sub {
  my $ua = Mojo::UserAgent->new(inactivity_timeout => 600);
  $ua->on(
    start => sub ($ua, $tx) {
      $tx->res->max_message_size(10737418240);

      # Work around misconfigured IBS reverse proxy servers that send
      # "Content-Encoding: gzip" without being asked to
      $tx->req->headers->remove('Accept-Encoding');
      $tx->res->content->auto_decompress(0);
    }
  );
  return $ua;
};

sub check_for_embargo ($self, $api, $request) {
  my $host = _url($api)->host;
  return 0 unless my $config = $self->config->{$host};
  return 0 unless $config->{embargoed_bugs};

  my $bugrefs = $self->get_bugrefs_for_request($api, $request);
  return 0 unless @$bugrefs;

  my $embargoed_bugrefs = $self->get_embargoed_bugrefs($api);
  my %enbargoed         = map { $_ => 1 } @$embargoed_bugrefs;
  for my $bugref (@$bugrefs) {
    return 1 if $enbargoed{$bugref};
  }

  return 0;
}

sub get_bugrefs_for_request ($self, $api, $request) {
  my $url = _url($api, 'request', $request)
    ->query({cmd => 'diff', view => 'xml', withissues => 1, withdescriptionissues => 1});
  my $res  = $self->_request($url, 'POST');
  my $code = $res->code;
  return [] if $code == 404;
  croak "$url: " . $code unless $res->is_success;

  my $dom     = $res->dom;
  my $bugrefs = {};
  for my $issue ($dom->find('issues > issue[label]')->each) {
    my $label = $issue->{label};
    $bugrefs->{$label}++;

    # Labels in SMASH and IBS can be inconsistent with "bnc#" and "bsc#" (so we generate both)
    $bugrefs->{"bnc#$1"}++ if $label =~ /^bsc#(\d+)$/;
  }

  return [sort keys %$bugrefs];
}

sub get_embargoed_bugrefs ($self, $api) {
  my $ua = $self->ua;

  my $host = _url($api)->host;
  die "Missing configuration for OBS instance: $host" unless my $config         = $self->config->{$host};
  return []                                           unless my $embargoed_bugs = $config->{embargoed_bugs};

  my $bugs    = $ua->get($embargoed_bugs)->result->json;
  my $bugrefs = {};
  for my $bug (@$bugs) {
    $bugrefs->{$bug->{bug}{name}}++;
    for my $cve (@{$bug->{cves}}) {
      $bugrefs->{$cve->{name}}++;
    }
  }

  return [sort keys %$bugrefs];
}

sub download_source ($self, $api, $project, $pkg, $dir, $options = {}) {
  $dir = path($dir)->make_path;

  # List files
  my $url = _url($api, 'source', $project, $pkg)->query(expand => 1);
  $url->query([rev => $options->{rev}]) if defined $options->{rev};
  my $res = $self->_request($url);
  croak "$url: " . $res->code unless $res->is_success;
  my $dom    = $res->dom;
  my $srcmd5 = $dom->at('directory')->{srcmd5};
  my @files  = $dom->find('entry')->map('attr')->each;

  # Download files
  for my $file (@files) {

    # We've actually seen this in IBS (usually a checksum mismatch)
    next if $file->{name} eq '_meta';

    my $url = _url($api, 'source', $project, $pkg, $file->{name});
    $url->query([expand => 1, rev => $srcmd5]);
    my $res = $self->_request($url);
    croak "$url: " . $res->code unless $res->is_success;
    my $target = $dir->child($file->{name});
    $res->content->asset->move_to($target);
    my $md5 = _md5($target);
    croak qq/$url: Corrupted file "$file->{name}": checksum $md5 != $file->{md5}/ unless $md5 eq $file->{md5};
  }
}

sub package_info ($self, $api, $project, $pkg, $options = {}) {
  my $url = _url($api, 'source', $project, $pkg)->query(view => 'info');
  $url->query([rev => $options->{rev}]) if defined $options->{rev};
  my $res = $self->_request($url);
  croak "$url: " . $res->code unless $res->is_success;

  my $source = $res->dom->at('sourceinfo');
  my $info   = {srcmd5 => $source->{srcmd5}, verifymd5 => $source->{verifymd5}, package => $pkg};

  # Find the deepest link
  my $linfo = $self->_find_link_target($api, $project, $pkg, $options->{rev} || $source->{srcmd5});
  $info->{package} = $linfo->{package} if $linfo;
  return $info;
}

sub _find_link_target ($self, $api, $project, $pkg, $lrev) {
  my $url   = _url($api, 'source', $project, $pkg);
  my $query = {expand => 1};
  $query->{rev} = $lrev if defined $lrev;
  $url->query($query);
  my $res = $self->_request($url);
  return undef unless $res->is_success;

  # Check if we're on track
  my $match = grep { $_->{name} eq "$pkg.spec" } $res->dom->find('entry')->map('attr')->each;

  if (my $link = $res->dom->at('linkinfo')) {
    my $linfo = $self->_find_link_target($api, $link->{project}, $link->{package}, $link->{srcmd5});
    if ($linfo) {

      # If the sub package has no matching spec file, we drop it
      return $linfo unless $match && !$linfo->{match};
    }
  }
  $url = _url($api, 'source', $project, $pkg, '_meta');
  $res = $self->_request($url);

  # This is severe as we already checked the sources
  croak "$url: " . $res->code unless $res->is_success;

  my %linfo = (project => $project, package => $pkg, lrev => $lrev, match => $match);
  return \%linfo unless my $rn = $res->dom->at('releasename');
  return {%linfo, package => $rn->text};
}

sub _md5 ($file) {
  my $md5 = Digest::MD5->new;
  $md5->addfile(path($file)->open('r'));
  return $md5->hexdigest;
}

sub _request ($self, $url, $method = 'GET') {
  my $ua = $self->ua;

  my $host = $url->host;
  die "Missing configuration for OBS instance: $host" unless my $config = $self->config->{$host};
  die "Missing user for OBS instance: $host"          unless my $user   = $config->{user};

  # "api.suse.de" needs ssh authentication
  my $tx;
  if (my $ssh_key = $config->{ssh_key}) {
    $tx = $ua->start($ua->build_tx($method => $url));
    my $res = $tx->res;
    $tx = $ua->start(
      $ua->build_tx(
        $method => $url => {Authorization => obs_ssh_auth($res->headers->www_authenticate, $user, $ssh_key)}
      )
    ) if $res->code == 401;
  }

  # All other instances should use basic authentication
  else {
    die "Missing password for OBS instance: $host" unless my $password = $config->{password};
    $tx = $ua->start($ua->build_tx($method => $url->userinfo("$user:$password")));
  }

  return $tx->result;
}

sub _url ($api, @path) {
  my $url  = Mojo::URL->new($api);
  my $path = $url->path->leading_slash(1);
  push @{$path->parts}, @path;
  return $url;
}

1;
