#
# spec file for package libqt4-devel-doc
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


Name:           libqt4-devel-doc
BuildRequires:  Mesa-devel
BuildRequires:  alsa-devel
BuildRequires:  cups-devel
BuildRequires:  fdupes
BuildRequires:  freeglut-devel
BuildRequires:  gtk2-devel
BuildRequires:  libjpeg-devel
BuildRequires:  libpng-devel
BuildRequires:  sqlite3-devel
%if 0%{?suse_version}
BuildRequires:  update-desktop-files
%endif
Summary:        Qt documentation
License:        SUSE-LGPL-2.1-with-digia-exception-1.1 or GPL-3.0
Group:          Documentation/HTML
Url:            http://qt.digia.com/
# COMMON-VERSION-BEGIN
# COMMON-VERSION-BEGIN
%define base_name libqt4
%define tar_version everywhere-opensource-src-%{version}
Version:        4.8.4
Release:        0
# COMMON-VERSION-END
# COMMON-VERSION-END
BuildRequires:  libQtWebKit-devel >= %{version}
BuildRequires:  libqt4-devel >= %{version}
Requires:       libqt4 = %{version}
Requires:       libqt4-devel-doc-data = %{version}
Requires:       libqt4-sql-sqlite >= %{version}
Provides:       libqt4-examples = 4.4.0
Obsoletes:      libqt4-examples < 4.4.0
Provides:       qt-devel-doc = 4.4.0
Obsoletes:      qt-devel-doc < 4.4.0
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
%package -n qt4-x11-tools
Summary:        C++ Program Library, Core Components
Group:          System/Libraries
Requires:       libqt4-x11 >= %{version}

%description -n qt4-x11-tools
Qt is a set of libraries for developing applications.

This package contains base tools, like string, xml, and network
handling.

%package data
Summary:        C++ Program Library, Core Components
Group:          System/Libraries
Requires:       %{name} = %{version}
BuildArch:      noarch

%description data
The architecture independent data files for the documentation.
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

%ifarch ppc64
export RPM_OPT_FLAGS="%{optflags} -mminimal-toc"
%endif
export QTDIR=$PWD
export PATH=$PWD/bin:$PATH
export LD_LIBRARY_PATH=$PWD/lib/
export CXXFLAGS="%{optflags}"
export CFLAGS="%{optflags}"
export MAKEFLAGS="%{?_smp_mflags}"
%ifarch sparc64
platform="-platform linux-g++-64"
%else
platform=""
%endif
echo yes | ./configure %common_options $platform \
	-webkit -xmlpatterns -no-sql-sqlite -no-sql-sqlite2 -no-sql-mysql
%check_config

# Simply use the binaries from the -devel package instead of building it again
rpm -ql libqt4-devel | grep %{_bindir}/ | sed 's#%{_bindir}/##' | \
    ( while read file; do test -e bin/$file || ln -s %{_bindir}/$file bin/ ; done )
rpm -ql libqt4-devel | grep %{_libdir}/lib | sed 's#%{_libdir}/##' | \
    ( while read file; do test -e lib/$file || ln -s %{_libdir}/$file lib/ ; done )
rpm -ql libQtWebKit-devel | grep %{_bindir}/ | sed 's#%{_bindir}/##' | \
    ( while read file; do test -e bin/$file || ln -s %{_bindir}/$file bin/ ; done )
rpm -ql libQtWebKit-devel | grep %{_libdir}/lib | sed 's#%{_libdir}/##' | \
    ( while read file; do test -e lib/$file || ln -s %{_libdir}/$file lib/ ; done )

make %{?_smp_mflags} -C tools/assistant
make %{?_smp_mflags} -C demos
make %{?_smp_mflags} -C examples
make %{?_smp_mflags} docs

%install
export QTDIR=$PWD
make INSTALL_ROOT=%{buildroot} -C tools/assistant install
make INSTALL_ROOT=%{buildroot} -C demos install
make INSTALL_ROOT=%{buildroot} -C examples install
mv %{buildroot}/%{_libdir}/qt4/examples/painting/svgviewer/svgviewer %{buildroot}/%{_bindir}
mv %{buildroot}/%{_libdir}/qt4/demos/browser/browser %{buildroot}/%{_bindir}/qt4-browser
ln -s %{_bindir}/svgviewer %{buildroot}/%{_libdir}/qt4/examples/painting/svgviewer/svgviewer
ln -s %{_bindir}/qt4-browser %{buildroot}/%{_libdir}/qt4/demos/browser/browser

# htmldocs are not generated - why?
for d in docimages qchdocs htmldocs ; do
  make INSTALL_ROOT=%{buildroot} install_${d}
done

# remove some executable flags from image files:
find %{buildroot}%{_datadir} -name "*.png" -print0 | xargs -0 chmod a-x
find %{buildroot}%{_datadir} -name "*.css" -print0 | xargs -0 chmod a-x
find %{buildroot}%{_datadir} -name "*.js" -print0 | xargs -0 chmod a-x

# remove executable flags from source files:
find %{buildroot}%{_libdir}/qt4/examples -name "*.h" -print0 | xargs -0 chmod a-x
find %{buildroot}%{_libdir}/qt4/examples -name "*.cpp" -print0 | xargs -0 chmod a-x

# reduce fileconflicts
for f in $(rpm -ql libqt4-devel) $(rpm -ql libqt4-x11) $(rpm -ql libqt4); do
  test -f %{buildroot}/$f && rm %{buildroot}/$f
done

find %{buildroot} -type d -print0 | xargs -0 --no-run-if-empty rmdir --ignore-fail-on-non-empty

# argggh, qmake is such a piece of <censored>
mkdir -p %{buildroot}/%{_libdir}/pkgconfig
find  %{buildroot}/%{_libdir} -type f -name '*.pc' -exec mv {} %{buildroot}/%{_libdir}/pkgconfig \;

# fix more qmake errors
mkdir -p %{buildroot}/%{_libdir}/qt
find %{buildroot}/%{_libdir} -type f -name '*la' -print -exec perl -pi -e 's, -L%{_builddir}/\S+,,g' {} \;
find %{buildroot}/%{_libdir}/pkgconfig -type f -name '*pc' -print -exec perl -pi -e 's, -L%{_builddir}/\S+,,g' {} \;
mkdir -p %{buildroot}/%_docdir/%base_name/
ln -s %{_libdir}/qt4/demos %{buildroot}/%_docdir/%base_name/demos
ln -s %{_libdir}/qt4/examples %{buildroot}/%_docdir/%base_name/examples

rm -f %{buildroot}/%{_libdir}/libQt{3,A,C,G,H,N,S,T}*
rm -f %{buildroot}/%{_libdir}/libQtXml.*
rm -rf %{buildroot}/%{_libdir}/qt4/plugins

%fdupes %{buildroot}%{_prefix}/include
%fdupes %{buildroot}%{_libdir}/qt4/
%fdupes %{buildroot}%_docdir/%base_name

# remove some executable flags from source files:
chmod ugo-x %{buildroot}%{_libdir}/qt4/examples/tutorials/modelview/*/*.h
chmod ugo-x %{buildroot}%{_libdir}/qt4/examples/tutorials/modelview/*/*.cpp

%suse_update_desktop_file -i assistant4 Qt Development Documentation

%pre
# used to be a directory, is now a binary
if [ $1 -gt 1 -a -d %{_libdir}/qt4/examples/declarative/i18n/i18n ]; then
  rm -rf %{_libdir}/qt4/examples/declarative/i18n/i18n || true
fi

%files
%defattr(-,root,root,755)
%dir %{_docdir}/%base_name
%{_bindir}/assistant
%{_bindir}/qcollectiongenerator
%{_bindir}/qtdemo
%{_datadir}/applications/assistant4.desktop
%{_datadir}/pixmaps/assistant.png
%{_docdir}/%base_name/demos
%{_docdir}/%base_name/examples
%{_libdir}/qt4/demos
%{_libdir}/qt4/examples

%files -n qt4-x11-tools
%defattr(-,root,root,755)
%{_bindir}/qt4-browser
%{_bindir}/svgviewer

%files data
%defattr(-,root,root,755)
%dir %{_datadir}/doc/packages/%base_name
%{_datadir}/doc/packages/%base_name/qch
%{_datadir}/doc/packages/%base_name/html*
%{_datadir}/doc/packages/%base_name/src

%changelog
