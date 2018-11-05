#
# spec file for package timezone-java
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


Name:           timezone-java
BuildRequires:  fastjar
BuildRequires:  gcc-gij
BuildRequires:  javazic
Summary:        Timezone Descriptions
License:        BSD-3-Clause and SUSE-Public-Domain
Group:          System/Base
# COMMON-BEGIN
# COMMON-BEGIN
Version:        2012f
Release:        0
Source:         ftp://ftp.iana.org/tz/releases/tzdata%{version}.tar.gz
Source1:        ftp://ftp.iana.org/tz/releases/tzcode%{version}.tar.gz
Patch0:         tzdata-china.diff
Patch1:         tzcode-zic.diff
Patch2:         tzcode-ksh.diff
Patch3:         iso3166-uk.diff
Patch4:         tzcode-link.diff
Patch5:         tzcode-symlink.patch
# COMMON-END
# COMMON-END
Url:            http://www.gnu.org/software/libc/libc.html
PreReq:         filesystem, coreutils
BuildArch:      noarch
Provides:       tzdata-java = %{version}-%{release}
BuildRoot:      %{_tmppath}/%{name}-%{version}-build

%description
These are configuration files that describe available time zones - this
package is intended for Java Virtual Machine based on OpenJDK.



%prep
%setup -c  -a 1
# COMMON-PREP-BEGIN
# COMMON-PREP-BEGIN
%patch0
%patch1
%patch2
%patch3
%if 0%{?suse_version} < 1220
%patch4
%else
%patch5 -p1
%endif
# COMMON-PREP-END
# COMMON-PREP-END

%build
gij -jar %{_javadir}/javazic.jar -V %{version} \
    -d javazi \
    africa antarctica asia australasia europe northamerica pacificnew \
    southamerica backward etcetera solar87 solar88 solar89 systemv  \
    %{_datadir}/javazic/tzdata_jdk/gmt \
    %{_datadir}/javazic/tzdata_jdk/jdk11_backward

%install
install -d -m 0755 $RPM_BUILD_ROOT/%{_datadir}
cp -a javazi $RPM_BUILD_ROOT%{_datadir}

%files
%defattr(-,root,root)
%{_datadir}/javazi

%changelog
