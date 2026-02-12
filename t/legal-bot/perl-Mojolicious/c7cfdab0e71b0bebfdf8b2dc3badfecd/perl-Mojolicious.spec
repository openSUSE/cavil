#
# spec file for package perl-Mojolicious
#
# Copyright (c) 2017 SUSE LINUX GmbH, Nuernberg, Germany.
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


Name:           perl-Mojolicious
Version:        7.25
Release:        0
%define cpan_name Mojolicious
Summary:        Real-time web framework
License:        Artistic-2.0
Group:          Development/Libraries/Perl
Url:            http://search.cpan.org/dist/Mojolicious/
Source0:        http://www.cpan.org/authors/id/S/SR/SRI/%{cpan_name}-%{version}.tar.gz
Source1:        cpanspec.yml
BuildArch:      noarch
BuildRoot:      %{_tmppath}/%{name}-%{version}-build
BuildRequires:  perl
BuildRequires:  perl-macros
BuildRequires:  perl(IO::Socket::IP) >= 0.37
BuildRequires:  perl(JSON::PP) >= 2.27103
BuildRequires:  perl(Pod::Simple) >= 3.09
BuildRequires:  perl(Time::Local) >= 1.2
Requires:       perl(IO::Socket::IP) >= 0.37
Requires:       perl(JSON::PP) >= 2.27103
Requires:       perl(Pod::Simple) >= 3.09
Requires:       perl(Time::Local) >= 1.2
%{perl_requires}

%description
An amazing real-time web framework built on top of the powerful Mojo web
development toolkit. With support for RESTful routes, plugins, commands,
Perl-ish templates, content negotiation, session management, form
validation, testing framework, static file server, 'CGI'/'PSGI' detection,
first class Unicode support and much more for you to discover.

Take a look at our excellent documentation in Mojolicious::Guides!

%prep
%setup -q -n %{cpan_name}-%{version}
find . -type f ! -name \*.pl -print0 | xargs -0 chmod 644

%build
%{__perl} Makefile.PL INSTALLDIRS=vendor
%{__make} %{?_smp_mflags}

%check
%{__make} test

%install
%perl_make_install
%perl_process_packlist
%perl_gen_filelist

%files -f %{name}.files
%defattr(-,root,root,755)
%doc Changes examples README.md
%license LICENSE

%changelog

#
# Legal-Review-Notice: Upstream project maintained by SUSE employee
#
