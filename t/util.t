use Mojo::Base -strict;

use Test::More;
use Cavil::Util 'buckets';

is_deeply buckets([1 .. 10], 3), [[1, 2, 3, 4], [5, 6, 7, 8], [9, 10]],
  'right buckets';
is_deeply buckets([1 .. 10], 4), [[1, 2, 3, 4, 5], [6, 7, 8, 9, 10]],
  'right buckets';

done_testing;
