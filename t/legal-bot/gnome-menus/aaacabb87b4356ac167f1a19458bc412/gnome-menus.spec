#
# spec file for package gnome-menus
#
# Copyright (c) 2011 SUSE LINUX Products GmbH, Nuernberg, Germany.
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



Name:           gnome-menus
Version:        3.0.1
Release:        1
License:        LGPLv2.1+
Summary:        The GNOME Desktop Menu
Url:            http://www.gnome.org
Group:          System/GUI/GNOME
Source:         %{name}-%{version}.tar.bz2
Source99:       baselibs.conf
# PATCH-MISSING-TAG -- See http://en.opensuse.org/Packaging/Patches
Patch3:         gnome-menus-x-suse-unimportant.patch
BuildRequires:  fdupes
BuildRequires:  glib2-devel
BuildRequires:  gobject-introspection-devel
BuildRequires:  intltool
BuildRequires:  python-devel
BuildRequires:  python-gtk
BuildRequires:  translation-update-upstream
BuildRequires:  update-desktop-files
%if 0%{?BUILD_FROM_VCS}
BuildRequires:  gnome-common
%endif
Requires:       %{name}-branding = %{version}
Recommends:     %{name}-lang
BuildRoot:      %{_tmppath}/%{name}-%{version}-build

%description
The package contains an implementation of the draft "Desktop Menu
Specification" from freedesktop.org:

http://www.freedesktop.org/Standards/menu-spec

%package -n libgnome-menu2
License:        LGPLv2.1+
Summary:        The GNOME Desktop Menu
Group:          System/GUI/GNOME
Requires:       %{name} >= %{version}
# bug437293
%ifarch ppc64
Obsoletes:      gnome-menus-64bit
%endif
#

%description -n libgnome-menu2
The package contains an implementation of the draft "Desktop Menu
Specification" from freedesktop.org:

http://www.freedesktop.org/Standards/menu-spec

%package branding-upstream
License:        LGPLv2.1+
Summary:        The GNOME Desktop Menu -- Upstream Menus Definitions
Group:          System/GUI/GNOME
Requires:       %{name} = %{version}
Provides:       %{name}-branding = %{version}
Conflicts:      otherproviders(%{name}-branding)
Supplements:    packageand(%{name}:branding-upstream)
BuildArch:      noarch
#BRAND: This package contains set of needed .menu files in
#BRAND: /etc/xdg/menus. .directory files in
#BRAND: %{_datadir}/desktop-directories/Multimedia.directory are part of
#BRAND: the main package. If you need custom one, simply it put there
#BRAND: and modify .menu file to refer to it.

%description branding-upstream
The package contains an implementation of the draft "Desktop Menu
Specification" from freedesktop.org:

http://www.freedesktop.org/Standards/menu-spec

This package provides the upstream definitions for menus.

%package -n python-gnome-menus
License:        LGPLv2.1+
Summary:        Python Bindings for the GNOME Desktop Menu
Group:          System/GUI/GNOME
Requires:       libgnome-menu2
Enhances:       %{name}
%py_requires

%description -n python-gnome-menus
The package contains an implementation of the draft "Desktop Menu
Specification" from freedesktop.org:

http://www.freedesktop.org/Standards/menu-spec

%package editor
License:        GPLv2+
Summary:        Editor for the GNOME Desktop Menu
Group:          System/GUI/GNOME
Requires:       libgnome-menu2
Requires:       python-gobject
Enhances:       %{name}
%py_requires

%description editor
The package contains an implementation of the draft "Desktop Menu
Specification" from freedesktop.org:

http://www.freedesktop.org/Standards/menu-spec

%package devel
License:        LGPLv2.1+
Summary:        The GNOME Desktop Menu
Group:          System/GUI/GNOME
Requires:       glib2-devel
Requires:       libgnome-menu2 = %{version}

%description devel
The package contains an implementation of the draft "Desktop Menu
Specification" from freedesktop.org:

http://www.freedesktop.org/Standards/menu-spec

%lang_package
%prep
%setup -q
translation-update-upstream
%patch3

%if 0%{?BUILD_FROM_VCS}
[ -x ./autogen.sh ] && NOCONFIGURE=1 ./autogen.sh
%endif

%build
%configure\
	--disable-static
make %{?jobs:-j%jobs}

%install
%makeinstall
%if 0%{?suse_version} <= 1110
%{__rm} %{buildroot}%{_datadir}/locale/ha/LC_MESSAGES/*
%{__rm} %{buildroot}%{_datadir}/locale/ig/LC_MESSAGES/*
%endif
%if 0%{?suse_version} <= 1120
%{__rm} %{buildroot}%{_datadir}/locale/en@shaw/LC_MESSAGES/*
%endif
%if 0%{?suse_version} <= 1130
%{__rm} %{buildroot}%{_datadir}/locale/kg/LC_MESSAGES/*
%endif
find %{buildroot} -type f -name "*.la" -delete -print
%find_lang %{name} %{?no_lang_C}
# Rename applications.menu to not collide with other desktops:
mv %{buildroot}%{_sysconfdir}/xdg/menus/applications.menu %{buildroot}%{_sysconfdir}/xdg/menus/gnome-applications.menu
%fdupes %{buildroot}
%suse_update_desktop_file gmenu-simple-editor
for dotdirectory in %{buildroot}%{_datadir}/desktop-directories/*.directory; do
  %suse_update_desktop_file $dotdirectory
done

%clean
rm -rf %{buildroot}

%post -n libgnome-menu2 -p /sbin/ldconfig

%postun -n libgnome-menu2 -p /sbin/ldconfig

%post editor
%desktop_database_post

%postun editor
%desktop_database_postun

%files
%defattr (-, root, root)
%doc AUTHORS COPYING COPYING.LIB ChangeLog NEWS README
%dir %{_datadir}/desktop-directories
%{_datadir}/desktop-directories/*.directory
%dir %{_sysconfdir}/xdg/menus

%files -n libgnome-menu2
%defattr (-, root, root)
%{_libdir}/libgnome-menu.so.2*
%{_libdir}/girepository-1.0/GMenu-2.0.typelib

%files lang -f %{name}.lang

%files branding-upstream
%defattr (-, root, root)
%{_sysconfdir}/xdg/menus/*.menu

%files -n python-gnome-menus
%defattr (-, root, root)
%{py_sitedir}/gmenu.so
%dir %{_datadir}/gnome-menus
%{_datadir}/gnome-menus/examples/

%files editor
%defattr (-, root, root)
%{_bindir}/gmenu-simple-editor
%{_datadir}/applications/gmenu-simple-editor.desktop
%dir %{_datadir}/gnome-menus
%{_datadir}/gnome-menus/ui/
%{py_sitedir}/GMenuSimpleEditor

%files devel
%defattr (-, root, root)
%{_includedir}/gnome-menus/
%{_libdir}/*.so
%{_libdir}/pkgconfig/*.pc
%{_datadir}/gir-1.0/GMenu-2.0.gir

%changelog
