#
# spec file for package gnome-icon-theme
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

# norootforbuild


Name:           gnome-icon-theme
Version:        3.0.0
Release:        1
Summary:        GNOME Icon Theme
License:        LGPLv3+ | CC BY-SA V3.0
Group:          System/GUI/GNOME
Url:            http://www.gnome.org/
Source:         ftp://ftp.gnome.org/pub/gnome/sources/%{name}/2.20/%{name}-%{version}.tar.bz2
BuildRequires:  fdupes
BuildRequires:  hicolor-icon-theme
BuildRequires:  icon-naming-utils-devel
BuildRequires:  intltool
BuildRequires:  pkg-config
# To make sure the icon theme cache gets generated
Requires(post): gtk3-tools
Provides:       %{name}-devel = %{version}-%{release}
BuildRoot:      %{_tmppath}/%{name}-%{version}-build
BuildArch:      noarch

%description
The default GNOME icon theme.

%prep
%setup -q

%build
%configure
make %{?jobs:-j%jobs}

%install
%makeinstall
# Those folders disappeared in the upgrade from 2.28.0 -> 2.29.0
# FIXME: eventually no application should install any files there
mkdir -p %{buildroot}%{_datadir}/icons/gnome/scalable/actions
mkdir -p %{buildroot}%{_datadir}/icons/gnome/scalable/apps
mkdir -p %{buildroot}%{_datadir}/icons/gnome/scalable/categories
mkdir -p %{buildroot}%{_datadir}/icons/gnome/scalable/devices
mkdir -p %{buildroot}%{_datadir}/icons/gnome/scalable/emblems
mkdir -p %{buildroot}%{_datadir}/icons/gnome/scalable/emotes
mkdir -p %{buildroot}%{_datadir}/icons/gnome/scalable/mimetypes
mkdir -p %{buildroot}%{_datadir}/icons/gnome/scalable/places
mkdir -p %{buildroot}%{_datadir}/icons/gnome/scalable/status
mkdir -p %{buildroot}%{_datadir}/icons/gnome/scalable/stock/generic
%icon_theme_cache_create_ghost gnome
%fdupes %{buildroot}

%clean
rm -rf %{buildroot}

%post
%icon_theme_cache_post gnome

# No need for %%icon_theme_cache_postun in %postun since the theme won't exist anymore

%files
%defattr(-, root, root)
%doc AUTHORS COPYING COPYING_LGPL COPYING_CCBYSA3
%ghost %{_datadir}/icons/gnome/icon-theme.cache
%{_datadir}/icons/gnome/
%{_datadir}/pkgconfig/gnome-icon-theme.pc

%changelog
