#
# spec file for package MozillaFirefox
#
# Copyright (c) 2025 SUSE LLC
#

%define major          140
%define mainver        %major.13.0
%define orig_version   140.13.0
%define orig_suffix    esr
%define pkgname        MozillaFirefox
%define appname        Firefox
%define srcname        firefox

# An escaped percent in a comment must be left untouched: %%major.99

# Conditional define, must not be captured as a simple macro
%{!?_rpmmacrodir: %global _rpmmacrodir %{_rpmconfigdir}/macros.d}

# Shell expansion must never be evaluated
%{expand:%%global optflags %(echo "%optflags") }

# Only one branch is live at build time; we cannot evaluate the condition, so
# the first definition wins (best-effort).
%if 0%{?suse_version} > 1500
%define channel release
%else
%define channel esr
%endif

Name:           %{pkgname}
Version:        %{mainver}
Release:        0
Summary:        Mozilla %{appname} Web Browser
License:        MPL-2.0
Group:          Productivity/Networking/Web/Browsers
URL:            http://www.mozilla.org/
Source:         http://ftp.mozilla.org/pub/%{srcname}/releases/%{version}%{orig_suffix}/source/%{srcname}-%{orig_version}%{orig_suffix}.source.tar.xz
Source1:        MozillaFirefox.desktop
BuildRequires:  gcc-c++

%description
The Mozilla %{appname} web browser.
