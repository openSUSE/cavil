#
# spec file for package libqt4-sql-plugins
#
# Copyright (c) 2013 SUSE LINUX Products GmbH, Nuernberg, Germany.
#
# All modifications and additions to the file contributed by third parties
# remain the property of their copyright owners, unless otherwise agreed
# upon. The license for this file, and modifications and additions to the
# file, is the same license as for the pristine package itself (unless the
# license for the pristine package is not an Open Source License, in which
# case the license is the MIT License). An "Open Source License" is a
# license that conforms to the Open Source Definition (Version 1.9)
# published by the Open Source Initiative.

# Please submit bugfixes or comments via http://bugs.opensuse.org/
#
# nodebuginfo


Name:           libqt4-sql-plugins
BuildRequires:  Mesa-devel
BuildRequires:  alsa-devel
BuildRequires:  cups-devel
BuildRequires:  gtk2-devel
BuildRequires:  libmysqlclient-devel
BuildRequires:  pkgconfig
BuildRequires:  postgresql-devel
BuildRequires:  unixODBC-devel
%if 0%{?suse_version}
BuildRequires:  update-desktop-files
%endif
Summary:        Qt 4 SQL related libraries
License:        SUSE-LGPL-2.1-with-digia-exception-1.1 or GPL-3.0
Group:          System/Libraries
Url:            http://qt.digia.com/
# COMMON-VERSION-BEGIN
# COMMON-VERSION-BEGIN
%define base_name libqt4
%define tar_version everywhere-opensource-src-%{version}
Version:        4.8.4
Release:        0
# COMMON-VERSION-END
# COMMON-VERSION-END
BuildRequires:  libqt4-devel >= %{version}
# COMMON-BEGIN
# COMMON-BEGIN
Source:         qt-%{tar_version}.tar.bz2
# to get mtime of file:
Source1:        libqt4.changes
Source2:        baselibs.conf
Source3:        macros.qt4
Source10:       qt4config.desktop
Source11:       designer4.desktop
Source12:       linguist4.desktop
Source13:       assistant4.desktop
Source14:       assistant.png
Source15:       designer.png
Source16:       linguist.png
Source17:       qt_lt.ts

Patch2:         qt-never-strip.diff
Patch3:         plastik-default.diff
Patch6:         use-freetype-default.diff
Patch8:         link-tools-shared.diff
Patch39:        0191-listview-alternate-row-colors.diff
Patch40:        0188-fix-moc-parser-same-name-header.diff
Patch43:        0195-compositing-properties.diff
Patch60:        0180-window-role.diff
Patch61:        qt4-fake-bold.patch
Patch70:        0225-invalidate-tabbar-geometry-on-refresh.patch
Patch75:        qt-debug-timer.diff
Patch87:        qfatal-noreturn.diff
Patch101:       no-moc-date.diff
Patch107:       webkit-ia64_s390x.patch
Patch109:       libqt4-libtool-nodate.diff
Patch113:       ppc64-webkit-link-fix.diff
Patch118:       rcc-stable-dirlisting.diff
Patch119:       hppa_ldcw_fix.diff
Patch120:       hppa_unaligned_access_fix_458133.diff
Patch121:       webkit-sparc64.diff
Patch123:       use-cups-default-print-settings-bnc552218.diff
Patch128:       build-qvfb-tool.diff
Patch131:       disable-im-for-password.diff
Patch132:       CVE-2011-3922.diff
Patch136:       handle-tga-files-properly.diff
Patch137:       qdbusconnection-no-warning-output.patch
Patch138:       undo-fix-jit-crash-on-x86_64.patch
# PATCH-FIX-UPSTREAM  fix_assistant_segfault_QTBUG-25324.patch [bnc#780763] [QTBUG#25324]
Patch140:       fix_assistant_segfault_QTBUG-25324.patch
# PATCH-FIX-OPENSUSE  fix build on s390x failing to link in qnetworkconfigmanager.o
Patch141:       qt4-fix-s390x-build.diff
Patch142:       qdbusviewer.patch
Patch143:       openssl-incompatibility-fix.diff
Patch144:       cert-blacklist-tuerktrust.diff
Patch145:       cert-blacklist-more.diff

BuildRoot:      %{_tmppath}/%{name}-%{version}-build
  %define common_options --opensource -fast -no-separate-debug-info -shared -xkb -openssl-linked -xrender -xcursor -dbus-linked -xfixes -xrandr -xinerama -sm -no-nas-sound -no-rpath -system-libjpeg -system-libpng -accessibility -cups -stl -nis -system-zlib -prefix /usr -L %{_libdir} -libdir %{_libdir} -docdir %_docdir/%{base_name} -examplesdir %{_libdir}/qt4/examples -demosdir %{_libdir}/qt4/demos -plugindir %plugindir -translationdir %{_datadir}/qt4/translations -iconv -sysconfdir /etc/settings -datadir %{_datadir}/qt4/ -no-pch -reduce-relocations -exceptions -system-libtiff -glib -optimized-qmake -no-webkit -no-xmlpatterns -system-sqlite -qt3support -no-sql-mysql -importdir %plugindir/imports  -xsync -xinput -gtkstyle
%define check_config \
  grep '# define' src/corelib/global/qconfig.h | egrep -v 'QT_(ARCH|USE)';             \
  if test -f %{_datadir}/qt4/mkspecs/qconfig.pri ; then                                 \
    diff -u %{_datadir}/qt4/mkspecs/qconfig.pri mkspecs/qconfig.pri || exit 1;           \
  fi                                                                                   \

%description
Qt is a set of libraries for developing applications.

This package contains base tools, like string, xml, and network
handling.
# COMMON-END
# COMMON-DESC-BEGIN
%package -n libqt4-sql-unixODBC
Summary:        Qt 4 unixODBC plugin
Group:          Development/Libraries/C and C++
Requires:       libqt4-sql = %{version}
Provides:       libqt4_sql_backend = %{version}
Obsoletes:      qt-sql-unixODBC < 4.6.0
Provides:       qt-sql-unixODBC = 4.6.0

%description -n libqt4-sql-unixODBC
Qt unixODBC plugin to support databases via unixODBC within Qt
applications.

%package -n libqt4-sql-postgresql
Summary:        Qt 4 PostgreSQL plugin
Group:          Development/Libraries/C and C++
Requires:       libqt4-sql = %{version}
Provides:       libqt4_sql_backend = %{version}
Obsoletes:      qt-sql-postgresql < 4.6.0
Provides:       qt-sql-postgresql = 4.6.0

%description -n libqt4-sql-postgresql
Qt SQL plugin to support PostgreSQL servers in Qt applications.

%package -n libqt4-sql-mysql
Summary:        Qt 4 MySQL support
Group:          Development/Libraries/C and C++
Requires:       libqt4-sql = %{version}
Provides:       libqt4_sql_backend = %{version}
Obsoletes:      qt-sql-mysql < 4.6.0
Provides:       qt-sql-mysql = 4.6.0

%description -n libqt4-sql-mysql
A plugin to support MySQL server in Qt applications.
# COMMON-DESC-END
# COMMON-PREP-BEGIN
%prep
%define plugindir %{_libdir}/qt4/plugins
%setup -q -n qt-%tar_version
%patch2
%patch3
%patch6
# needs rediffing
#%patch8
%patch39
%patch40
%patch43
%patch60
# bnc#374073 comment #8
#%patch61
%patch70
%patch75
%patch87
%patch101
# ### 48 rediff
#%patch107
%patch109
# ### 48 rediff
#%patch113
%patch118 -p1
%ifarch hppa
%patch119
%patch120
%endif
%patch123
cp %{SOURCE17} translations/
%patch128
%patch131 -p1
%patch132
%patch136
%patch137
%patch138 -p1
%patch140 -p1
%patch141 -p0
%patch142
%patch143
%patch144 -p1
%patch145 -p1
# ### 47 rediff
#%patch121 -p1
# be sure not to use them
rm -rf src/3rdparty/{libjpeg,freetype,libpng,zlib,libtiff,fonts}
# COMMON-PREP-END
# COMMON-PREP-END

%build
export QTDIR=$PWD
export PATH=$PWD/bin:$PATH
export LD_LIBRARY_PATH=$PWD/lib/
%ifarch ppc64
export RPM_OPT_FLAGS="%{optflags} -mminimal-toc"
%endif
export CXXFLAGS="%{optflags}"
export CFLAGS="%{optflags}"
export MAKEFLAGS="%{?_smp_mflags}"
%ifarch sparc64
platform="-platform linux-g++-64"
%else
platform=""
%endif
echo yes | ./configure %common_options $platform \
   -no-webkit -no-xmlpatterns -nomake examples \
   -plugin-sql-psql -I/usr/include -I/usr/include/pgsql/ -I/usr/include/pgsql/server \
   -plugin-sql-odbc \
   -plugin-sql-mysql -I/usr/include/mysql/ -no-sql-sqlite -no-sql-sqlite2

rpm -ql libqt4-devel | grep %{_bindir}/ | sed 's#%{_bindir}/##' | \
    ( while read file; do test -e bin/$file || ln -s %{_bindir}/$file bin/ ; done )
rpm -ql libqt4-devel | grep %{_libdir}/lib | sed 's#%{_libdir}/##' | \
    ( while read file; do test -e lib/$file || ln -s %{_libdir}/$file lib/ ; done )
make %{?_smp_mflags} -C src/sql
make %{?_smp_mflags} -C src/plugins/sqldrivers

%install
export QTDIR=$PWD
make INSTALL_ROOT=%{buildroot} -C src/sql install
make INSTALL_ROOT=%{buildroot} -C src/plugins/sqldrivers install

# argggh, qmake is such a piece of <censored>
mkdir -p %{buildroot}/%{_libdir}/pkgconfig
find  %{buildroot}/%{_libdir} -type f -name '*.pc' -exec mv {} %{buildroot}/%{_libdir}/pkgconfig \;
# fix more qmake errors
mkdir -p %{buildroot}/%{_libdir}/qt
find %{buildroot}/%{_libdir} -type f -name '*la' -print -exec perl -pi -e 's, -L%{_builddir}/\S+,,g' {} \;
find %{buildroot}/%{_libdir}/pkgconfig -type f -name '*pc' -print -exec perl -pi -e 's, -L%{_builddir}/\S+,,g' {} \;
rm -rf %{buildroot}%{_prefix}/include
rm -rf %{buildroot}%{_libdir}/pkgconfig
mkdir %{buildroot}/%{_libdir}/backup
mv %{buildroot}/%{_libdir}/libQtSql*.so.* %{buildroot}/%{_libdir}/backup
rm -f %{buildroot}/%{_libdir}/lib*
mv %{buildroot}/%{_libdir}/backup/libQtSql*.so.* %{buildroot}/%{_libdir}
rmdir %{buildroot}/%{_libdir}/backup
rm -rf %{buildroot}%{_prefix}/bin
for i in %{buildroot}/%plugindir/*; do
  case "$i" in
    *sqldriv*): ;;
    *) rm -rf $i
  esac
done
rm -f %{buildroot}/%{_libdir}/libQtSql*

%files -n libqt4-sql-unixODBC
%defattr(-,root,root,755)
%dir %plugindir/sqldrivers
%plugindir/sqldrivers/libqsqlodbc*.so

%files -n libqt4-sql-postgresql
%defattr(-,root,root,755)
%dir %plugindir/sqldrivers
%plugindir/sqldrivers/libqsqlpsql*.so

%files -n libqt4-sql-mysql
%defattr(-,root,root,755)
%dir %plugindir/sqldrivers
%plugindir/sqldrivers/libqsqlmysql*.so

%changelog
