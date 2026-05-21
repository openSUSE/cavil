Name:           npm-vendored
Version:        1.0
Release:        0
Summary:        Demo package with vendored NPM dependencies
License:        MIT
Group:          Development/Libraries/JavaScript
Url:            https://example.com/npm-vendored
Source0:        npm-vendored-1.0.tar.gz
BuildArch:      noarch

%description
Test fixture for Cavil's NPM vendored-dependency detector.

%prep
%setup -q

%build

%install

%files
%license LICENSE

%changelog
