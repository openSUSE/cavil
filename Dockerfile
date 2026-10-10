FROM opensuse/leap:16.0

# Cavil-specific Perl modules (perl-Cavil-Matcher, perl-File-Unpack2, ...) live in
# the devel:languages:perl OBS project, not the default Leap repositories.
RUN zypper --non-interactive ar -f \
      https://download.opensuse.org/repositories/devel:/languages:/perl/16.0/devel:languages:perl.repo && \
    zypper --non-interactive --gpg-auto-import-keys ref

# Runtime + build dependencies. Kept in sync with the dependency list in README.md.
RUN zypper --non-interactive in -C \
      openssl-devel make gcc npm vim tmux \
      postgresql-server postgresql-contrib \
      perl-Mojolicious perl-Mojolicious-Plugin-Webpack perl-Mojo-Pg perl-Minion \
      perl-File-Unpack2 perl-HTML-Parser perl-Cpanel-JSON-XS perl-Cavil-Matcher \
      perl-Mojolicious-Plugin-OAuth2 perl-Mojo-JWT perl-BSD-Resource \
      perl-Term-ProgressBar perl-Text-Glob perl-IPC-Run perl-Try-Tiny perl-MCP \
      perl-CommonMark perl-CryptX perl-Algorithm-Diff \
      git git-lfs tar xz cpio rpm unzip binutils gzip bzip2 sharutils \
      poppler-tools mkisofs 7zip cabextract lzip file shared-mime-info

COPY . /opt/cavil
WORKDIR /opt/cavil

RUN chmod +x ./start.sh ./staging.sh

RUN npm i
RUN npm run build
