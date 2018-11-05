# Cavil [![Build Status](https://travis-ci.com/openSUSE/cavil.svg?branch=master)](https://travis-ci.com/openSUSE/cavil)

  Cavil is a legal review system for the
  [Open Build Service](https://openbuildservice.org). It is used in the
  development of openSUSE Tumbleweed, openSUSE Leap, as well as SUSE Linux
  Enterprise.

![Screenshot](https://raw.github.com/openSUSE/cavil/master/examples/report.png?raw=true)

  This distribution contains the two main components of the system. A
  [Mojolicious](https://mojolicious.org) web application that lawyers can use to
  efficiently review package contents, and
  [Minion](https://metacpan.org/pod/Minion) background jobs to process and index
  packages, to create easy to digest license reports.

  Additionally there is also a small curated subset of the license patterns the
  SUSE lawyers have created included in this distribution. Currently this subset
  consists of 20 patterns each for 100 popular licenses. This library of
  patterns might be expanded in the future however.

  The easiest way to connect OBS to Cavil is the `legal-auto.py` bot from the
  [openSUSE Release Tools](https://github.com/openSUSE/openSUSE-release-tools)
  repository.

## Getting Started

  The easiest way to get started with Cavil is the included staging scripts for
  setting up a quick development environment. All you need is an empty
  PostgreSQL database and the following dependencies:

    $ sudo zypper in w3m postgresql96-server ruby2.1-rubygem-sass
    $ sudo zypper in perl-Mojolicious perl-Mojolicious-Plugin-AssetPack \
      perl-Mojo-Pg perl-Minion perl-File-Unpack perl-Cpanel-JSON-XS \
      perl-Spooky-Patterns-XS perl-Net-OpenID-Consumer perl-LWP-UserAgent \
      perl-BSD-Resource

  Then use these commands to set up and tear down a development environment:

    $ perl staging/start.pl postgresql://tester:testing@/test
    ...
    $ CAVIL_CONF=staging/do_not_commit/cavil.conf morbo script/cavil
    ...
    $ CAVIL_CONF=staging/do_not_commit/cavil.conf script/cavil minion worker
    ...
    $ perl staging/stop.pl
    ...

  The `morbo` development web server will make the web application available
  under `http://127.0.0.1:3000`. And `script/cavil minion worker` will start the
  job queue for processing background jobs.
