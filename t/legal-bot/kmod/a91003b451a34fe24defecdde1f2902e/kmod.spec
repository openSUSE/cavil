#
# spec file for package kmod
#
# Copyright (c) 2012 SUSE LINUX Products GmbH, Nuernberg, Germany.
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



Name:           kmod
%define lname	libkmod1
Summary:        Utilities to load modules into the kernel
Version:        3
Release:        0
%define git_snapshot 0
License:        LGPL-2.1+ and GPL-2.0+
Group:          System/Kernel
Url:            http://www.politreco.com/2011/12/announce-kmod-2/

#Git-Clone:	git://git.profusion.mobi/kmod
Source:         %name-%version.tar.xz

BuildRoot:      %{_tmppath}/%{name}-%{version}-build
%if 0%{?git_snapshot}
BuildRequires:  autoconf automake libtool
%endif
BuildRequires:  pkgconfig >= 0.23 pkgconfig(liblzma) pkgconfig(zlib) xz

%description
kmod is a set of tools to handle common tasks with Linux kernel
modules like insert, remove, list, check properties, resolve
dependencies and aliases.

These tools are designed on top of libkmod, a library that is shipped
with kmod. The aim is to be compatible with tools, configurations and
indexes from module-init-tools project.

%package compat
Summary:        Compat symlinks for kernel module utilities
License:        GPL-2.0+
Group:          System/Kernel
Conflicts:      module-init-tools

%description compat
kmod is a set of tools to handle common tasks with Linux kernel
modules like insert, remove, list, check properties, resolve
dependencies and aliases.

This package contains traditional name symlinks (lsmod, etc.)

%package -n %lname
Summary:        Library to interact with Linux kernel modules
License:        LGPL-2.1+
Group:          System/Libraries

%description -n %lname
libkmod was created to allow programs to easily insert, remove and
list modules, also checking its properties, dependencies and aliases.

%package -n libkmod-devel
Summary:        Development files for libkmod
Group:          Development/Libraries/C and C++
License:        LGPL-2.1+
Requires:       %lname = %version

%description -n libkmod-devel
libkmod was created to allow programs to easily insert, remove and
list modules, also checking its properties, dependencies and aliases.

%prep
%setup -q

%build
%if 0%{?git_snapshot}
if [ ! -e configure ]; then
	autoreconf -fi;
fi;
%endif
# The extra --includedir gives us the possibility to detect dependent
# packages which fail to properly use pkgconfig.
%configure --with-xz --with-zlib --includedir=%_includedir/%name-%version \
	--with-rootlibdir=/%_lib --bindir=/bin
make %{?_smp_mflags}

%install
b="%buildroot";
%make_install
# Remove standalone tools
rm -f "$b/bin"/kmod-*;
rm -f "$b/%_libdir"/*.la;

# kmod-compat
mkdir -p "$b/bin" "$b/sbin";
ln -s kmod "$b/bin/lsmod";
for i in depmod insmod lsmod modinfo modprobe rmmod; do
	ln -s "/bin/kmod" "$b/sbin/$i";
done;

%check
make check

%post -n %lname -p /sbin/ldconfig

%postun -n %lname -p /sbin/ldconfig

%files
%defattr(-,root,root)
/bin/kmod

%files -n %lname
%defattr(-,root,root)
/%_lib/libkmod.so.1*

%files -n libkmod-devel
%defattr(-,root,root)
%_includedir/*
%_libdir/pkgconfig/*.pc
%_libdir/libkmod.so

%files compat
%defattr(-,root,root)
/bin/lsmod
/sbin/*

%changelog
