# Copyright (C) 2018-2024 SUSE LLC
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

use Mojo::Base -strict, -signatures;

use FindBin;
use lib "$FindBin::Bin/lib";

use Test::More;
use Test::Mojo;
use Cavil::Test;
use Mojo::File qw(tempdir tempfile);
use Mojolicious::Lite;
use Cavil::OBS;

plan skip_all => 'set TEST_ONLINE to enable this test' unless $ENV{TEST_ONLINE};

app->log->level('error');

app->routes->add_condition(
  query => sub {
    my ($route, $c, $captures, $hash) = @_;

    for my $key (keys %$hash) {
      my $values = ref $hash->{$key} ? $hash->{$key} : [$hash->{$key}];
      my $param  = $c->req->url->query->param($key);
      return undef unless defined $param && grep { $param eq $_ } @$values;
    }

    return 1;
  }
);

get '/source/:project/kernel-default' => [project => ['openSUSE:Factory']] => (query => {view => 'info'}) =>
  {text => <<'EOF'};
<sourceinfo package="kernel-default" rev="10" vrev="1"
srcmd5="74ee00bc30bdaf23acbfba25a893b52a"
lsrcmd5="afd761dadb5281cdc26c869324b2ecd2"
verifymd5="bb19066400b2b60e2310b45f10d12f56">
  <filename>kernel-default.spec</filename>
  <linked project="openSUSE:Factory" package="kernel-source" />
</sourceinfo>
EOF

get '/source/:project/kernel-default'                                 => [project => ['openSUSE:Factory']] =>
  (query => {expand => 1, rev => '74ee00bc30bdaf23acbfba25a893b52a'}) => {text => <<'EOF'};
<directory name="kernel-default" rev="dde505c17d7e2d6b146c2a823f8b3224" vrev="1"
  srcmd5="dde505c17d7e2d6b146c2a823f8b3224">
  <linkinfo project="openSUSE:Factory" package="kernel-source"
    srcmd5="75a7d6524faa9d48cd415a62feadea8e"
    lsrcmd5="afd761dadb5281cdc26c869324b2ecd2" />
  <entry name="README.KSYMS" md5="c3f38df11cd76c6f6fb24c7c1fab880f" size="345"
    mtime="1238551590" />
  <entry name="README.PATCH-POLICY.SUSE" md5="2ecf3527d0a5f5dd4f32d89969e0c488"
    size="13708" mtime="1392274851" />
</directory>
EOF

get '/source/:project/kernel-source'                                  => [project => ['openSUSE:Factory']] =>
  (query => {expand => 1, rev => '75a7d6524faa9d48cd415a62feadea8e'}) => {text => <<'EOF'};
<directory name="kernel-source" rev="75a7d6524faa9d48cd415a62feadea8e"
  srcmd5="75a7d6524faa9d48cd415a62feadea8e">
  <entry name="README.KSYMS" md5="c3f38df11cd76c6f6fb24c7c1fab880f" size="345"
    mtime="1238551590" />
  <entry name="README.PATCH-POLICY.SUSE" md5="2ecf3527d0a5f5dd4f32d89969e0c488"
    size="13708" mtime="1392274851" />
  <entry name="README.SUSE" md5="eb4947a5aded7ad16025bf036cfa468b" size="17012"
    mtime="1406590067" />
</directory>
EOF

get '/source/:project/kernel-source'                     => [project => ['openSUSE:Factory']] =>
  (query => {rev => 'bb19066400b2b60e2310b45f10d12f56'}) => {text => <<'EOF'};
<directory name="kernel-source" rev="bb19066400b2b60e2310b45f10d12f56"
  srcmd5="bb19066400b2b60e2310b45f10d12f56">
  <entry name="kernel-source.spec" md5="3291debddffcf461fba5d9679099e0eb"
    size="8600" mtime="1485422138" />
</directory>
EOF

get '/source/:project/kernel-source/_meta' => [project => ['openSUSE:Factory']] => {text => <<'EOF'};
<package name="kernel-source" project="openSUSE:Factory">
  <title>The Linux Kernel Sources</title>
  <devel project="Kernel:stable" package="kernel-source" />
</package>
EOF

get '/source/:project/perl-Mojolicious'   => [project => ['openSUSE:Factory']] =>
  (query => {view => 'info', rev => '3'}) => {text => <<'EOF'};
<sourceinfo package="perl-Mojolicious" rev="3" vrev="1"
  srcmd5="09f3db66fc4df14f1160b01ceb4b3e73"
  verifymd5="09f3db66fc4df14f1160b01ceb4b3e73">
  <filename>perl-Mojolicious.spec</filename>
</sourceinfo>
EOF

get '/source/:project/perl-Mojolicious/_meta' => [project => ['openSUSE:Factory']] => {text => <<'EOF'};
<package name="perl-Mojolicious" project="openSUSE:Factory">
  <title>The Web In A Box!</title>
  <devel project="devel:languages:perl" package="perl-Mojolicious" />
</package>
EOF

get '/source/:project/perl-Mojolicious' => [project => ['home:kraih']] => (query => {view => 'info'}) =>
  {text => <<'EOF'};
<sourceinfo package="perl-Mojolicious" rev="9199eca9ec0fa5cffe4c3a6cb99a8093"
vrev="140"
srcmd5="0e5c2d1c0c4178869cf7fb82482b9c52"
lsrcmd5="d277e095ec45b64835452d5e87d2d349"
verifymd5="bb19066400b2b60e2310b45f10d12f56">
  <filename>perl-Mojolicious.spec</filename>
</sourceinfo>
EOF

get '/source/:project/perl-Mojolicious/_meta' => [project => ['home:kraih']] => {text => <<'EOF'};
<package name="postgresql-plr" project="server:database:postgresql">
  <title>Mojolicious</title>
  <description>
    Real-time web framework
  </description>
</package>
EOF

get '/source/:project/perl-Mojolicious'                                    => [project => ['home:kraih']] =>
  (query => {expand => 1, rev => [1, '0e5c2d1c0c4178869cf7fb82482b9c52']}) => {text => <<'EOF'};
<directory name="perl-Mojolicious" rev="9199eca9ec0fa5cffe4c3a6cb99a8093"
  vrev="140" srcmd5="9199eca9ec0fa5cffe4c3a6cb99a8093">
  <linkinfo project="devel:languages:perl" package="perl-Mojolicious"
    srcmd5="0e5c2d1c0c4178869cf7fb82482b9c52"
    lsrcmd5="d277e095ec45b64835452d5e87d2d349" />
  <serviceinfo code="succeeded" lsrcmd5="9ed57c4451a8074594a106af43604341" />
  <entry name="perl-Mojo#licious.changes" md5="64dc1045d41bc24d40e196a965f6e253"
    size="76628" mtime="1485497156" />
  <entry name="perl-Mojolicious.spec" md5="aca567897d3201d004b48cdface4ea44"
    size="2405" mtime="1485497157" />
</directory>
EOF

# explicit 404
get '/source/:project/perl-Mojolicious' => [project => ['openSUSE:Factory']] =>
  (query => {view => 'info', rev => 4}) => {text => '', status => 404};

get '/source/:project/perl-Mojolicious/perl-Mojolicious.spec' => [project => ['home:kraih']] =>
  (query => {rev => '9199eca9ec0fa5cffe4c3a6cb99a8093'})      => {text => 'Mojolicious spec!'};

get '/source/:project/perl-Mojolicious/:special'         => [project => ['home:kraih']]                =>
  (query => {rev => '9199eca9ec0fa5cffe4c3a6cb99a8093'}) => [special => ['perl-Mojo#licious.changes']] =>
  {text => 'Mojolicious changes!'};

get '/source/:project/perl-WrongChecksum' => [project => ['home:kraih']] => (query => {expand => 1, rev => 1}) =>
  {text => <<'EOF'};
<directory name="perl-WrongChecksum" rev="9199eca9ec0fa5cffe4c3a6cb99a8093"
  vrev="140" srcmd5="9199eca9ec0fa5cffe4c3a6cb99a8093">
  <linkinfo project="devel:languages:perl" package="perl-WrongChecksum"
    srcmd5="0e5c2d1c0c4178869cf7fb82482b9c52"
    lsrcmd5="d277e095ec45b64835452d5e87d2d349" />
  <serviceinfo code="succeeded" lsrcmd5="9ed57c4451a8074594a106af43604341" />
  <entry name="perl-WrongChecksum.changes"
    md5="d425747e9ffddb65ba09ee5616b54803" size="76628" mtime="1485497156" />
</directory>
EOF

get '/source/:project/perl-WrongChecksum/perl-WrongChecksum.changes' => [project => ['home:kraih']] =>
  (query => {rev => '9199eca9ec0fa5cffe4c3a6cb99a8093'})             => {text => 'Wrong checksum changes!'};

get '/source/:project/perl-Mojo-SQLite' => (query => {expand => 1}) => [project => ['home:kraih']] => {text => <<'EOF'};
<directory name="perl-Mojo-SQLite" rev="51d642346cc9e5f57c43463dd0b1dad9"
  vrev="5" srcmd5="51d642346cc9e5f57c43463dd0b1dad9">
  <linkinfo project="devel:languages:perl" package="perl-Mojo-SQLite"
    srcmd5="d5671d9368fc6116338daae9d78dffc1"
    lsrcmd5="c1561b1edefaf726ed99570c13087dc4" />
  <serviceinfo code="succeeded" lsrcmd5="e64bb2dfb509a3c64c7d48374278e80c" />
  <entry name="Mojo-SQLite-1.004.tar.gz" md5="81bd2669af1129737fb7570e3b063117"
    size="41365" mtime="1484719569" />
  <entry name="cpanspec.yml" md5="92d12bcb54f9827ab103cbe18087544d" size="669"
    mtime="1479278950" />
  <entry name="perl-Mojo-SQLite.changes" md5="5bf03afeee47f04fc1dd054b43ceed73"
    size="1682" mtime="1484719569" />
  <entry name="perl-Mojo-SQLite.spec" md5="c4d5d7f3bd0d831c6ca7acca54329bcb"
    size="5210" mtime="1484719569" />
</directory>
EOF

get '/source/:project/python-monascaclient' => [project => ['Cloud:OpenStack:Factory']] =>
  (query => {view => 'info', rev => 4})     => {text => <<'EOF'};
<sourceinfo package="python-monascaclient" rev="4" vrev="4"
  srcmd5="d023edaef04687af8d487ff4e2eda5f7"
  lsrcmd5="4de5b31e259161d9368c9a3c8b6ccecd"
    verifymd5="34d69b093c93614c829c06c075688463">
  <filename>python-monascaclient.spec</filename>
  <linked project="openSUSE:Factory" package="python-monascaclient" />
</sourceinfo>
EOF

get '/source/:project/python-monascaclient' => [project => ['Cloud:OpenStack:Factory']] =>
  (query => {expand => 1, rev => 4})        => {text => <<'EOF'};
<directory name="python-monascaclient" rev="d023edaef04687af8d487ff4e2eda5f7"
  vrev="4" srcmd5="d023edaef04687af8d487ff4e2eda5f7">
  <linkinfo project="openSUSE:Factory" package="python-monascaclient"
    srcmd5="d41d8cd98f00b204e9800998ecf8427e"
    baserev="d41d8cd98f00b204e9800998ecf8427e" missingok="true"
    lsrcmd5="4de5b31e259161d9368c9a3c8b6ccecd" />
  <serviceinfo code="succeeded" lsrcmd5="e702593dae9c7fda8dcffffbcc36c878" />
  <entry name="_service" md5="79e205934ea247150fd6cf43da26f495" size="709"
    mtime="1486989850" />
  <entry name="python-monascaclient-1.5.0.tar.gz"
    md5="fa704ad667b72eae31f14846e5a1b16a" size="60537" mtime="1486073611" />
  <entry name="python-monascaclient.changes"
    md5="4ed5c1b86066cc9f74a6bcdadf94157b" size="2160" mtime="1487005856" />
  <entry name="python-monascaclient.spec" md5="8106bbdf6917c65c90d8847c8b1e99b9"
    size="3363" mtime="1486742394" />
</directory>
EOF

get '/source/:project/python-monascaclient'              => [project => ['openSUSE:Factory']] =>
  (query => {rev => 'd41d8cd98f00b204e9800998ecf8427e'}) => {text => '', status => 404};

get '/source/:project/python-monascaclient/_meta' => [project => ['Cloud:OpenStack:Factory']] => {text => <<'EOF'};
<package name="python-monascaclient" project="Cloud:OpenStack:Factory">
  <title/>
  <description/>
</package>
EOF

get '/source/:project/postgresql95-plr' => [project => ['server:database:postgresql']] =>
  (query => {view => 'info', rev => 2}) => {text => <<'EOF'};
<sourceinfo package="postgresql95-plr" rev="2" vrev="30"
  srcmd5="33fd6e072853f97aa64a205090f55d5e"
  lsrcmd5="3cb5f8a6851e65e8f10270f2bbe5dac4"
  verifymd5="5e2c789dcbe65ad644652455029c1123">
  <filename>postgresql95-plr.spec</filename>
  <linked project="server:database:postgresql" package="postgresql-plr" />
</sourceinfo>
EOF

get '/source/:project/postgresql96-plr' => [project => ['server:database:postgresql']] =>
  (query => {view => 'info', rev => 2}) => {text => <<'EOF'};
<sourceinfo package="postgresql96-plr" rev="2" vrev="30"
  srcmd5="e9cb3655b11bd63d07210a161240330c"
  lsrcmd5="36b5b26094ae578303e70881a7e246b8"
  verifymd5="8c174a4cd8c85e430378d875aa77c23e">
  <filename>postgresql96-plr.spec</filename>
  <linked project="server:database:postgresql" package="postgresql-plr" />
</sourceinfo>
EOF

get '/source/:project/postgresql96-plr' => [project => ['server:database:postgresql']] =>
  (query => {rev => 2, expand => 1})    => {text => <<'EOF'};
<directory name="postgresql96-plr" rev="e9cb3655b11bd63d07210a161240330c"
  vrev="30" srcmd5="e9cb3655b11bd63d07210a161240330c">
  <linkinfo project="server:database:postgresql" package="postgresql-plr"
    srcmd5="7ee96456a79d70a12270cb1d045cca3c"
    baserev="7ee96456a79d70a12270cb1d045cca3c"
    lsrcmd5="36b5b26094ae578303e70881a7e246b8" />
  <entry name="REL8_3_0_17.tar.gz" md5="b0aa8e24ddfea33a475c1d0c43a30bf9"
    size="74017" mtime="1484155216" />
  <entry name="patch-Makefile-ldflags.patch"
    md5="59b52e35328418cd3f70ecc6d891f982" size="839" mtime="1484155216" />
  <entry name="plr-US.pdf" md5="20ba09b8fcd110109d0ea76fdbfdeed3" size="167371"
    mtime="1484155217" />
  <entry name="postgresql-plr.changes.in" md5="9c9cda58c29550a1fda86d5877536039"
    size="6250" mtime="1484415125" />
  <entry name="postgresql-plr.spec.in" md5="7453458a771dd8bfe9aefaa1e620239c"
    size="4941" mtime="1484155217" />
  <entry name="postgresql96-plr.changes" md5="9c9cda58c29550a1fda86d5877536039"
    size="6250" mtime="1484415128" />
  <entry name="postgresql96-plr.spec" md5="093e53eec85352d28a358920da1191d6"
    size="4941" mtime="1484155222" />
  <entry name="pre_checkin.sh" md5="d98c1f9801d9da71495fff4af9cbabe5" size="221"
    mtime="1484415128" />
  <entry name="readme.SUSE" md5="07c065e300e454b1adb793bf7fbe19bd" size="1847"
    mtime="1423858795" />
</directory>
EOF

get '/source/:project/postgresql95-plr' => [project => ['server:database:postgresql']] =>
  (query => {rev => 2, expand => 1})    => {text => <<'EOF'};
<directory name="postgresql95-plr" rev="33fd6e072853f97aa64a205090f55d5e"
  vrev="30" srcmd5="33fd6e072853f97aa64a205090f55d5e">
  <linkinfo project="server:database:postgresql" package="postgresql-plr"
    srcmd5="7ee96456a79d70a12270cb1d045cca3c"
    baserev="7ee96456a79d70a12270cb1d045cca3c"
    lsrcmd5="3cb5f8a6851e65e8f10270f2bbe5dac4" />
  <entry name="REL8_3_0_17.tar.gz" md5="b0aa8e24ddfea33a475c1d0c43a30bf9"
    size="74017" mtime="1484155216" />
  <entry name="patch-Makefile-ldflags.patch"
    md5="59b52e35328418cd3f70ecc6d891f982" size="839" mtime="1484155216" />
  <entry name="plr-US.pdf" md5="20ba09b8fcd110109d0ea76fdbfdeed3" size="167371"
    mtime="1484155217" />
  <entry name="postgresql-plr.changes.in" md5="9c9cda58c29550a1fda86d5877536039"
    size="6250" mtime="1484415125" />
  <entry name="postgresql-plr.spec.in" md5="7453458a771dd8bfe9aefaa1e620239c"
    size="4941" mtime="1484155217" />
  <entry name="postgresql95-plr.changes" md5="9c9cda58c29550a1fda86d5877536039"
    size="6250" mtime="1484415128" />
  <entry name="postgresql95-plr.spec" md5="d4ecdb857b7f76d02612d6fa8fdf02c4"
    size="4941" mtime="1484155221" />
  <entry name="pre_checkin.sh" md5="d98c1f9801d9da71495fff4af9cbabe5" size="221"
    mtime="1484415128" />
  <entry name="readme.SUSE" md5="07c065e300e454b1adb793bf7fbe19bd" size="1847"
    mtime="1423858795" />
</directory>
EOF

get '/source/:project/postgresql-plr'                                 => [project => ['server:database:postgresql']] =>
  (query => {expand => 1, rev => '7ee96456a79d70a12270cb1d045cca3c'}) => {text => <<'EOF'};
<directory name="postgresql-plr" rev="7ee96456a79d70a12270cb1d045cca3c"
  srcmd5="7ee96456a79d70a12270cb1d045cca3c">
  <entry name="REL8_3_0_17.tar.gz" md5="b0aa8e24ddfea33a475c1d0c43a30bf9"
    size="74017" mtime="1484155216" />
  <entry name="patch-Makefile-ldflags.patch"
    md5="59b52e35328418cd3f70ecc6d891f982" size="839" mtime="1484155216" />
  <entry name="plr-US.pdf" md5="20ba09b8fcd110109d0ea76fdbfdeed3" size="167371"
    mtime="1484155217" />
  <entry name="postgresql-plr.changes.in" md5="9c9cda58c29550a1fda86d5877536039"
    size="6250" mtime="1484415125" />
  <entry name="postgresql-plr.spec.in" md5="7453458a771dd8bfe9aefaa1e620239c"
    size="4941" mtime="1484155217" />
  <entry name="postgresql91-plr.changes" md5="9c9cda58c29550a1fda86d5877536039"
    size="6250" mtime="1484415126" />
  <entry name="postgresql91-plr.spec" md5="63ec2837d442ab598f135f6d3a21b680"
    size="4941" mtime="1484155218" />
  <entry name="postgresql92-plr.changes" md5="9c9cda58c29550a1fda86d5877536039"
    size="6250" mtime="1484415127" />
  <entry name="postgresql92-plr.spec" md5="8988283907b005e920f2cd78d33de41c"
    size="4941" mtime="1484155219" />
  <entry name="postgresql93-plr.changes" md5="9c9cda58c29550a1fda86d5877536039"
    size="6250" mtime="1484415127" />
  <entry name="postgresql93-plr.spec" md5="91837f93bcf1ce10d5e8e39bd312d8de"
    size="4941" mtime="1484155219" />
  <entry name="postgresql94-plr.changes" md5="9c9cda58c29550a1fda86d5877536039"
    size="6250" mtime="1484415127" />
  <entry name="postgresql94-plr.spec" md5="7388f6d33488a916fc0aefb129336111"
    size="4941" mtime="1484155220" />
  <entry name="postgresql95-plr.changes" md5="9c9cda58c29550a1fda86d5877536039"
    size="6250" mtime="1484415128" />
  <entry name="postgresql95-plr.spec" md5="d4ecdb857b7f76d02612d6fa8fdf02c4"
    size="4941" mtime="1484155221" />
  <entry name="postgresql96-plr.changes" md5="9c9cda58c29550a1fda86d5877536039"
    size="6250" mtime="1484415128" />
  <entry name="postgresql96-plr.spec" md5="093e53eec85352d28a358920da1191d6"
    size="4941" mtime="1484155222" />
  <entry name="pre_checkin.sh" md5="d98c1f9801d9da71495fff4af9cbabe5" size="221"
    mtime="1484415128" />
  <entry name="readme.SUSE" md5="07c065e300e454b1adb793bf7fbe19bd" size="1847"
    mtime="1423858795" />
</directory>
EOF

get '/source/:project/postgresql-plr/_meta' => [project => ['server:database:postgresql']] => {text => <<'EOF'};
<package name="postgresql-plr" project="server:database:postgresql">
  <title>PL/R - R Procedural Language for PostgreSQL</title>
  <description>
    PL/R is a loadable procedural language that enables you to write PostgreSQL
    functions
  </description>
</package>
EOF

get '/source/:project/postgresql95-plr/_meta' => [project => ['server:database:postgresql']] => {text => <<'EOF'};
<package name="postgresql95-plr" project="server:database:postgresql">
  <title>PL/R - R Procedural Language for PostgreSQL</title>
  <description>
    PL/R is a loadable procedural language that enables you to write PostgreSQL
    functions
  </description>
</package>
EOF

get '/source/:project/postgresql96-plr/_meta' => [project => ['server:database:postgresql']] => {text => <<'EOF'};
<package name="postgresql96-plr" project="server:database:postgresql">
  <title>PL/R - R Procedural Language for PostgreSQL</title>
  <description>
    PL/R is a loadable procedural language that enables you to write PostgreSQL
    functions
  </description>
</package>
EOF

post '/request/1235' => (query => {cmd => 'diff', view => 'xml', withissues => 1, withdescriptionissues => 1}) =>
  {status => 200, text => <<'EOF'};
EOF

post '/request/344036' => (query => {cmd => 'diff', view => 'xml', withissues => 1, withdescriptionissues => 1}) =>
  {status => 200, text => <<'EOF'};
<request id="344036" actions="0">
  <action type="maintenance_incident">
    <source project="SUSE:Maintenance:REQUEST:344036" package="perl-Mojolicious.SUSE_SLE-15-SP2_Update" rev="e107785743567f297d622fabab3db71c"/>
    <target project="SUSE:Maintenance" releaseproject="SUSE:SLE-15-SP2:Update"/>
    <sourcediff key="08943b6f0b415b013042f01b8c0fabdd">
      <old project="SUSE:SLE-15-SP2:Update" package="perl-Mojolicious.24434" rev="1" srcmd5="c41f992a6f5997cc30649019cb57ad78"/>
      <new project="SUSE:Maintenance:REQUEST:344036" package="perl-Mojolicious..SUSE_SLE-15-SP2_Update" rev="e107785743567f297d622fabab3db71c" srcmd5="b7451ed1d847d67fd497df8c5b0ad3b9"/>
      <files>
        <file state="changed">
          <old name="perl-Mojolicious..changes" md5="c6ca632ea4982747c36834f1873ec43d" size="136059"/>
          <new name="perl-Mojolicious..changes" md5="a845059bf4311c9379fa5892d15e05b1" size="152330"/>
          <diff lines="266">@@ -1,4 +1,265 @@
    -------------------------------------------------------------------
    +Wed Sep 03 02:01:10 UTC 2023 - tester@suse.com
    +
    +- bsc#1225312 - CVE-2024-3654 - Stuff
    </diff>
        </file>
      </files>
      <issues>
        <issue state="added" tracker="cve" name="2022-2850" label="CVE-2022-2850" url="http://cve.mitre.org/cgi-bin/cvename.cgi?name=CVE-2022-2850"/>
        <issue state="added" tracker="cve" name="2024-1062" label="CVE-2024-1062" url="http://cve.mitre.org/cgi-bin/cvename.cgi?name=CVE-2024-1062"/>
        <issue state="added" tracker="cve" name="2024-2199" label="CVE-2024-2199" url="http://cve.mitre.org/cgi-bin/cvename.cgi?name=CVE-2024-2199"/>
        <issue state="added" tracker="cve" name="2024-3657" label="CVE-2024-3657" url="http://cve.mitre.org/cgi-bin/cvename.cgi?name=CVE-2024-3657"/>
        <issue state="added" tracker="cve" name="2024-5953" label="CVE-2024-5953" url="http://cve.mitre.org/cgi-bin/cvename.cgi?name=CVE-2024-5953"/>
        <issue state="added" tracker="bnc" name="1202470" label="bsc#1202470" url="https://bugzilla.suse.com/show_bug.cgi?id=1202470"/>
        <issue state="added" tracker="bnc" name="1219836" label="bsc#1219836" url="https://bugzilla.suse.com/show_bug.cgi?id=1219836"/>
        <issue state="added" tracker="bnc" name="1225512" label="bsc#1225512" url="https://bugzilla.suse.com/show_bug.cgi?id=1225512"/>
      </issues>
    </sourcediff>
  </action>
  <action type="delete">
    <target project="SUSE:Maintenance:REQUEST:344036"/>
  </action>
  <issues>
    <issue tracker="cve" name="2024-2199" label="CVE-2024-2199" url="http://cve.mitre.org/cgi-bin/cvename.cgi?name=CVE-2024-2199"/>
    <issue tracker="cve" name="2024-3657" label="CVE-2024-3657" url="http://cve.mitre.org/cgi-bin/cvename.cgi?name=CVE-2024-3657"/>
    <issue tracker="cve" name="2024-5953" label="CVE-2024-5953" url="http://cve.mitre.org/cgi-bin/cvename.cgi?name=CVE-2024-5953"/>
    <issue tracker="bnc" name="1225512" label="bsc#1225512" url="https://bugzilla.suse.com/show_bug.cgi?id=1225512"/>
  </issues>
</request>
EOF

post '/request/1236' => (query => {cmd => 'diff', view => 'xml', withissues => 1, withdescriptionissues => 1}) =>
  {status => 200, text => <<'EOF'};
<request id="1235" actions="0">
  <action type="maintenance_incident">
    <sourcediff key="08943b6f0b415b013042f01b8c0fabdd">
      <issues>
        <issue state="added" tracker="cve" name="2024-22038" label="CVE-2024-22038" url="http://cve.mitre.org/cgi-bin/cvename.cgi?name=CVE-2024-22038"/>
      </issues>
    </sourcediff>
  </action>
</request>
EOF

post '/request/1237' => (query => {cmd => 'diff', view => 'xml', withissues => 1, withdescriptionissues => 1}) =>
  {status => 200, text => <<'EOF'};
<request id="1235" actions="0">
  <action type="maintenance_incident">
    <sourcediff key="08943b6f0b415b013042f01b8c0fabdd">
    </sourcediff>
  </action>
</request>
EOF

get '/api/embargoed-bugs' => {format => 'json', text => <<'EOF'};
[
  {
    "bug": {
      "name": "bnc#1196706",
      "url": "https://bugzilla.suse.com/show_bug.cgi?id=1196706",
      "source": "SUSE Bugzilla"
    },
    "cves": []
  },
  {
    "bug": {
      "name": "bnc#1202470",
      "url": "https://bugzilla.suse.com/show_bug.cgi?id=1202470",
      "source": "SUSE Bugzilla"
    },
    "cves":[]
  },
  {
    "bug": {
      "name": "bnc#1230469",
      "url": "https://bugzilla.suse.com/show_bug.cgi?id=1230469",
      "source":"SUSE Bugzilla"
    },
    "cves": [
      {
        "name": "CVE-2024-22038",
        "url": "http://web.nvd.nist.gov/view/vuln/detail?vulnId=CVE-2024-22038",
        "source": "NVD"
      }
    ]
  }
]
EOF

get '/api/embargoed-bugs/none' => {format => 'json', text => <<'EOF'};
[]
EOF

my $AUTHENTICATED = 0;
get '/source/:project/kernel-test' => [project => ['openSUSE:Factory']] => (query => {view => 'info'}) => sub ($c) {
  if (($c->req->headers->authorization // '') =~ /^Signature keyId="legaldb",algorithm="ssh",.+,created="\d+"$/) {
    $AUTHENTICATED = 1;
    $c->render(data => <<'EOF');
<sourceinfo package="kernel-test" rev="10" vrev="1"
srcmd5="74ee00bc30bdaf23acbfba25a893b52a"
lsrcmd5="afd761dadb5281cdc26c869324b2ecd2"
verifymd5="bb19066400b2b60e2310b45f10d12f56">
  <filename>kernel-default.spec</filename>
  <linked project="openSUSE:Factory" package="kernel-source" />
</sourceinfo>
EOF
  }
  else {
    $c->res->headers->www_authenticate('Signature realm="Use your developer account",headers="(created)"');
    $c->render(data => '', status => 401);
  }
};

get '/*whatever' => {whatever => ''} => {text => '', status => 404};

# Connect mock web service
my $obs = Cavil::OBS->new;
my $api = 'http://127.0.0.1:' . $obs->ua->server->app(app)->url->port;
$obs->config({'127.0.0.1' => {user => 'test', password => 'testing', embargoed_bugs => "$api/api/embargoed-bugs"}});

subtest 'Package info' => sub {
  my $info = {
    srcmd5    => '74ee00bc30bdaf23acbfba25a893b52a',
    package   => 'kernel-source',
    verifymd5 => 'bb19066400b2b60e2310b45f10d12f56'
  };
  is_deeply $obs->package_info($api, 'openSUSE:Factory', 'kernel-default'), $info, 'right structure';
  $info = {
    srcmd5    => '09f3db66fc4df14f1160b01ceb4b3e73',
    package   => 'perl-Mojolicious',
    verifymd5 => '09f3db66fc4df14f1160b01ceb4b3e73'
  };
  is_deeply $obs->package_info($api, 'openSUSE:Factory', 'perl-Mojolicious', {rev => 3}), $info, 'right structure';
};

subtest 'Package info for missing packages' => sub {
  eval { $obs->package_info($api, 'openSUSE:Factory', 'perl-Mojolicious', {rev => 4}); };
  like $@, qr/perl-Mojolicious/, 'right error';
};

subtest 'Package info for missingok=true packages' => sub {
  my $info = {
    package   => 'python-monascaclient',
    srcmd5    => 'd023edaef04687af8d487ff4e2eda5f7',
    verifymd5 => '34d69b093c93614c829c06c075688463'
  };
  is_deeply $obs->package_info($api, 'Cloud:OpenStack:Factory', 'python-monascaclient', {rev => 4}), $info,
    'right structure';
};

subtest 'obs request 459053' => sub {
  my $info = {
    package   => 'postgresql96-plr',
    srcmd5    => 'e9cb3655b11bd63d07210a161240330c',
    verifymd5 => '8c174a4cd8c85e430378d875aa77c23e'
  };
  is_deeply $obs->package_info($api, 'server:database:postgresql', 'postgresql96-plr', {rev => 2}), $info,
    'right structure';
};

subtest 'obs request 459054' => sub {
  my $info = {
    package   => 'postgresql95-plr',
    srcmd5    => '33fd6e072853f97aa64a205090f55d5e',
    verifymd5 => '5e2c789dcbe65ad644652455029c1123'
  };
  is_deeply $obs->package_info($api, 'server:database:postgresql', 'postgresql95-plr', {rev => 2}), $info,
    'right structure';
};

subtest 'Source download with revision' => sub {
  my $dir = tempdir;
  $obs->download_source($api, 'home:kraih', 'perl-Mojolicious', $dir, {rev => 1});
  ok -e $dir->child('perl-Mojo#licious.changes'), 'file exists';
  like $dir->child('perl-Mojo#licious.changes')->slurp, qr/changes!/, 'right content';
  ok -e $dir->child('perl-Mojolicious.spec'), 'file exists';
  like $dir->child('perl-Mojolicious.spec')->slurp, qr/spec!/, 'right content';
  is $dir->list->size, 2, 'only two files';
};

subtest 'Wrong checksum' => sub {
  my $dir = tempdir;
  eval { $obs->download_source($api, 'home:kraih', 'perl-WrongChecksum', $dir, {rev => 1}); };
  like $@, qr/Corrupted file/, 'right error';
};

subtest 'Source download for missing packages' => sub {
  my $dir = tempdir;
  eval { $obs->download_source($api, 'home:kraih', 'does-not-exist', $dir, {rev => 1}); };
  like $@, qr/does-not-exist/, 'right error';
  eval { $obs->download_source($api, 'home:kraih', 'perl-Mojo-SQLite', $dir); };
  like $@, qr/Mojo-SQLite-1.004.tar.gz/, 'right error';
};

subtest 'Embargo' => sub {
  subtest 'SMASH bugrefs' => sub {
    subtest 'Realistic example' => sub {
      is_deeply $obs->get_embargoed_bugrefs($api), ['CVE-2024-22038', 'bnc#1196706', 'bnc#1202470', 'bnc#1230469'],
        'right bugrefs';
    };

    subtest 'No embargoed bugs' => sub {
      local $obs->config->{'127.0.0.1'}{embargoed_bugs} = "$api/api/embargoed-bugs/none";
      is_deeply $obs->get_embargoed_bugrefs($api), [], 'right bugrefs';
    };

    subtest 'Not configured' => sub {
      local $obs->config->{'127.0.0.1'}{embargoed_bugs} = undef;
      is_deeply $obs->get_embargoed_bugrefs($api), [], 'right bugrefs';
    };
  };

  subtest 'OBS bugrefs' => sub {
    is_deeply $obs->get_bugrefs_for_request($api, 1236), ['CVE-2024-22038'], 'right bugrefs';
    is_deeply $obs->get_bugrefs_for_request($api, 1237), [],                 'no bugrefs';
    is_deeply $obs->get_bugrefs_for_request($api, 344036),
      [
      'CVE-2022-2850', 'CVE-2024-1062', 'CVE-2024-2199', 'CVE-2024-3657', 'CVE-2024-5953', 'bnc#1202470',
      'bnc#1219836',   'bnc#1225512',   'bsc#1202470',   'bsc#1219836',   'bsc#1225512'
      ],
      'right bugrefs';
  };

  subtest 'Check for embargo' => sub {
    is $obs->check_for_embargo($api, 1235),   0, 'not embargoed';
    is $obs->check_for_embargo($api, 1236),   1, 'embargoed';
    is $obs->check_for_embargo($api, 1237),   0, 'not embargoed';
    is $obs->check_for_embargo($api, 344036), 1, 'embargoed';
  };

  subtest 'Check for embargo without embargo server (bails out early)' => sub {
    local $obs->config->{'127.0.0.1'}{embargoed_bugs} = undef;
    is $obs->check_for_embargo($api, 1236), 0, 'not embargoed';

    local $obs->config->{'127.0.0.1'} = undef;
    is $obs->check_for_embargo($api, 1236), 0, 'not embargoed';
  };
};

subtest 'Bot API (with Minion background jobs)' => sub {
  my $cavil_test = Cavil::Test->new(online => $ENV{TEST_ONLINE}, schema => 'import_test');
  my $config     = $cavil_test->default_config;
  my $t          = Test::Mojo->new(Cavil => $config);
  $cavil_test->no_fixtures($t->app);

  # Connect with mock web service
  $t->app->obs->ua->server->app(app);
  my $api = 'http://127.0.0.1:' . $t->app->obs->ua->server->app(app)->url->port;
  $t->app->obs->config({'127.0.0.1' => {user => 'test', password => 'testing'}});

  # Validation errors
  $t->post_ok('/packages')->status_is(403);
  my $headers = {Authorization => "Token $config->{tokens}[0]"};
  $t->post_ok('/packages', $headers)
    ->status_is(400)
    ->json_is({error => 'Invalid request parameters (api, package, project)'});

  # Standard import
  $t->post_ok('/packages', $headers,
    form => {api => $api, package => 'perl-Mojolicious', project => 'home:kraih', rev => 1})
    ->status_is(200)
    ->json_is('/saved/id' => 1);
  ok !$t->app->packages->is_imported(1), 'not imported yet';
  $t->get_ok('/package/1', $headers)->status_is(200)->json_is('/state' => 'new')->json_is('/imported' => undef);
  my $minion = $t->app->minion;
  my $worker = $minion->worker->register;
  my $job_id = $minion->jobs({tasks => ['obs_import']})->next->{id};
  ok my $job = $worker->dequeue(0, {id => $job_id}), 'job dequeued';
  is $job->execute, undef, 'no error';
  ok $minion->lock('processing_pkg_1', 0), 'lock no longer exists';
  $worker->unregister;
  ok $t->app->packages->is_imported(1), 'imported';
  $t->get_ok('/package/1', $headers)->status_is(200)->json_is('/state' => 'new')->json_like('/imported' => qr/\d/);
  unlike $minion->job($job_id)->info->{result}, qr/Package \d+ is already being processed/, 'no race condition';

  # Prevent import race condition
  ok $minion->job($job_id)->retry, 'import job retried';
  my $guard = $minion->guard('processing_pkg_1', 172800);
  ok !$minion->lock('processing_pkg_1', 0), 'lock exists';
  $worker->register;
  ok $job = $worker->dequeue(0, {id => $job_id}), 'job dequeued';
  is $job->execute, undef, 'no error';
  like $minion->job($job_id)->info->{result}, qr/Package \d+ is already being processed/, 'race condition prevented';
  $worker->unregister;
  undef $guard;
  ok $minion->lock('processing_pkg_1', 0), 'lock no longer exists';
};

subtest 'Package info (with ssh authentication)' => sub {
  my $private_key = tempfile->spew(<<'EOF');
-----BEGIN OPENSSH PRIVATE KEY-----
b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW
QyNTUxOQAAACAQ1ktyOCFDMUIV9GfaZio8NNPT09mHcG0Wpx3bo7xwzAAAAJBnE+yjZxPs
owAAAAtzc2gtZWQyNTUxOQAAACAQ1ktyOCFDMUIV9GfaZio8NNPT09mHcG0Wpx3bo7xwzA
AAAEAnJpCOHj1O0O8oCygQJ6pjDT+827VkQXq98zApns/VYRDWS3I4IUMxQhX0Z9pmKjw0
09PT2YdwbRanHdujvHDMAAAACmNhdmlsQHRlc3QBAgM=
-----END OPENSSH PRIVATE KEY-----
EOF
  $obs->config({'127.0.0.1' => {user => 'legaldb', ssh_key => $private_key->to_string}});

  my $info = {
    srcmd5    => '74ee00bc30bdaf23acbfba25a893b52a',
    package   => 'kernel-test',
    verifymd5 => 'bb19066400b2b60e2310b45f10d12f56'
  };
  ok !$AUTHENTICATED, 'not authenticated';
  is_deeply $obs->package_info($api, 'openSUSE:Factory', 'kernel-test'), $info, 'right structure';
  ok $AUTHENTICATED, 'authenticated';
};

done_testing;
