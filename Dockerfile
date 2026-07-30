FROM  opensuse/leap 

RUN zypper --non-interactive in -C openssl-devel vim tmux

RUN zypper --non-interactive in -C  perl-Mojolicious make gcc postgresql \
  perl-Mojo-Pg perl-Minion perl-File-Unpack perl-Cpanel-JSON-XS \
  perl-Spooky-Patterns-XS perl-Mojolicious-Plugin-OAuth2 \
  perl-BSD-Resource perl-Term-ProgressBar perl-Text-Glob perl-Module-Build-Tiny

RUN cpan Mojolicious::Plugin::Webpack Algorithm::Diff cpan Mojo::JWT 

COPY . /opt/cavil 
WORKDIR /opt/cavil

RUN chmod +x ./start.sh 
RUN chmod +x ./staging.sh 

RUN zypper --non-interactive in npm
RUN npm i 
RUN npm run build 
