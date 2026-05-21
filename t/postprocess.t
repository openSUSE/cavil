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

use Mojo::Base -strict;

use Test::More;
use Mojo::File qw(path tempdir);
use Mojo::JSON 'decode_json';
use Cavil::Checkout;

my $dir = path(__FILE__)->dirname->child('legal-bot');

sub temp_copy {
  my $from   = $dir->child(@_);
  my $target = tempdir;
  $_->copy_to($target->child($_->basename)) for $from->list->each;
  return $target;
}

subtest 'gnome-icon-theme' => sub {
  my $pwll      = temp_copy('package-with-long-lines', '677dca225770d164778fd08123af89e960b8bd0d');
  my $processor = Cavil::PostProcess->new({destdir => $pwll, unpacked => {'README.md' => {mime => 'text/plain'}}});
  $processor->postprocess;
  is_deeply $processor->hash, {destdir => $pwll, unpacked => {'README.processed.md' => {mime => 'text/plain'}}},
    'maxed';

  is $pwll->child('README.processed.md')->slurp, $pwll->child('README.shortened')->slurp, 'Correctly split';

  my $pwt = temp_copy('package-with-translations', '96d268b759eb1e18a63a95a2c622ab47d5c34f23');
  $processor = Cavil::PostProcess->new(
    {destdir => $pwt, unpacked => {'test.po' => {mime => 'text/x-po'}, 'package.spec' => {mime => 'text/plain'}}});
  $processor->postprocess;
  is_deeply $processor->hash,
    {
    destdir  => $pwt,
    unpacked => {'test.processed.po' => {mime => 'text/x-po'}, 'package.processed.spec' => {mime => 'text/plain'},}
    },
    'striped';

  is $pwt->child('test.processed.po')->slurp, $pwt->child('test.stripped')->slurp, 'Correctly stripped msgid';
  is $pwt->child('package.processed.spec')->slurp, $pwt->child('package.stripped')->slurp,
    'Correctly stripped spec file';
};

subtest 'structured manifests are not line-split (would corrupt JSON/TOML/YAML)' => sub {
  my $tmp = tempdir;

  # Build a package-lock.json with a string value long enough to trigger the
  # post-processor's line-splitting if it ran. Splitting inside a JSON string
  # literal injects a raw newline that JSON parsers reject.
  my $long_integrity = 'sha512-' . ('A' x 800) . '==';
  $tmp->child('package-lock.json')->spew(<<"JSON");
{
  "lockfileVersion": 3,
  "packages": {
    "": {"name": "demo", "version": "1.0.0"},
    "node_modules/leftpad": {
      "version": "1.3.0",
      "integrity": "$long_integrity",
      "license": "MIT"
    }
  }
}
JSON

  # Sanity check: this file would trigger line-splitting if it weren't a manifest
  ok((-s $tmp->child('package-lock.json')) > 800, 'fixture has long-line content');
  my $before = $tmp->child('package-lock.json')->slurp;

  my $processor
    = Cavil::PostProcess->new({destdir => $tmp, unpacked => {'package-lock.json' => {mime => 'text/plain'}}});
  $processor->postprocess;

  is_deeply $processor->hash, {destdir => $tmp, unpacked => {'package-lock.json' => {mime => 'text/plain'}}},
    'manifest still references the original .json filename';
  ok !-e $tmp->child('package-lock.processed.json'), 'no .processed.json sibling was created';
  is $tmp->child('package-lock.json')->slurp, $before, 'file bytes are unchanged';

  my $parsed = eval { decode_json($tmp->child('package-lock.json')->slurp) };
  is $parsed->{packages}{'node_modules/leftpad'}{version}, '1.3.0', 'JSON still parses end-to-end';

  # Spot-check the other extensions in the skip list
  for my $ext (qw(toml yaml yml lock)) {
    my $sub  = tempdir;
    my $name = "Cargo.$ext";
    $sub->child($name)->spew(('x' x 5000) . "\n");
    my $p = Cavil::PostProcess->new({destdir => $sub, unpacked => {$name => {mime => 'text/plain'}}});
    $p->postprocess;
    is_deeply $p->hash->{unpacked}, {$name => {mime => 'text/plain'}}, "$ext also skipped";
  }
};

done_testing;
