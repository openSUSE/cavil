# Cavil Development Environment

The staging scripts set up a local environment for working on Cavil itself, with example data. It is made for testing
and deliberately runs without the AI classifier, because its example packages are made for testing without one. Real
packages need a classifier, so to review them, set up an instance with the [setup guide](Setup.md) instead.

## Dependencies

All you need is an empty PostgreSQL database (with the `pgcrypto` and `pg_trgm` extensions activated) and the
following dependencies:

```sh
# Install dependencies
sudo zypper in -C postgresql-server postgresql-contrib
sudo zypper in -C perl-Mojolicious perl-Mojolicious-Plugin-Webpack \
  perl-Mojo-Pg perl-Minion perl-File-Unpack2 perl-HTML-Parser perl-Cpanel-JSON-XS \
  perl-Cavil-Matcher perl-Mojolicious-Plugin-OAuth2 perl-Mojo-JWT \
  perl-BSD-Resource perl-Term-ProgressBar perl-Text-Glob perl-IPC-Run \
  perl-Try-Tiny perl-MCP perl-CommonMark perl-CryptX git git-lfs tar xz \
  cpio rpm unzip binutils gzip bzip2 sharutils poppler-tools mkisofs \
  7zip cabextract lzip file shared-mime-info
npm i

# Build JavaScript assets
npm run build
```

## Staging environment

Then use these commands to set up and tear down a development environment:

```sh
# Initialize staging environment (remove --clean to include example fixtures)
perl staging/start.pl --clean postgresql://tester:testing@/test

# Start HTTP application server under http://127.0.0.1:3000
CAVIL_CONF=staging/do_not_commit/cavil.conf morbo script/cavil

# Start background job queue (separate process that does all the actual work)
CAVIL_CONF=staging/do_not_commit/cavil.conf script/cavil minion worker

# Tear down staging environment once you are done
perl staging/stop.pl
```

The staging environment has no real authentication, so the **Login** link signs you straight in as an admin. From
there you can browse any example reports and upload a tarball of your own.
