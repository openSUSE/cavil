#
# spec file for package wxGTK3-3_2
#
# Copyright (c) 2018 SUSE LINUX GmbH, Nuernberg, Germany.
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


Name:           wxGTK3-3_2
%define base_name wxWidgets-3_2
%define tarball_name wxWidgets
%define variant suse
%define sonum 5
Version:        3.1.1~2640
Release:        0
%define wx_minor 3.1
%define wx_micro 3.1.1
# build non-UI toolkit related packages
%define         base_packages 0
Summary:        C++ Library for Cross-Platform Development
License:        LGPL-2.1+ WITH WxWindows-exception-3.1
Group:          Development/Libraries/C and C++
Url:            http://www.wxwidgets.org/
Source:         %tarball_name-%version.tar.xz
Source2:        README.SUSE
Source5:        wxWidgets-3_2-rpmlintrc
# This script is not used during build, but it makes possible to
# identify and backport wxPython fixes to wxWidgets.
Source6:        wxpython-mkdiff.sh
Patch1:         soversion.diff
Patch2:         wxqt-compile.diff
BuildRoot:      %{_tmppath}/%{name}-%{version}-build
BuildRequires:  SDL-devel
BuildRequires:  autoconf
BuildRequires:  cppunit-devel
BuildRequires:  gcc-c++
BuildRequires:  gstreamer-devel
BuildRequires:  gstreamer-plugins-base-devel
BuildRequires:  pkgconfig(gtk+-3.0)
%define gtk_version 3
%define toolkit gtk%gtk_version
%if 0%{?suse_version} >= 1220
BuildRequires:  libSM-devel
%else
%if 0%{?sles_version} >= 11
BuildRequires:  xorg-x11-libSM-devel
%endif
%endif
BuildRequires:  libexpat-devel
BuildRequires:  libjpeg-devel
BuildRequires:  libmspack-devel
BuildRequires:  libnotify-devel
BuildRequires:  libpng-devel
BuildRequires:  libtiff-devel
BuildRequires:  zlib-devel
BuildRequires:  pkgconfig(glu)

%description
wxWidgets is a C++ library for cross-platform GUI.
With wxWidgets, you can create applications for different GUIs (GTK+,
Motif, MS Windows, MacOS X, Windows CE, GPE) from the same source code.

%package -n libwx_baseu-%variant%sonum
Summary:        wxWidgets Library
# Name up to openSUSE 11.3 and up to wxGTK-2.8:
Group:          System/Libraries
Obsoletes:      wxGTK <= %version.0
# Third party base package name:
Obsoletes:      wxWidgets < %version
Provides:       wxWidgets = %version
Recommends:     wxWidgets-lang >= 3.0

%description -n libwx_baseu-%variant%sonum
Library for the wxWidgets cross-platform GUI.

%package -n libwx_baseu_net-%variant%sonum
Summary:        wxWidgets Library
Group:          System/Libraries

%description -n libwx_baseu_net-%variant%sonum
Library for the wxWidgets cross-platform GUI.

%package -n libwx_baseu_xml-%variant%sonum
Summary:        wxWidgets Library
Group:          System/Libraries

%description -n libwx_baseu_xml-%variant%sonum
Library for the wxWidgets cross-platform GUI.

%package -n libwx_%{toolkit}u_adv-%variant%sonum
Summary:        wxWidgets Library
Group:          System/Libraries

%description -n libwx_%{toolkit}u_adv-%variant%sonum
Library for the wxWidgets cross-platform GUI.

%package -n libwx_%{toolkit}u_aui-%variant%sonum
Summary:        wxWidgets Library
Group:          System/Libraries

%description -n libwx_%{toolkit}u_aui-%variant%sonum
Library for the wxWidgets cross-platform GUI.

%package -n libwx_%{toolkit}u_core-%variant%sonum
Summary:        wxWidgets Library
Group:          System/Libraries

%description -n libwx_%{toolkit}u_core-%variant%sonum
Library for the wxWidgets cross-platform GUI.

%package -n libwx_%{toolkit}u_gl-%variant%sonum
Summary:        wxWidgets Library
Group:          System/Libraries

%description -n libwx_%{toolkit}u_gl-%variant%sonum
Library for the wxWidgets cross-platform GUI.

%package -n libwx_%{toolkit}u_html-%variant%sonum
Summary:        wxWidgets Library
Group:          System/Libraries

%description -n libwx_%{toolkit}u_html-%variant%sonum
Library for the wxWidgets cross-platform GUI.

%package -n libwx_%{toolkit}u_media-%variant%sonum
Summary:        wxWidgets Library
Group:          System/Libraries

%description -n libwx_%{toolkit}u_media-%variant%sonum
Library for the wxWidgets cross-platform GUI.

%package -n libwx_%{toolkit}u_propgrid-%variant%sonum
Summary:        wxWidgets Library
Group:          System/Libraries

%description -n libwx_%{toolkit}u_propgrid-%variant%sonum
Library for the wxWidgets cross-platform GUI.

%package -n libwx_%{toolkit}u_qa-%variant%sonum
Summary:        wxWidgets Library
Group:          System/Libraries

%description -n libwx_%{toolkit}u_qa-%variant%sonum
Library for the wxWidgets cross-platform GUI.

%package -n libwx_%{toolkit}u_ribbon-%variant%sonum
Summary:        wxWidgets Library
Group:          System/Libraries

%description -n libwx_%{toolkit}u_ribbon-%variant%sonum
Library for the wxWidgets cross-platform GUI.

%package -n libwx_%{toolkit}u_richtext-%variant%sonum
Summary:        wxWidgets Library
Group:          System/Libraries

%description -n libwx_%{toolkit}u_richtext-%variant%sonum
Library for the wxWidgets cross-platform GUI.

%package -n libwx_%{toolkit}u_stc-%variant%sonum
Summary:        wxWidgets Library
Group:          System/Libraries

%description -n libwx_%{toolkit}u_stc-%variant%sonum
Library for the wxWidgets cross-platform GUI.

%package -n libwx_%{toolkit}u_xrc-%variant%sonum
Summary:        wxWidgets Library
Group:          System/Libraries

%description -n libwx_%{toolkit}u_xrc-%variant%sonum
Library for the wxWidgets cross-platform GUI.

%package plugin-sound_sdlu-3_2
Summary:        wxWidgets SDL Plugin
Group:          System/Libraries

%description plugin-sound_sdlu-3_2
SDL Plugin for the wxWidgets cross-platform GUI.

%package devel
Summary:        Development files for GTK3-backed wxWidgets 3.2
Group:          Development/Libraries/C and C++
Requires:       gtk%gtk_version-devel
Requires:       libwx_%{toolkit}u_adv-%variant%sonum = %version
Requires:       libwx_%{toolkit}u_aui-%variant%sonum = %version
Requires:       libwx_%{toolkit}u_core-%variant%sonum = %version
Requires:       libwx_%{toolkit}u_gl-%variant%sonum = %version
Requires:       libwx_%{toolkit}u_html-%variant%sonum = %version
Requires:       libwx_%{toolkit}u_media-%variant%sonum = %version
Requires:       libwx_%{toolkit}u_propgrid-%variant%sonum = %version
Requires:       libwx_%{toolkit}u_qa-%variant%sonum = %version
Requires:       libwx_%{toolkit}u_ribbon-%variant%sonum = %version
Requires:       libwx_%{toolkit}u_richtext-%variant%sonum = %version
Requires:       libwx_%{toolkit}u_stc-%variant%sonum = %version
Requires:       libwx_%{toolkit}u_xrc-%variant%sonum = %version
Requires:       libwx_baseu-%variant%sonum = %version
Requires:       libwx_baseu_net-%variant%sonum = %version
Requires:       libwx_baseu_xml-%variant%sonum = %version
Requires:       pkgconfig(gl)
Requires:       pkgconfig(glu)
Provides:       wxGTK3-devel = %version-%release
Provides:       wxWidgets-any-devel
Conflicts:      wxWidgets-any-devel

%description devel
wxWidgets is a C++ library for cross-platform GUI development.
With wxWidgets, you can create applications for different GUIs (GTK+,
Motif, MS Windows, MacOS X, Windows CE, GPE) from the same source code.

This package contains all files needed for developing with wxGTK%gtk_version.

Note: wxWidgets variant devel packages are mutually exclusive. Please
read %_docdir/%name/README.SUSE to pick a correct variant.

%prep
echo "=== RPM build flags: WX_DEBUG=0%{?WX_DEBUG}"
%setup -q -n %tarball_name-%version
%patch -P 1 -P 2 -p1
cp %{S:2} .

%build
autoconf -f -i
# NOTE: gnome-vfs is deprecated. Disabled for GTK3 build
#
# With 2.9.1:
# --enable-objc_uniquifying is relevant only for Cocoa
# --enable-accessibility is currently supported only in msw
# --enable-extended_rtti does not compile

%configure \
	--enable-vendor=%variant \
	--with-gtk=%gtk_version \
	--enable-unicode \
	--with-opengl \
	--with-libmspack \
	--with-sdl \
	--enable-ipv6 \
	--enable-mediactrl \
	--enable-optimise \
%if 0%{?WX_DEBUG}
	--enable-debug \
%else
	--disable-debug \
%endif
	--enable-stl \
	--enable-plugins
make %{?_smp_mflags}

%install
export VENDORTAG='-$variant' # only needed for non-MSW
make install DESTDIR="%buildroot"
%if !%base_packages
# Drop libraries already supplied by another packages
rm -f "%buildroot/%_libdir"/libwx_baseu{,_net,_xml}-%variant.so.%{sonum}* \
   "%buildroot/%_libdir/wx/%wx_micro"/sound_sdlu-*.so
%endif
rm -Rf %buildroot/%_datadir/locale

# HACK: Fix wx-config symlink (bug introduced in 2.9.4).
ln -sf $(echo %buildroot/%_libdir/wx/config/* | sed "s%%%buildroot%%%%") %buildroot/%_bindir/wx-config

%post   -n libwx_baseu-%variant%sonum -p /sbin/ldconfig
%postun -n libwx_baseu-%variant%sonum -p /sbin/ldconfig
%post   -n libwx_baseu_net-%variant%sonum -p /sbin/ldconfig
%postun -n libwx_baseu_net-%variant%sonum -p /sbin/ldconfig
%post   -n libwx_baseu_xml-%variant%sonum -p /sbin/ldconfig
%postun -n libwx_baseu_xml-%variant%sonum -p /sbin/ldconfig
%post   -n libwx_%{toolkit}u_adv-%variant%sonum -p /sbin/ldconfig
%postun -n libwx_%{toolkit}u_adv-%variant%sonum -p /sbin/ldconfig
%post   -n libwx_%{toolkit}u_aui-%variant%sonum -p /sbin/ldconfig
%postun -n libwx_%{toolkit}u_aui-%variant%sonum -p /sbin/ldconfig
%post   -n libwx_%{toolkit}u_core-%variant%sonum -p /sbin/ldconfig
%postun -n libwx_%{toolkit}u_core-%variant%sonum -p /sbin/ldconfig
%post   -n libwx_%{toolkit}u_gl-%variant%sonum -p /sbin/ldconfig
%postun -n libwx_%{toolkit}u_gl-%variant%sonum -p /sbin/ldconfig
%post   -n libwx_%{toolkit}u_html-%variant%sonum -p /sbin/ldconfig
%postun -n libwx_%{toolkit}u_html-%variant%sonum -p /sbin/ldconfig
%post   -n libwx_%{toolkit}u_media-%variant%sonum -p /sbin/ldconfig
%postun -n libwx_%{toolkit}u_media-%variant%sonum -p /sbin/ldconfig
%post   -n libwx_%{toolkit}u_propgrid-%variant%sonum -p /sbin/ldconfig
%postun -n libwx_%{toolkit}u_propgrid-%variant%sonum -p /sbin/ldconfig
%post   -n libwx_%{toolkit}u_qa-%variant%sonum -p /sbin/ldconfig
%postun -n libwx_%{toolkit}u_qa-%variant%sonum -p /sbin/ldconfig
%post   -n libwx_%{toolkit}u_ribbon-%variant%sonum -p /sbin/ldconfig
%postun -n libwx_%{toolkit}u_ribbon-%variant%sonum -p /sbin/ldconfig
%post   -n libwx_%{toolkit}u_richtext-%variant%sonum -p /sbin/ldconfig
%postun -n libwx_%{toolkit}u_richtext-%variant%sonum -p /sbin/ldconfig
%post   -n libwx_%{toolkit}u_stc-%variant%sonum -p /sbin/ldconfig
%postun -n libwx_%{toolkit}u_stc-%variant%sonum -p /sbin/ldconfig
%post   -n libwx_%{toolkit}u_xrc-%variant%sonum -p /sbin/ldconfig
%postun -n libwx_%{toolkit}u_xrc-%variant%sonum -p /sbin/ldconfig

%if %base_packages
%files -n libwx_baseu-%variant%sonum
%defattr (-,root,root)
%_libdir/libwx_baseu-%variant.so.%{sonum}*

%files -n libwx_baseu_net-%variant%sonum
%defattr (-,root,root)
%_libdir/libwx_baseu_net-%variant.so.%{sonum}*

%files -n libwx_baseu_xml-%variant%sonum
%defattr (-,root,root)
%_libdir/libwx_baseu_xml-%variant.so.%{sonum}*
%endif

%files -n libwx_%{toolkit}u_adv-%variant%sonum
%defattr (-,root,root)
%_libdir/libwx_%{toolkit}u_adv-%variant.so.%{sonum}*

%files -n libwx_%{toolkit}u_aui-%variant%sonum
%defattr (-,root,root)
%_libdir/libwx_%{toolkit}u_aui-%variant.so.%{sonum}*

%files -n libwx_%{toolkit}u_core-%variant%sonum
%defattr (-,root,root)
%_libdir/libwx_%{toolkit}u_core-%variant.so.%{sonum}*

%files -n libwx_%{toolkit}u_gl-%variant%sonum
%defattr (-,root,root)
%_libdir/libwx_%{toolkit}u_gl-%variant.so.%{sonum}*

%files -n libwx_%{toolkit}u_html-%variant%sonum
%defattr (-,root,root)
%_libdir/libwx_%{toolkit}u_html-%variant.so.%{sonum}*

%files -n libwx_%{toolkit}u_media-%variant%sonum
%defattr (-,root,root)
%_libdir/libwx_%{toolkit}u_media-%variant.so.%{sonum}*

%files -n libwx_%{toolkit}u_propgrid-%variant%sonum
%defattr (-,root,root)
%_libdir/libwx_%{toolkit}u_propgrid-%variant.so.%{sonum}*

%files -n libwx_%{toolkit}u_qa-%variant%sonum
%defattr (-,root,root)
%_libdir/libwx_%{toolkit}u_qa-%variant.so.%{sonum}*

%files -n libwx_%{toolkit}u_ribbon-%variant%sonum
%defattr (-,root,root)
%_libdir/libwx_%{toolkit}u_ribbon-%variant.so.%{sonum}*

%files -n libwx_%{toolkit}u_richtext-%variant%sonum
%defattr (-,root,root)
%_libdir/libwx_%{toolkit}u_richtext-%variant.so.%{sonum}*

%files -n libwx_%{toolkit}u_stc-%variant%sonum
%defattr (-,root,root)
%_libdir/libwx_%{toolkit}u_stc-%variant.so.%{sonum}*

%files -n libwx_%{toolkit}u_xrc-%variant%sonum
%defattr (-,root,root)
%_libdir/libwx_%{toolkit}u_xrc-%variant.so.%{sonum}*

%if %base_packages
%files plugin-sound_sdlu-3_2
%defattr (-,root,root)
%dir %_libdir/wx
%dir %_libdir/wx/%wx_micro
%_libdir/wx/%wx_micro/sound_sdlu-%wx_micro.so
%endif

%files devel
%defattr (-,root,root)
# Complete documentation is available in the docs packages.
%doc docs/*.txt README.SUSE
%_bindir/wxrc
%_bindir/wxrc-%wx_minor
%_bindir/*-config*
%_datadir/aclocal
%_datadir/bakefile
%_includedir/wx-%wx_minor
%_libdir/*.so
%dir %_libdir/wx
%_libdir/wx/config
%_libdir/wx/include

%changelog
