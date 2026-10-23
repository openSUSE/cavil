FROM registry.opensuse.org/opensuse/tumbleweed AS assets
RUN zypper -n in --no-recommends nodejs-default npm-default && zypper clean -a
WORKDIR /opt/cavil
COPY . .
RUN npm ci && NODE_ENV=production npm run build

FROM registry.opensuse.org/opensuse/tumbleweed
# The perl-File-Unpack2 package only provides dependencies, Cavil needs 2.03 or newer for the unpack watchdog
RUN zypper -n in --no-recommends \
      perl-Mojolicious perl-Mojolicious-Plugin-Webpack perl-Mojo-Pg perl-Minion perl-File-Unpack2 perl-HTML-Parser \
      perl-Cpanel-JSON-XS perl-Cavil-Matcher perl-Mojolicious-Plugin-OAuth2 perl-Mojo-JWT perl-BSD-Resource \
      perl-Term-ProgressBar perl-Text-Glob perl-IPC-Run perl-Try-Tiny perl-MCP perl-CommonMark perl-CryptX \
      perl-Algorithm-Diff perl-IO-Socket-SSL perl-Text-Diff perl-YAML-LibYAML perl-JSON-Schema-Tiny perl-Digest-SHA1 \
      git git-lfs tar xz cpio rpm unzip binutils gzip bzip2 sharutils poppler-tools mkisofs 7zip cabextract lzip \
      zstd lha upx file shared-mime-info curl perl-App-cpanminus make \
    && zypper clean -a \
    && cpanm -n https://cpan.metacpan.org/authors/id/K/KR/KRAIH/File-Unpack2-2.03.tar.gz && rm -rf /root/.cpanm \
    && useradd -u 1000 -M -d /opt/cavil cavil \
    && mkdir -p /data/checkouts /data/incoming /var/cache/cavil && chown -R cavil /data /var/cache/cavil
WORKDIR /opt/cavil
COPY . .
COPY --from=assets /opt/cavil/public public
USER cavil
ENV CAVIL_CONF=/opt/cavil/docker/cavil.conf MOJO_MODE=production
VOLUME /data
EXPOSE 3000
CMD ["script/cavil", "prefork", "--proxy", "-l", "http://*:3000"]
