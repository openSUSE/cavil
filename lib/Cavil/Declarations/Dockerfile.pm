# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package Cavil::Declarations::Dockerfile;
use Mojo::Base -base, -signatures;

use Cavil::Util qw(legal_review_notices);

# Plain "Dockerfile", multibuild flavors like "Dockerfile.driver-550", and named "foo.Dockerfile"
sub file   ($self) {qr{(?:^|/)(?:Dockerfile(?:\.[^/]+)?|[^/]+\.Dockerfile)$}}
sub format ($self) {'dockerfile'}

sub parse ($self, $file) {
  my $content = $file->slurp;
  my $info    = {notices => legal_review_notices($content)};
  ($info->{license}) = $content =~ /^\s*#\s*SPDX-License-Identifier\s*:\s*(.+)$/m;
  ($info->{version}) = $content =~ /org\.opencontainers\.image\.version="([^"]+)"/;
  ($info->{summary}) = $content =~ /org\.opencontainers\.image\.description="([^"]+)"/;
  return $info;
}

1;
