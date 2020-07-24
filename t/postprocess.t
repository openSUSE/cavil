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

done_testing;
