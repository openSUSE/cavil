#
# spec file for package timezone
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


Name:           timezone
Summary:        Timezone Descriptions
License:        BSD-3-Clause and SUSE-Public-Domain
Group:          System/Base
Url:            http://www.gnu.org/software/libc/libc.html
PreReq:         filesystem, coreutils
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
BuildRoot:      %{_tmppath}/%{name}-%{version}-build
%global AREA    Etc
%global ZONE    UTC

%description
These are configuration files that describe available time zones. You
can select an appropriate time zone for your system with YaST.



%prep
%setup -c -a 1
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

%build
unset ${!LC_*}
LANG=POSIX
LC_ALL=POSIX
AREA=%{AREA}
ZONE=%{ZONE}
export AREA LANG LC_ALL ZONE
make %{?_smp_mflags} TZDIR=%{_prefix}/share/zoneinfo CFLAGS="$RPM_OPT_FLAGS -DHAVE_GETTEXT=1 -DTZDEFAULT='\"/etc/localtime\"'" AWK=awk
make %{?_smp_mflags} TZDIR=zoneinfo AWK=awk zones
# Generate posixrules
./zic -y ./yearistype -d zoneinfo -p %{AREA}/%{ZONE}

%install
mkdir -p %{buildroot}%{_prefix}/share/zoneinfo
cp -a zoneinfo %{buildroot}%{_prefix}/share/zoneinfo/posix
cp -al %{buildroot}%{_prefix}/share/zoneinfo/posix/. %{buildroot}%{_prefix}/share/zoneinfo
cp -a zoneinfo-leaps %{buildroot}%{_prefix}/share/zoneinfo/right
mkdir -p %{buildroot}/etc
rm -f  %{buildroot}/etc/localtime
rm -f  %{buildroot}%{_prefix}/share/zoneinfo/posixrules
cp -fp %{buildroot}%{_prefix}/share/zoneinfo/%{AREA}/%{ZONE} %{buildroot}/etc/localtime
ln -sf /etc/localtime      %{buildroot}%{_prefix}/share/zoneinfo/posixrules
install -m 644 iso3166.tab %{buildroot}%{_prefix}/share/zoneinfo/iso3166.tab
install -m 644 zone.tab    %{buildroot}%{_prefix}/share/zoneinfo/zone.tab
install -D -m 755 tzselect %{buildroot}%{_bindir}/tzselect
install -D -m 755 zdump    %{buildroot}%{_sbindir}/zdump
install -D -m 755 zic      %{buildroot}%{_sbindir}/zic

%clean
rm -rf %{buildroot}

%post
if [ -f /etc/sysconfig/clock ];
then
    . /etc/sysconfig/clock
    if [ -n "$TIMEZONE" -a -f /etc/localtime -a -f /usr/share/zoneinfo/$TIMEZONE ]; then
	new=$(mktemp /etc/localtime.XXXXXXXX) || exit 1
	cp -l /usr/share/zoneinfo/$TIMEZONE $new 2>/dev/null || cp -fp /usr/share/zoneinfo/$TIMEZONE $new
	mv -f $new /etc/localtime
    else
	[ ! -f /etc/localtime ] || echo "WARNING: Not updating /etc/localtime with new zone file" >&2
    fi
fi
if [ ! -L /usr/share/zoneinfo/posixrules ]; then
   rm -f /usr/share/zoneinfo/posixrules
   ln -sf /etc/localtime /usr/share/zoneinfo/posixrules
fi
if [ -e /usr/share/zoneinfo/posixrules.rpmnew ]; then
   rm -f /usr/share/zoneinfo/posixrules.rpmnew
fi

%files
%defattr(-,root,root)
%verify(not link md5 size mtime) %config(missingok,noreplace) /etc/localtime
%verify(not link md5 size mtime) %{_prefix}/share/zoneinfo/posixrules
%{_prefix}/share/zoneinfo
%{_bindir}/tzselect
%{_sbindir}/zdump
%{_sbindir}/zic

%changelog
