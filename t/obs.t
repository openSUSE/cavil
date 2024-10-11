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

get '/public/source/:project/kernel-default' => [project => ['openSUSE:Factory']] => (query => {view => 'info'}) =>
  {text => <<'EOF'};
<sourceinfo package="kernel-default" rev="10" vrev="1"
srcmd5="74ee00bc30bdaf23acbfba25a893b52a"
lsrcmd5="afd761dadb5281cdc26c869324b2ecd2"
verifymd5="bb19066400b2b60e2310b45f10d12f56">
  <filename>kernel-default.spec</filename>
  <linked project="openSUSE:Factory" package="kernel-source" />
</sourceinfo>
EOF

get '/public/source/:project/kernel-default'                          => [project => ['openSUSE:Factory']] =>
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

get '/public/source/:project/kernel-source'                           => [project => ['openSUSE:Factory']] =>
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

get '/public/source/:project/kernel-source'              => [project => ['openSUSE:Factory']] =>
  (query => {rev => 'bb19066400b2b60e2310b45f10d12f56'}) => {text => <<'EOF'};
<directory name="kernel-source" rev="bb19066400b2b60e2310b45f10d12f56"
  srcmd5="bb19066400b2b60e2310b45f10d12f56">
  <entry name="kernel-source.spec" md5="3291debddffcf461fba5d9679099e0eb"
    size="8600" mtime="1485422138" />
</directory>
EOF

get '/public/source/:project/kernel-source/_meta' => [project => ['openSUSE:Factory']] => {text => <<'EOF'};
<package name="kernel-source" project="openSUSE:Factory">
  <title>The Linux Kernel Sources</title>
  <devel project="Kernel:stable" package="kernel-source" />
</package>
EOF

get '/public/source/:project/perl-Mojolicious' => [project => ['openSUSE:Factory']] =>
  (query => {view => 'info', rev => '3'})      => {text => <<'EOF'};
<sourceinfo package="perl-Mojolicious" rev="3" vrev="1"
  srcmd5="09f3db66fc4df14f1160b01ceb4b3e73"
  verifymd5="09f3db66fc4df14f1160b01ceb4b3e73">
  <filename>perl-Mojolicious.spec</filename>
</sourceinfo>
EOF

get '/public/source/:project/perl-Mojolicious/_meta' => [project => ['openSUSE:Factory']] => {text => <<'EOF'};
<package name="perl-Mojolicious" project="openSUSE:Factory">
  <title>The Web In A Box!</title>
  <devel project="devel:languages:perl" package="perl-Mojolicious" />
</package>
EOF

get '/public/source/:project/perl-Mojolicious' => [project => ['home:kraih']] => (query => {view => 'info'}) =>
  {text => <<'EOF'};
<sourceinfo package="perl-Mojolicious" rev="9199eca9ec0fa5cffe4c3a6cb99a8093"
vrev="140"
srcmd5="0e5c2d1c0c4178869cf7fb82482b9c52"
lsrcmd5="d277e095ec45b64835452d5e87d2d349"
verifymd5="bb19066400b2b60e2310b45f10d12f56">
  <filename>perl-Mojolicious.spec</filename>
</sourceinfo>
EOF

get '/public/source/:project/perl-Mojolicious/_meta' => [project => ['home:kraih']] => {text => <<'EOF'};
<package name="postgresql-plr" project="server:database:postgresql">
  <title>Mojolicious</title>
  <description>
    Real-time web framework
  </description>
</package>
EOF

get '/public/source/:project/perl-Mojolicious'                             => [project => ['home:kraih']] =>
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
get '/public/source/:project/perl-Mojolicious' => [project => ['openSUSE:Factory']] =>
  (query => {view => 'info', rev => 4})        => {text => '', status => 404};

get '/public/source/:project/perl-Mojolicious/perl-Mojolicious.spec' => [project => ['home:kraih']] =>
  (query => {rev => '9199eca9ec0fa5cffe4c3a6cb99a8093'})             => {text => 'Mojolicious spec!'};

get '/public/source/:project/perl-Mojolicious/:special'  => [project => ['home:kraih']]                =>
  (query => {rev => '9199eca9ec0fa5cffe4c3a6cb99a8093'}) => [special => ['perl-Mojo#licious.changes']] =>
  {text => 'Mojolicious changes!'};

get '/public/source/:project/perl-WrongChecksum' => [project => ['home:kraih']] =>
  (query => {expand => 1, rev => 1})             => {text => <<'EOF'};
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

get '/public/source/:project/perl-WrongChecksum/perl-WrongChecksum.changes' => [project => ['home:kraih']] =>
  (query => {rev => '9199eca9ec0fa5cffe4c3a6cb99a8093'})                    => {text => 'Wrong checksum changes!'};

get '/public/source/:project/perl-Mojo-SQLite' => (query => {expand => 1}) => [project => ['home:kraih']] =>
  {text => <<'EOF'};
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

get '/public/source/:project/python-monascaclient' => [project => ['Cloud:OpenStack:Factory']] =>
  (query => {view => 'info', rev => 4})            => {text => <<'EOF'};
<sourceinfo package="python-monascaclient" rev="4" vrev="4"
  srcmd5="d023edaef04687af8d487ff4e2eda5f7"
  lsrcmd5="4de5b31e259161d9368c9a3c8b6ccecd"
    verifymd5="34d69b093c93614c829c06c075688463">
  <filename>python-monascaclient.spec</filename>
  <linked project="openSUSE:Factory" package="python-monascaclient" />
</sourceinfo>
EOF

get '/public/source/:project/python-monascaclient' => [project => ['Cloud:OpenStack:Factory']] =>
  (query => {expand => 1, rev => 4})               => {text => <<'EOF'};
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

get '/public/source/:project/python-monascaclient'       => [project => ['openSUSE:Factory']] =>
  (query => {rev => 'd41d8cd98f00b204e9800998ecf8427e'}) => {text => '', status => 404};

get '/public/source/:project/python-monascaclient/_meta' => [project => ['Cloud:OpenStack:Factory']] =>
  {text => <<'EOF'};
<package name="python-monascaclient" project="Cloud:OpenStack:Factory">
  <title/>
  <description/>
</package>
EOF

get '/public/source/:project/postgresql95-plr' => [project => ['server:database:postgresql']] =>
  (query => {view => 'info', rev => 2})        => {text => <<'EOF'};
<sourceinfo package="postgresql95-plr" rev="2" vrev="30"
  srcmd5="33fd6e072853f97aa64a205090f55d5e"
  lsrcmd5="3cb5f8a6851e65e8f10270f2bbe5dac4"
  verifymd5="5e2c789dcbe65ad644652455029c1123">
  <filename>postgresql95-plr.spec</filename>
  <linked project="server:database:postgresql" package="postgresql-plr" />
</sourceinfo>
EOF

get '/public/source/:project/postgresql96-plr' => [project => ['server:database:postgresql']] =>
  (query => {view => 'info', rev => 2})        => {text => <<'EOF'};
<sourceinfo package="postgresql96-plr" rev="2" vrev="30"
  srcmd5="e9cb3655b11bd63d07210a161240330c"
  lsrcmd5="36b5b26094ae578303e70881a7e246b8"
  verifymd5="8c174a4cd8c85e430378d875aa77c23e">
  <filename>postgresql96-plr.spec</filename>
  <linked project="server:database:postgresql" package="postgresql-plr" />
</sourceinfo>
EOF

get '/public/source/:project/postgresql96-plr' => [project => ['server:database:postgresql']] =>
  (query => {rev => 2, expand => 1})           => {text => <<'EOF'};
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

get '/public/source/:project/postgresql95-plr' => [project => ['server:database:postgresql']] =>
  (query => {rev => 2, expand => 1})           => {text => <<'EOF'};
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

get '/public/source/:project/postgresql-plr'                          => [project => ['server:database:postgresql']] =>
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

get '/public/source/:project/postgresql-plr/_meta' => [project => ['server:database:postgresql']] => {text => <<'EOF'};
<package name="postgresql-plr" project="server:database:postgresql">
  <title>PL/R - R Procedural Language for PostgreSQL</title>
  <description>
    PL/R is a loadable procedural language that enables you to write PostgreSQL
    functions
  </description>
</package>
EOF

get '/public/source/:project/postgresql95-plr/_meta' => [project => ['server:database:postgresql']] =>
  {text => <<'EOF'};
<package name="postgresql95-plr" project="server:database:postgresql">
  <title>PL/R - R Procedural Language for PostgreSQL</title>
  <description>
    PL/R is a loadable procedural language that enables you to write PostgreSQL
    functions
  </description>
</package>
EOF

get '/public/source/:project/postgresql96-plr/_meta' => [project => ['server:database:postgresql']] =>
  {text => <<'EOF'};
<package name="postgresql96-plr" project="server:database:postgresql">
  <title>PL/R - R Procedural Language for PostgreSQL</title>
  <description>
    PL/R is a loadable procedural language that enables you to write PostgreSQL
    functions
  </description>
</package>
EOF

get '/public/request/1234' => {text => <<'EOF'};
<request id="1234" creator="test2">
  <action type="maintenance_release">
    <source project="SUSE:Maintenance:4321" package="perl-Mojolicious.SUSE_SLE-15-SP2_Update"
      rev="961b20692bc317a3c6ab3166312425da"/>
    <target project="SUSE:SLE-15-SP2:Update" package="curl-perl-Mojolicious.33127"/>
  </action>
  <description>requesting release</description>
</request>
EOF

get '/public/source/:project/_attribute' => [project => 'SUSE:Maintenance:4321'] => {text => <<'EOF'};
<attributes>
  <attribute name="EmbargoDate" namespace="OBS">
    <value>2024-03-27 07:00 UTC</value>
  </attribute>
</attributes>
EOF

get '/public/request/1235' => {text => <<'EOF'};
<request id="1234" creator="test2">
  <action type="maintenance_release">
    <source project="SUSE:Maintenance:5321" package="perl-Mojolicious.SUSE_SLE-15-SP2_Update"
      rev="961b20693bc397a3c65a3164312425db"/>
    <target project="SUSE:SLE-15-SP2:Update" package="curl-perl-Mojolicious.33127"/>
  </action>
  <description>requesting release</description>
</request>
EOF

get '/public/source/:project/_attribute' => [project => 'SUSE:Maintenance:5321'] => {text => <<'EOF'};
<attributes/>
EOF

get '/public/request/324874' => {text => <<'EOF'};
<request id="324874" creator="test2">
  <action type="maintenance_release">
    <source project="SUSE:Maintenance:34725" package="curl-mini.SUSE_SLE-15-SP2_Update"
      rev="9698206925c397a3c6a43166312425dc"/>
    <target project="SUSE:SLE-15-SP2:Update" package="curl-mini.33127"/>
  </action>
  <action type="maintenance_release">
    <source project="SUSE:Maintenance:34725" package="curl.SUSE_SLE-15-SP2_Update"
      rev="7b1b7765b09ae0622ee1f444a03b1dee"/>
    <target project="SUSE:SLE-15-SP2:Update" package="curl.33127"/>
    <acceptinfo rev="1" srcmd5="38d742c3eb1b4d27d95003c647b7ffa2" oproject="SUSE:SLE-15-SP2:Update"
      opackage="curl.31896" osrcmd5="6f2bce80ce9601ae0544ebfab8ca1cbe" oxsrcmd5="6f2bce80ce9601ae0544ebfab8ca1cbe"/>
  </action>
  <action type="maintenance_release">
    <source project="SUSE:Maintenance:34725" package="patchinfo"/>
    <target project="SUSE:SLE-15-SP2:Update" package="patchinfo.33127"/>
    <acceptinfo rev="1" srcmd5="d4e961c88c26a5552dc7f075361b3c87" osrcmd5="d41d8cd98f00b204e9800998ecf8427e"/>
  </action>
  <action type="maintenance_release">
    <source project="SUSE:Maintenance:33127" package="patchinfo"/>
    <target project="SUSE:Updates:SUSE-MicroOS:5.1:aarch64" package="patchinfo.33127"/>
    <acceptinfo rev="1" srcmd5="d4e961c88c26a5552dc7f075361b3c87" osrcmd5="d41d8cd98f00b204e9800998ecf8427e"/>
  </action>
  <action type="maintenance_release">
    <source project="SUSE:Maintenance:33127" package="patchinfo"/>
    <target project="SUSE:Updates:SUSE-MicroOS:5.1:s390x" package="patchinfo.33127"/>
    <acceptinfo rev="1" srcmd5="d4e961c88c26a5552dc7f075361b3c87" osrcmd5="d41d8cd98f00b204e9800998ecf8427e"/>
  </action>
  <action type="maintenance_release">
    <source project="SUSE:Maintenance:33127" package="patchinfo"/>
    <target project="SUSE:Updates:SUSE-MicroOS:5.1:x86_64" package="patchinfo.33127"/>
    <acceptinfo rev="1" srcmd5="d4e961c88c26a5552dc7f075361b3c87" osrcmd5="d41d8cd98f00b204e9800998ecf8427e"/>
  </action>
  <action type="maintenance_release">
    <source project="SUSE:Maintenance:33127" package="patchinfo"/>
    <target project="SUSE:Updates:SUSE-MicroOS:5.2:aarch64" package="patchinfo.33127"/>
    <acceptinfo rev="1" srcmd5="d4e961c88c26a5552dc7f075361b3c87" osrcmd5="d41d8cd98f00b204e9800998ecf8427e"/>
  </action>
  <action type="maintenance_release">
    <source project="SUSE:Maintenance:33127" package="patchinfo"/>
    <target project="SUSE:Updates:SUSE-MicroOS:5.2:s390x" package="patchinfo.33127"/>
    <acceptinfo rev="1" srcmd5="d4e961c88c26a5552dc7f075361b3c87" osrcmd5="d41d8cd98f00b204e9800998ecf8427e"/>
  </action>
  <action type="maintenance_release">
    <source project="SUSE:Maintenance:33127" package="patchinfo"/>
    <target project="SUSE:Updates:SUSE-MicroOS:5.2:x86_64" package="patchinfo.33127"/>
    <acceptinfo rev="1" srcmd5="d4e961c88c26a5552dc7f075361b3c87" osrcmd5="d41d8cd98f00b204e9800998ecf8427e"/>
  </action>
  <action type="maintenance_release">
    <source project="SUSE:Maintenance:33127" package="patchinfo"/>
    <target project="SUSE:Updates:SLE-Module-Development-Tools-OBS:15-SP5:aarch64" package="patchinfo.33127"/>
    <acceptinfo rev="1" srcmd5="d4e961c88c26a5552dc7f075361b3c87" osrcmd5="d41d8cd98f00b204e9800998ecf8427e"/>
  </action>
  <action type="maintenance_release">
    <source project="SUSE:Maintenance:33127" package="patchinfo"/>
    <target project="SUSE:Updates:SLE-Module-Development-Tools-OBS:15-SP5:ppc64le" package="patchinfo.33127"/>
    <acceptinfo rev="1" srcmd5="d4e961c88c26a5552dc7f075361b3c87" osrcmd5="d41d8cd98f00b204e9800998ecf8427e"/>
  </action>
  <action type="maintenance_release">
    <source project="SUSE:Maintenance:33127" package="patchinfo"/>
    <target project="SUSE:Updates:SLE-Module-Development-Tools-OBS:15-SP5:s390x" package="patchinfo.33127"/>
    <acceptinfo rev="1" srcmd5="d4e961c88c26a5552dc7f075361b3c87" osrcmd5="d41d8cd98f00b204e9800998ecf8427e"/>
  </action>
  <action type="maintenance_release">
    <source project="SUSE:Maintenance:33127" package="patchinfo"/>
    <target project="SUSE:Updates:SLE-Module-Development-Tools-OBS:15-SP5:x86_64" package="patchinfo.33127"/>
    <acceptinfo rev="1" srcmd5="d4e961c88c26a5552dc7f075361b3c87" osrcmd5="d41d8cd98f00b204e9800998ecf8427e"/>
  </action>
  <state name="accepted" who="test1" when="2024-04-05T12:03:55" created="2024-03-26T10:52:47" approver="eroca">
    <comment>Auto accept</comment>
  </state>
  <review state="accepted" created="2024-03-26T10:52:50" when="2024-03-26T12:36:42" who="test1"
    by_group="autobuild-team">
    <comment>reviewed_okay</comment>
    <history who="test1" when="2024-03-26T12:36:42">
      <description>Review got accepted</description>
      <comment>reviewed_okay</comment>
    </history>
  </review>
  <review state="accepted" created="2024-03-26T10:52:50" when="2024-04-03T11:54:34" who="test2"
    by_group="maintenance-release-approver">
    <comment>OK</comment>
    <history who="test2" when="2024-04-03T11:54:34">
      <description>Review got accepted</description>
      <comment>OK</comment>
    </history>
  </review>
  <review state="accepted" created="2024-03-26T10:52:50" when="2024-03-26T11:00:03" who="maintenance-robot"
    by_group="qam-auto">
    <comment>reviewers added: qam-openqa</comment>
    <history who="maintenance-robot" when="2024-03-26T11:00:03">
      <description>Review got accepted</description>
      <comment>reviewers added: qam-openqa</comment>
    </history>
  </review>
  <review state="accepted" created="2024-03-26T11:00:03" when="2024-04-05T12:03:30" who="sle-qam-openqa"
    by_group="qam-openqa">
    <comment>Request accepted for 'qam-openqa' based on data in http://dashboard.qam.suse.de/</comment>
    <history who="sle-qam-openqa" when="2024-04-05T12:03:30">
      <description>Review got accepted</description>
      <comment>Request accepted for 'qam-openqa' based on data in http://dashboard.qam.suse.de/</comment>
    </history>
  </review>
  <description>requesting release</description>
</request>
EOF

get '/public/source/:project/_attribute' => [project => 'SUSE:Maintenance:33127'] => {text => <<'EOF'};
<attributes/>
EOF

get '/public/source/:project/_attribute' => [project => 'SUSE:Maintenance:34725'] => {text => <<'EOF'};
<attributes>
  <attribute name="ScheduledReleaseDate" namespace="MAINT">
    <value>2024-07-16 12:00 UTC</value>
  </attribute>
  <attribute name="RejectReason" namespace="MAINT">
    <value>338592:admin</value>
    <value>341702:admin</value>
  </attribute>
  <attribute name="EmbargoDate" namespace="OBS">
    <value>2024-09-24 12:00 UTC</value>
  </attribute>
  <attribute name="MaintenanceProject" namespace="CPE"/>
</attributes>
EOF

my $AUTHENTICATED = 0;
get '/source/:project/kernel-default' => [project => ['openSUSE:Factory']] => (query => {view => 'info'}) => sub ($c) {
  if (($c->req->headers->authorization // '') =~ /^Signature keyId="legaldb",algorithm="ssh",.+,created="\d+"$/) {
    $AUTHENTICATED = 1;
    $c->render(data => <<'EOF');
<sourceinfo package="kernel-default" rev="10" vrev="1"
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
  is $obs->check_for_embargo($api, 1234),   1, 'embargoed';
  is $obs->check_for_embargo($api, 1235),   0, 'not embargoed';
  is $obs->check_for_embargo($api, 324874), 1, 'embargoed';
};

subtest 'Bot API (with Minion background jobs)' => sub {
  my $cavil_test = Cavil::Test->new(online => $ENV{TEST_ONLINE}, schema => 'import_test');
  my $config     = $cavil_test->default_config;
  my $t          = Test::Mojo->new(Cavil => $config);
  $cavil_test->no_fixtures($t->app);

  # Connect with mock web service
  $t->app->obs->ua->server->app(app);
  my $api = 'http://127.0.0.1:' . $t->app->obs->ua->server->app(app)->url->port;

  # Validation errors
  $t->post_ok('/packages')->status_is(403);
  my $headers = {Authorization => "Token $config->{tokens}[0]"};
  $t->post_ok('/packages', $headers)->status_is(400)
    ->json_is({error => 'Invalid request parameters (api, package, project)'});

  # Standard import
  $t->post_ok('/packages', $headers,
    form => {api => $api, package => 'perl-Mojolicious', project => 'home:kraih', rev => 1})->status_is(200)
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
  $obs->user('legaldb');
  $obs->ssh_key($private_key->to_string);
  $obs->ssh_hosts(['127.0.0.1']);

  my $info = {
    srcmd5    => '74ee00bc30bdaf23acbfba25a893b52a',
    package   => 'kernel-default',
    verifymd5 => 'bb19066400b2b60e2310b45f10d12f56'
  };
  ok !$AUTHENTICATED, 'not authenticated';
  is_deeply $obs->package_info($api, 'openSUSE:Factory', 'kernel-default'), $info, 'right structure';
  ok $AUTHENTICATED, 'authenticated';
};

done_testing;
