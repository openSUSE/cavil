#
# spec file for package gtk-vnc2
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


%define build_for_gtk2 1

%if !%{build_for_gtk2}
%define _sover -2_0-0
%define _sonamever 2.0
%define _sonamepkg 2_0
%else
%define _sover -1_0-0
%define _sonamever 1.0
%define _sonamepkg 1_0
%endif

Name:           gtk-vnc2
%define _name   gtk-vnc
BuildRequires:  cyrus-sasl-devel
BuildRequires:  gobject-introspection-devel
%if %{build_for_gtk2}
BuildRequires:  gtk2-devel
%else
BuildRequires:  gtk3-devel
%endif
BuildRequires:  intltool
BuildRequires:  libgcrypt-devel
BuildRequires:  libtool
%if %{build_for_gtk2}
BuildRequires:  python-devel
BuildRequires:  python-gtk-devel
%endif
BuildRequires:  translation-update-upstream
%if ! %{build_for_gtk2}
BuildRequires:  vala
%endif
BuildRequires:  pkgconfig(gnutls) >= 1.4.0
BuildRequires:  pkgconfig(libpulse-simple)
Summary:        A GTK widget for VNC clients
License:        LGPL-2.1 and LGPL-2.1+
Group:          Development/Libraries/X11
Version:        0.5.2
Release:        0
# FIXME: see if the browser plugin can be built (last try 0.4.2)
Source:         http://download.gnome.org/sources/gtk-vnc/0.5/%{_name}-%{version}.tar.xz
BuildRoot:      %{_tmppath}/%{name}-%{version}-build
Url:            http://gtk-vnc.sf.net/

%description
gtk-vnc is a VNC viewer widget for GTK+. It is built using coroutines
allowing it to be completely asynchronous while remaining single
threaded.

%package -n libgvnc-1_0-0
Summary:        GObject-based library to interact with the RFB protocol
License:        LGPL-2.1 and LGPL-2.1+
Group:          Development/Libraries/X11

%description  -n libgvnc-1_0-0
gtk-vnc is a VNC viewer widget for GTK+. It is built using coroutines
allowing it to be completely asynchronous while remaining single
threaded.

This package contains the GObject-based library to interact with the
RFB protocol.

%package -n typelib-1_0-GVnc-1_0
Summary:        GObject-based library to interact with the RFB protocol -- Introspection bindings
License:        LGPL-2.1 and LGPL-2.1+
Group:          System/Libraries

%description -n typelib-1_0-GVnc-1_0
gtk-vnc is a VNC viewer widget for GTK+. It is built using coroutines
allowing it to be completely asynchronous while remaining single
threaded.

This package provides the GObject Introspection bindings for the libgvnc
library.

%package -n libgvncpulse-1_0-0
Summary:        Pulse audio bridge for VNC client connections
License:        LGPL-2.1 and LGPL-2.1+
Group:          Development/Libraries/X11

%description  -n libgvncpulse-1_0-0
gtk-vnc is a VNC viewer widget for GTK+. It is built using coroutines
allowing it to be completely asynchronous while remaining single
threaded.

This package contains the Pulse audio bridge for VNC client connections.

%package -n typelib-1_0-GVncPulse-1_0
Summary:        Pulse audio bridge for VNC client connections -- Introspection bindings
License:        LGPL-2.1 and LGPL-2.1+
Group:          System/Libraries

%description -n typelib-1_0-GVncPulse-1_0
gtk-vnc is a VNC viewer widget for GTK+. It is built using coroutines
allowing it to be completely asynchronous while remaining single
threaded.

This package provides the GObject Introspection bindings for the
libgvncpulse library.

%package -n libgtk-vnc%{_sover}

Summary:        A GTK widget for VNC clients
License:        LGPL-2.1 and LGPL-2.1+
Group:          Development/Libraries/X11
Recommends:     %{name}-lang
# Needed to make lang package installable (and because we used to
# have a gtk-vnc package earlier).
Provides:       %{name} = %{version}
Obsoletes:      %{name} < %{version}

%description  -n libgtk-vnc%{_sover}
gtk-vnc is a VNC viewer widget for GTK+. It is built using coroutines
allowing it to be completely asynchronous while remaining single
threaded.

%package -n typelib-1_0-GtkVnc-%{_sonamepkg}
Summary:        A GTK widget for VNC clients -- Introspection bindings
License:        LGPL-2.1 and LGPL-2.1+
Group:          System/Libraries

%description -n typelib-1_0-GtkVnc-%{_sonamepkg}
gtk-vnc is a VNC viewer widget for GTK+. It is built using coroutines
allowing it to be completely asynchronous while remaining single
threaded.

This package provides the GObject Introspection bindings for the
libgtk-vnc library.

%package tools
Summary:        VNC Tools based on gtk-vnc
License:        LGPL-2.1 and LGPL-2.1+
Group:          Development/Libraries/X11

%description tools
This package contains tools based on gtk-vnc:

 - gvnccapture: a tool to capture a screenshot of the VNC desktop

 - gvncviewer: a simple VNC client

%package devel
Summary:        A GTK widget for VNC clients -- Development Files
License:        LGPL-2.1+
Group:          Development/Libraries/X11
Requires:       libgtk-vnc%{_sover} = %{version}
Requires:       libgvnc-1_0-0 = %{version}
Requires:       libgvncpulse-1_0-0 = %{version}
Requires:       typelib-1_0-GVnc-1_0 = %{version}
Requires:       typelib-1_0-GVncPulse-1_0 = %{version}
Requires:       typelib-1_0-GtkVnc-%{_sonamepkg} = %{version}

%description devel
gtk-vnc is a VNC viewer widget for GTK+. It is built using coroutines
allowing it to be completely asynchronous while remaining single
threaded.

%if %{build_for_gtk2}

%package -n python-gtk-vnc

Summary:        Python bindings for the gtk-vnc library
License:        LGPL-2.1+
Group:          Development/Libraries/X11
Provides:       gtk-vnc-python = %{version}
Obsoletes:      gtk-vnc-python < %{version}
%py_requires

%description -n python-gtk-vnc
gtk-vnc is a VNC viewer widget for GTK+. It is built using coroutines
allowing it to be completely asynchronous while remaining single
threaded.

This package contains the python bindings for gtk-vnc.
%endif

%lang_package

%prep
%setup -q -n %{_name}-%{version}
translation-update-upstream

%build
# We use --with-examples since this will build gvncviewer, which is neat
%configure --disable-static --with-pic \
%if %{build_for_gtk2}
        --with-gtk=2.0\
%else
        --with-gtk=3.0\
%endif
        --with-examples
%{__make} %{?jobs:-j%jobs} V=1

%install
%makeinstall
%if %{build_for_gtk2}
rm %{buildroot}%{py_sitedir}/gtkvnc.*a
# Files that will come with gtk3 build
rm -r %{buildroot}%{_includedir}/{gvnc-1.0/,gvncpulse-1.0/}
rm %{buildroot}%{_libdir}/{libgvnc-1.0.so*,libgvncpulse-1.0.so*}
rm %{buildroot}%{_libdir}/pkgconfig/{gvnc-1.0.pc,gvncpulse-1.0.pc}
rm %{buildroot}%{_datadir}/gir-1.0/{GVnc-1.0.gir,GVncPulse-1.0.gir}
rm %{buildroot}%{_libdir}/girepository-1.0/{GVnc-1.0.typelib,GVncPulse-1.0.typelib}
rm %{buildroot}%{_bindir}/gvnccapture
rm %{buildroot}%{_bindir}/gvncviewer
rm %{buildroot}%{_mandir}/man1/gvnccapture.1*
%endif
%{__rm} -f %{buildroot}%{_libdir}/*.la
%find_lang %{_name}

%clean
rm -rf $RPM_BUILD_ROOT

%postun  -n libgvnc-1_0-0 -p /sbin/ldconfig

%post  -n libgvnc-1_0-0 -p /sbin/ldconfig

%postun  -n libgvncpulse-1_0-0 -p /sbin/ldconfig

%post  -n libgvncpulse-1_0-0 -p /sbin/ldconfig

%postun  -n libgtk-vnc%{_sover} -p /sbin/ldconfig

%post  -n libgtk-vnc%{_sover} -p /sbin/ldconfig

%if !%{build_for_gtk2}

%files -n libgvnc-1_0-0
%defattr(-, root, root)
%doc AUTHORS COPYING.LIB ChangeLog NEWS README
%{_libdir}/libgvnc-1.0.so.0*

%files -n typelib-1_0-GVnc-1_0
%defattr(-,root,root)
%{_libdir}/girepository-1.0/GVnc-1.0.typelib

%files -n libgvncpulse-1_0-0
%defattr(-, root, root)
%doc AUTHORS COPYING.LIB ChangeLog NEWS README
%{_libdir}/libgvncpulse-1.0.so.0*

%files -n typelib-1_0-GVncPulse-1_0
%defattr(-,root,root)
%{_libdir}/girepository-1.0/GVncPulse-1.0.typelib

%endif

%files -n libgtk-vnc%{_sover}
%defattr(-, root, root)
%doc AUTHORS COPYING.LIB ChangeLog NEWS README
%{_libdir}/libgtk-vnc-%{_sonamever}.so.0*

%files -n typelib-1_0-GtkVnc-%{_sonamepkg}
%defattr(-,root,root)
%{_libdir}/girepository-1.0/GtkVnc-%{_sonamever}.typelib

%if !%{build_for_gtk2}

%files tools
%defattr(-, root, root)
%{_bindir}/gvnccapture
%{_bindir}/gvncviewer
%{_mandir}/man1/gvnccapture.1*
%endif

%if %{build_for_gtk2}

%files -n python-gtk-vnc
%defattr(-, root, root)
%doc examples/gvncviewer-bindings.py
%doc examples/gvncviewer-introspection.py
%{py_sitedir}/gtkvnc.so
%endif

%files devel
%defattr(-, root, root)
%if !%{build_for_gtk2}
%{_includedir}/gvnc-1.0/
%{_includedir}/gvncpulse-1.0/
%{_libdir}/libgvnc-1.0.so
%{_libdir}/libgvncpulse-1.0.so
%{_libdir}/pkgconfig/gvnc-1.0.pc
%{_libdir}/pkgconfig/gvncpulse-1.0.pc
%{_datadir}/gir-1.0/GVnc-1.0.gir
%{_datadir}/gir-1.0/GVncPulse-1.0.gir
%dir %{_datadir}/vala
%dir %{_datadir}/vala/vapi
%{_datadir}/vala/vapi/gtk-vnc-%{_sonamever}.deps
%{_datadir}/vala/vapi/gtk-vnc-%{_sonamever}.vapi
%{_datadir}/vala/vapi/gvnc-1.0.vapi
%{_datadir}/vala/vapi/gvncpulse-1.0.vapi
%endif
%{_includedir}/gtk-vnc-%{_sonamever}/
%{_libdir}/libgtk-vnc-%{_sonamever}.so
%{_libdir}/pkgconfig/gtk-vnc-%{_sonamever}.pc
%{_datadir}/gir-1.0/GtkVnc-%{_sonamever}.gir

%files lang -f %{_name}.lang

%changelog
