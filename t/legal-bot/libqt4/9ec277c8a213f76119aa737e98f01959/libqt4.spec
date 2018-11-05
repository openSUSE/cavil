#
# spec file for package libqt4
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


Name:           libqt4

%define with_qt3support 1
%define with_phonon 0
%define with_phonon_backend 0
%define with_qtwebkit 0

BuildRequires:  Mesa-devel
BuildRequires:  alsa-devel
BuildRequires:  clucene-core-devel
BuildRequires:  cups-devel
BuildRequires:  dbus-1-devel
BuildRequires:  fdupes
BuildRequires:  freetype2-devel
BuildRequires:  gcc-c++
BuildRequires:  glib2-devel
BuildRequires:  gtk2-devel
BuildRequires:  libjpeg-devel
BuildRequires:  libmng-devel
BuildRequires:  libpng-devel
BuildRequires:  libtiff-devel
BuildRequires:  openssl-devel
BuildRequires:  pkgconfig
BuildRequires:  sqlite3-devel
BuildRequires:  update-desktop-files
BuildRequires:  xorg-x11-devel

%if %with_phonon && %with_phonon_backend
BuildRequires:  gstreamer-0_10-plugins-base-devel
BuildRequires:  libxine-devel
%endif
# COMMON-VERSION-BEGIN
%define base_name libqt4
%define tar_version everywhere-opensource-src-%{version}
Version:        4.8.4
Release:        0
# COMMON-VERSION-END
Summary:        C++ Program Library, Core Components
License:        GPL-3.0 or SUSE-LGPL-2.1-with-digia-exception-1.1
Group:          System/Libraries
Url:            http://qt.digia.com
# bug437293
%ifarch ppc64
Obsoletes:      qt-64bit
%endif
# plugindir/codecs/* was moved from libqt4-x11, Ensure seamless update from openSUSE <= 11.1 and SLE <= 11:
# See also baselibs.conf.
Conflicts:      %{name}-x11 <= 4.5.1-2.5
#
Obsoletes:      qt < 4.4.0
Provides:       libqt4-dbus-1 = 4.4.0
Provides:       qt = 4.4.0
Obsoletes:      libqt4-dbus-1 < 4.4.0

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

%package devel
Summary:        Qt Development Kit
License:        GPL-3.0 or SUSE-LGPL-2.1-with-digia-exception-1.1
Group:          Development/Libraries/X11
Requires:       %{name} = %{version}
Requires:       Mesa-devel
Requires:       c++_compiler
Requires:       dbus-1-devel
Requires:       freetype2-devel
Requires:       glib2-devel
Requires:       libmng-devel
Requires:       libpng-devel
Requires:       libqt4-sql-sqlite >= %{version}
Requires:       libtiff-devel
Requires:       make
Requires:       openssl-devel
Requires:       pkgconfig
Requires:       sqlite3-devel
Requires:       xorg-x11-devel
Requires:       zlib-devel
# bug437293
%ifarch ppc64
Obsoletes:      qt-devel-64bit
%endif
#
Provides:       dbus-1-qt = 0.63
Provides:       dbus-1-qt-devel = 0.63
Provides:       libQtDeclarative-devel = 4.6.0
Provides:       qt-dbus-1 = 4.2.0
Provides:       qt-devel = 4.4.0
Obsoletes:      dbus-1-qt < 0.63
Obsoletes:      dbus-1-qt-devel < 0.63
Obsoletes:      libQtDeclarative-devel < 4.6.0
Obsoletes:      qt-dbus-1 < 4.2.0
Obsoletes:      qt-devel < 4.4.0

%description devel
You need this package, if you want to compile programs with Qt. It
contains the "Qt Crossplatform Development Kit". It does contain
include files and development applications like GUI designers,
translator tools and code generators.

%package -n libqt4-sql-sqlite
Summary:        Qt 4 sqlite plugin
License:        GPL-3.0 or SUSE-LGPL-2.1-with-digia-exception-1.1
Group:          Development/Libraries/C and C++
Requires:       libqt4-sql = %{version}
Provides:       libqt4_sql_backend = %{version}
Obsoletes:      qt-sql-sqlite < 4.4.0
Provides:       qt-sql-sqlite = 4.4.0

%description -n libqt4-sql-sqlite
Qt 4 sqlite plugin to be able to use database functionality with Qt
applications without the need to setup a SQL server.

%package x11
Summary:        Qt 4 GUI related libraries
License:        GPL-3.0 or SUSE-LGPL-2.1-with-digia-exception-1.1
Group:          Development/Libraries/C and C++
# bug437293
%ifarch ppc64
Obsoletes:      qt-x11-64bit
%endif
Requires:       %{name} = %{version}
#
Obsoletes:      qt-x11 < 4.4.0
Provides:       qt-x11 = 4.4.0

%description x11
Qt 4 libraries which are used for drawing widgets and OpenGL items.

%if %with_qt3support

%package qt3support
Summary:        C++ Program Library, Core Components
License:        GPL-3.0 or SUSE-LGPL-2.1-with-digia-exception-1.1
Group:          System/Libraries
# bug437293
%ifarch ppc64
Obsoletes:      qt-qt3support-64bit
%endif
Requires:       %{name} = %{version}
#
Obsoletes:      qt-qt3support < 4.6.0
Provides:       qt-qt3support = 4.6.0

%description qt3support
Qt is a set of libraries for developing applications.

This package contains base tools, like string, xml, and network
handling.

%endif

%package sql
Summary:        Qt 4 SQL related libraries
License:        GPL-3.0 or SUSE-LGPL-2.1-with-digia-exception-1.1
Group:          Development/Libraries/C and C++
# bug437293
%ifarch ppc64
Obsoletes:      qt-sql-64bit
%endif
Requires:       %{name} = %{version}
Recommends:     libqt4_sql_backend = %{version}
Suggests:       libqt4-sql-sqlite
#
Obsoletes:      qt-sql < 4.4.0
Provides:       qt-sql = 4.4.0

%description sql
Qt 4 libraries which are used for connection with an SQL server. You
will need also a plugin package for a supported SQL server.

%if %with_qtwebkit
%package -n libQtWebKit4
Summary:        Open source Web Browser engine based on Qt4
License:        BSD-3-Clause and LGPL-2.0+
Group:          Development/Libraries/C and C++
Requires:       libqt4-x11 = %{version}
Provides:       libQtDeclarative4 = 4.6.0
Obsoletes:      libQtDeclarative4 < 4.6.0

%description -n libQtWebKit4
WebKit is an open source web browser engine. WebKit's HTML and JavaScript
code began as a branch of the KHTML and KJS libraries from KDE. As part of
KDE framework KHTML was based on Qt but during their porting efforts Apple's
engineers made WebKit toolkit independent. WebKit Qt is a project aiming at
porting this fabulous engine back to Qt.

%package -n libQtWebKit-devel
Summary:        Open source Web Browser engine based on Qt4
License:        BSD-3-Clause and LGPL-2.0+
Group:          Development/Libraries/C and C++
Requires:       libQtWebKit4 = %{version}
Requires:       libqt4-devel = %{version}

%description -n libQtWebKit-devel
WebKit is an open source web browser engine. WebKit's HTML and JavaScript
code began as a branch of the KHTML and KJS libraries from KDE. As part of
KDE framework KHTML was based on Qt but during their porting efforts Apple's
engineers made WebKit toolkit independent. WebKit Qt is a project aiming at
porting this fabulous engine back to Qt.
%endif

%package private-headers-devel
Summary:        Non-ABI stabile experimental API
License:        GPL-3.0 or SUSE-LGPL-2.1-with-digia-exception-1.1
Group:          Development/Libraries/C and C++
Requires:       libqt4-devel = %{version}
Requires:       libqt4-x11 = %{version}

%description private-headers-devel
This package provides private headers of libqt4-devel that are normally
not used by application development and that do not have any ABI or
API guarantees. The packages that build against these have to require
the exact Qt version.

%if %with_phonon

%package -n phonon
Summary:        Phonon Multimedia Platform Abstraction
License:        LGPL-2.0+
Group:          Development/Libraries/KDE
Requires:       libphonon4 = %{version}
Requires:       phonon-backend = %{version}

%description -n phonon
Phonon is a cross-platform portable Multimedia Support Abstraction,
which allows you to play multiple audio or video formats with the same
quality on all platforms, no matter which underlying architecture is
used.

%package -n phonon-devel
Summary:        Phonon Multimedia Platform Abstraction
License:        LGPL-2.0+
Group:          Development/Libraries/KDE
Requires:       %{name} = %{version}
Requires:       libphonon4 = %{version}
Requires:       libqt4-devel

%description -n phonon-devel
Phonon is a cross-platform portable Multimedia Support Abstraction,
which allows you to play multiple audio or video formats with the same
quality on all platforms, no matter which underlying architecture is
used.

%package -n libphonon4
Summary:        Phonon Multimedia Platform Abstraction
License:        LGPL-2.0+
Group:          Development/Libraries/KDE
%requires_ge    libqt4-x11

%description -n libphonon4
Phonon is a cross-platform portable Multimedia Support Abstraction,
which allows you to play multiple audio or video formats with the same
quality on all platforms, no matter which underlying architecture is
used.

%if %with_phonon_backend

%package -n phonon-backend-gstreamer-0_10
Summary:        Phonon Multimedia Platform Abstraction
License:        LGPL-2.0+
Group:          Development/Libraries/KDE
Requires:       libphonon4 = %{version}
Provides:       phonon-backend = %{version}

%description backend-gstreamer-0_10
Phonon is a cross-platform portable Multimedia Support Abstraction,
which allows you to play multiple audio or video formats with the same
quality on all platforms, no matter which underlying architecture is
used.

%package -n phonon-backend-xine
Summary:        Phonon Multimedia Platform Abstraction
License:        LGPL-2.0+
Group:          Development/Libraries/KDE
Requires:       libphonon4 = %{version}
Supplements:    packageand(libxine1-codecs:phonon)
Provides:       phonon-backend = %{version}

%description backend-xine
Phonon is a cross-platform portable Multimedia Support Abstraction,
which allows you to play multiple audio or video formats with the same
quality on all platforms, no matter which underlying architecture is
used.

%endif
%endif

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

%build
export QTDIR=$PWD
export PATH=$PWD/bin:$PATH
export LD_LIBRARY_PATH=$PWD/lib/
%ifarch ppc64
  RPM_OPT_FLAGS="$RPM_OPT_FLAGS -mminimal-toc"
%endif
export CXXFLAGS="$CXXFLAGS $RPM_OPT_FLAGS -DOPENSSL_LOAD_CONF"
export CFLAGS="$CFLAGS $RPM_OPT_FLAGS -DOPENSSL_LOAD_CONF"
export MAKEFLAGS="%{?_smp_mflags}"
touch translations/qt_de.qm
%ifarch sparc64
platform="-platform linux-g++-64"
%else
platform=""
%endif
# Record mtime of changes file instead of build time
CHANGES=`stat --format="%y" %{SOURCE1}|cut --characters=1-10`
sed -i -e "s/qt_instdate=\$TODAY/qt_instdate=$CHANGES/" configure

echo yes | ./configure %common_options $platform \
	-plugin-sql-sqlite -nomake examples -nomake demos -nomake docs \
%ifarch %arm
  -no-neon \
%endif
%if %with_qtwebkit
-webkit \
%endif
-xmlpatterns

%check_config
test -s translations/qt_de.qm || rm translations/qt_de.qm
make %{?_smp_mflags}
for i in translations/*.ts; do
  LD_LIBRARY_PATH=$PWD/lib bin/lrelease $i -qm ${i/.ts/.qm}
done

%install
make INSTALL_ROOT=%{buildroot} install
# install macros and replace version placeholder with current version
install -D -m644 %{SOURCE3} %{buildroot}%{_sysconfdir}/rpm/macros.qt4
sed -i 's/QTVER/%{version}/g' %{buildroot}%{_sysconfdir}/rpm/macros.qt4
%if %with_qtwebkit
cp -p src/3rdparty/webkit/JavaScriptCore/release/libjscore.a \
      src/3rdparty/webkit/JavaScriptCore/release/libjscore.prl \
      %{buildroot}/%{_libdir}
%endif
# argggh, qmake is such a piece of <censored>
find %{buildroot}/%{_libdir} -type f -name '*prl' -exec perl -pi -e "s, -L$RPM_BUILD_DIR/\S+,,g" {} \;
find %{buildroot}/%{_libdir} -type f -name '*prl' -exec sed -i -e "/^QMAKE_PRL_BUILD_DIR/d" {} \;
#find %{buildroot}/%_docdir/%{name} -type f -name 'lib*.a' -exec rm {} \;
find %{buildroot}/%{_libdir} -type f -name '*la' -print -exec perl -pi -e "s, -L$RPM_BUILD_DIR/?\S+,,g" {} \;
# insanity ...
find %{buildroot}/%{_libdir} -type f -name '*pc' -print -exec perl -pi -e "s, -L$RPM_BUILD_DIR/?\S+,,g" {} \; -exec sed -i -e "s,^moc_location=.*,moc_location=%{_bindir}/moc," -e "s,uic_location=.*,uic_location=%{_bindir}/uic," {} \;
find %{buildroot}/%{_libdir}/ -name 'lib*.a' -exec chmod -x -- {} \;
mkdir -p %{buildroot}/%plugindir/sqldrivers
#install qdoc3
install -m 755 bin/qdoc3 %{buildroot}%{_bindir}/
# packaged in devel-doc
rm %{buildroot}%{_bindir}/{qcollectiongenerator,assistant}
# some packages expect these symlinks
ln -s %{_includedir} %{buildroot}/%{_libdir}/qt4/include
ln -s %{_libdir} %{buildroot}/%{_libdir}/qt4/lib
ln -s %{_bindir} %{buildroot}/%{_libdir}/qt4/bin

# install private headers manually instead of using -developer-build
for comb in QtDeclarative/declarative QtCore/corelib QtScript/script QtGui/gui; do
    d=${comb%%/*}
    s=${comb##*/}
    mkdir -p %{buildroot}%{_includedir}/$d/private
    for h in include/$d/private/*_p.h; do
        header=$(find src/$s/ -name "$(basename $h)" | head -n 1)
        if test -r "$header"; then
            install -m 644 $header %{buildroot}%{_includedir}/$d/private
        fi
    done
done

%fdupes  %{buildroot}%{_includedir}
%fdupes  %{buildroot}%{_datadir}/qt4
%fdupes  %{buildroot}%{_datadir}/doc/packages/%base_name
#
# we do not package qvfb, and assistant in devel-doc
#
rm %{buildroot}%{_datadir}/qt4/translations/qvfb_*.qm
rm %{buildroot}%{_datadir}/qt4/translations/assistant_*.qm
#
# install menu entries
#
%suse_update_desktop_file -i qt4config  Qt Utility     DesktopSettings
%suse_update_desktop_file -i designer4  Qt Development GUIDesigner
%suse_update_desktop_file -i linguist4  Qt Development Translation

%post -p /sbin/ldconfig
%postun -p /sbin/ldconfig

%post sql -p /sbin/ldconfig
%postun sql -p /sbin/ldconfig

%post x11 -p /sbin/ldconfig
%postun x11 -p /sbin/ldconfig

%if %with_qt3support
%post qt3support -p /sbin/ldconfig
%postun qt3support -p /sbin/ldconfig
%endif

%if %with_qtwebkit
%post -n libQtWebKit4 -p /sbin/ldconfig
%postun -n libQtWebKit4 -p /sbin/ldconfig
%endif

%if %with_phonon
%post -n libphonon4 -p /sbin/ldconfig
%postun -n libphonon4 -p /sbin/ldconfig
%endif

%files
%defattr(-,root,root,755)
%doc *.txt LICENSE.GPL3 LICENSE.LGPL

%if 0%{?snapshot} < 1
%doc changes-*
%endif

%dir %plugindir
%dir %plugindir/codecs
%dir %plugindir/script
%dir %{_datadir}/qt4
%dir %{_datadir}/qt4/translations
%dir %{_libdir}/qt4

%plugindir/codecs/*
%{_bindir}/qdbus
%{_bindir}/xmlpatterns
%{_bindir}/xmlpatternsvalidator

%{_datadir}/qt4/translations/qt_*.qm

%{_libdir}/libQtCLucene.so.*
%{_libdir}/libQtCore*.so.*
%{_libdir}/libQtDBus*.so.*
%{_libdir}/libQtNetwork*.so.*
%{_libdir}/libQtTest.so.*
%{_libdir}/libQtXml.so.*
%{_libdir}/libQtXmlPatterns.so.*

%files x11
%defattr(-,root,root,755)
%dir %plugindir/iconengines
%dir %plugindir/imageformats
%dir %plugindir/inputmethods
%dir %plugindir/accessible
%dir %plugindir/graphicssystems
%dir %plugindir/bearer
%dir %plugindir/imports
%dir %plugindir/imports/Qt
%dir %plugindir/qmltooling

%plugindir/accessible/*
%plugindir/bearer/*
%if !%with_qtwebkit
%plugindir/designer/libqdeclarativeview.so
%endif
%plugindir/graphicssystems/*
%plugindir/iconengines/*
%plugindir/imageformats/*
%plugindir/imports/Qt/*
%plugindir/inputmethods/*
%plugindir/qmltooling/libqmldbg_inspector.so
%plugindir/qmltooling/libqmldbg_tcp.so
%plugindir/script/libqtscriptdbus.so

%{_bindir}/qdbusviewer
%{_bindir}/qmlplugindump
%{_bindir}/qmlviewer
%if %with_qt3support
%{_bindir}/qtconfig
%endif

%{_datadir}/applications/qt4config.desktop
# designer.png is referenced by qt4config.desktop
%{_datadir}/pixmaps/designer.png
%{_datadir}/qt4/phrasebooks
%{_datadir}/qt4/translations/qtconfig_*.qm

%{_libdir}/libQtDeclarative.so.*
%{_libdir}/libQtDesigner*.so.*
%{_libdir}/libQtGui*.so.*
%{_libdir}/libQtHelp.so.*
%{_libdir}/libQtMultimedia.so.*
%{_libdir}/libQtOpenGL*.so.*
%{_libdir}/libQtScript.so.*
%{_libdir}/libQtScriptTools.so.*
%{_libdir}/libQtSvg.so.*

%{_sysconfdir}/rpm/macros.qt4

%if %with_qt3support
%exclude %plugindir/accessible/libqtaccessiblecompatwidgets.so
%endif

%if %with_qt3support
%files qt3support
%defattr(-,root,root,755)
%plugindir/accessible/libqtaccessiblecompatwidgets.so
%plugindir/designer/libqt3supportwidgets.so
%{_libdir}/libQt3Support*.so.*
%endif

%if %with_qtwebkit
%files -n libQtWebKit4
%defattr(-,root,root,755)
%dir %plugindir/imports/QtWebKit
%plugindir/designer/libqdeclarativeview.so
%plugindir/designer/libqwebview.so
%plugindir/imports/QtWebKit/*
%{_libdir}/libQtWebKit.so.*

%files -n libQtWebKit-devel
%defattr(-,root,root,755)
%{_includedir}/QtWebKit
%{_libdir}/libQtWebKit.la
%{_libdir}/libQtWebKit.prl
%{_libdir}/libQtWebKit.so
%{_libdir}/libjscore.a
%{_libdir}/libjscore.prl
%{_libdir}/pkgconfig/QtWebKit.pc
%endif

%files devel
%defattr(-,root,root,755)
%dir %plugindir/designer
%dir %{_includedir}/QtDeclarative
%dir %{_datadir}/qt4

%{_bindir}/designer
%{_bindir}/lconvert
%{_bindir}/linguist
%{_bindir}/lrelease
%{_bindir}/lupdate
%{_bindir}/moc
%{_bindir}/pixeltool
%{_bindir}/qdbuscpp2xml
%{_bindir}/qdbusxml2cpp
%{_bindir}/qdoc3
%{_bindir}/qhelpconverter
%{_bindir}/qhelpgenerator
%{_bindir}/qmake
%{_bindir}/qt3to4
%{_bindir}/qttracereplay
%{_bindir}/qvfb
%{_bindir}/rcc
%{_bindir}/uic
%if %with_qt3support
%{_bindir}/uic3
%endif

%{_includedir}/Qt/
%if %with_qt3support
%{_includedir}/Qt3Support
%endif
%{_includedir}/QtCore/
%{_includedir}/QtDBus/
%{_includedir}/QtDeclarative/QDeclarative*
%{_includedir}/QtDeclarative/qdeclarative*h
%{_includedir}/QtDeclarative/QtDeclarative
%{_includedir}/QtDesigner/
%{_includedir}/QtGui/
%{_includedir}/QtHelp/
%{_includedir}/QtMultimedia/
%{_includedir}/QtNetwork/
%{_includedir}/QtOpenGL/
%{_includedir}/QtScript/
%{_includedir}/QtScriptTools/
%{_includedir}/QtSql/
%{_includedir}/QtSvg/
%{_includedir}/QtTest/
%{_includedir}/QtUiTools/
%{_includedir}/QtXml/
%{_includedir}/QtXmlPatterns/

%{_datadir}/applications/designer4.desktop
%{_datadir}/applications/linguist4.desktop
%{_datadir}/pixmaps/linguist.png
%{_datadir}/qt4/mkspecs
%{_datadir}/qt4/q3porting.xml
%{_datadir}/qt4/translations/designer_*.qm
%{_datadir}/qt4/translations/linguist_*.qm

%{_libdir}/lib*.prl
%{_libdir}/lib*.so
%{_libdir}/lib*a
%{_libdir}/pkgconfig/*
%{_libdir}/qt4/bin
%{_libdir}/qt4/include
%{_libdir}/qt4/lib

%if %with_qtwebkit
%exclude %{_libdir}/libQtWebKit.la
%exclude %{_libdir}/libQtWebKit.prl
%exclude %{_libdir}/libQtWebKit.so
%exclude %{_libdir}/pkgconfig/QtWebKit.pc
%endif
%exclude %{_includedir}/QtDeclarative/private/
%exclude %{_includedir}/QtCore/private/
%exclude %{_includedir}/QtScript/private/
%exclude %{_includedir}/QtGui/private/

%files private-headers-devel
%defattr(-,root,root,755)
%{_includedir}/QtCore/private/
%{_includedir}/QtDeclarative/private/
%{_includedir}/QtGui/private/
%{_includedir}/QtScript/private/

%files sql
%defattr(-,root,root,755)
%dir %plugindir/sqldrivers
%{_libdir}/libQtSql*.so.*

%files -n libqt4-sql-sqlite
%defattr(-,root,root,755)
%plugindir/sqldrivers/libqsqlite*.so

%if %with_phonon
%files -n phonon
%defattr(-,root,root)
%dir %plugindir/phonon_backend

%files -n libphonon4
%defattr(-,root,root)
%{_libdir}/libphonon.so.*

%files -n phonon-devel
%defattr(-,root,root)
%dir %{_includedir}/phonon
%{_includedir}/phonon
%{_libdir}/libphonon.so
%{_libdir}/pkgconfig/phonon.pc

%if %with_phonon_backend
%files -n phonon-backend-gstreamer-0_10
%defattr(-,root,root)
%plugindir/phonon_backend/phonon_gstreamer.so
%{_datadir}/kde4/services/phononbackends/gstreamer.desktop

%files -n phonon-backend-xine
%defattr(-,root,root)
%{_libdir}/kde4/plugins/phonon_backend/phonon_xine.so
%{_datadir}/kde4/services/phononbackends/xine.desktop
%{_datadir}/icons/*/*/apps/phonon-xine.*
%endif
%endif

%changelog
