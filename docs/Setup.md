# Cavil Setup Guide

This guide takes you through setting up a fresh Cavil instance for production. It sticks to the essentials: what to
install, how to configure the core settings, and the order in which to bring the pieces up. Every configuration option
is documented inline in the shipped [`cavil.conf`](../cavil.conf), so this guide points you there for the details
rather than repeating them.

If you just want to try Cavil out locally, the fastest path is the staging scripts described in the
[README](../README.md#getting-started); this guide is for a real deployment.

## What you will be running

A working Cavil instance is made of a few cooperating pieces:

* **A web application** - the [Mojolicious](https://mojolicious.org) app that serves the review UI and the REST/MCP
  APIs. This is what you point your browser at.
* **One or more background workers** - [Minion](https://minion.pm) jobs do all the real work (downloading, unpacking,
  license matching, analysis, report generation). The web app only enqueues jobs; nothing happens until a worker runs.
* **A PostgreSQL database** - the single source of truth for packages, users, patterns, reports and the job queue.
* **The curated license patterns** - the 28,000+ patterns Cavil ships with, loaded into the database.
* **An AI text classifier** - a required component that separates genuine license text from scanner noise (see below).

The web app and the workers are the same program (`script/cavil`) started differently, reading the same config file.
Restart both after any configuration change.

## Prerequisites

* **PostgreSQL** with the `pgcrypto` and `pg_trgm` extensions available (any supported release). Cavil enables
  `pgcrypto` itself during migration, but the server must provide it - hence `postgresql-contrib` below.
* **Perl and system dependencies.** On openSUSE, install them as packages; the full list is in the `cpanfile` and can
  otherwise be installed from CPAN (`cpanm --installdeps .`). `Cavil::Matcher`, the pattern matching engine, is an XS
  module and needs a C++ toolchain.
* **Node.js with npm** to build the web UI assets.

```sh
sudo zypper in -C postgresql-server postgresql-contrib
sudo zypper in -C perl-Mojolicious perl-Mojolicious-Plugin-Webpack \
  perl-Mojo-Pg perl-Minion perl-File-Unpack2 perl-HTML-Parser perl-Cpanel-JSON-XS \
  perl-Cavil-Matcher perl-Mojolicious-Plugin-OAuth2 perl-Mojo-JWT \
  perl-BSD-Resource perl-Term-ProgressBar perl-Text-Glob perl-IPC-Run \
  perl-Try-Tiny perl-MCP perl-CommonMark perl-CryptX git git-lfs
```

## Setup steps

### 1. Create the database

Create an empty PostgreSQL database and make sure Cavil's database user can create the `pgcrypto` and `pg_trgm`
extensions (or create them ahead of time as a superuser). Cavil creates its own tables in step 4; do not load any
schema by hand.

### 2. Install dependencies and build the assets

From a checkout of the repository, after installing the prerequisites above:

```sh
npm i
npm run build
```

### 3. Write the configuration file

Copy the shipped `cavil.conf` as your starting point and edit it. Cavil reads whichever file you point it at with the
`CAVIL_CONF` environment variable. Every option is commented in that file; the ones you **must** set for a fresh
instance are:

* `secrets` - a list of your own random strings used to sign session cookies. Never keep the default.
* `pg` - the connection string for the database from step 1 (e.g. `postgresql://user@/cavil`).
* `checkout_dir` - a directory on a **large** disk where unpacked source is kept for reindexing.
* `tmp_dir` - a directory for incoming files before they are moved into `checkout_dir`.
* `cache_dir` - a directory for temporary files shared between indexing processes.
* `classifier` - the AI classifier connection (see step 5).
* `spdx` - the `namespace` is the base address of every identifier in the SBOMs Cavil generates, usually the address
  of your instance followed by `/spdx/`. It ends up in every published SBOM, so choose it once and keep it. There is
  no built-in fallback: until it is set, SBOMs cannot be generated.
* `openid` - OpenID Connect settings for real user login. Any standard provider works (Keycloak, Okta, Authentik,
  GitLab, Google, Microsoft Entra and others): the Cavil login is the first of the `nickname`, `preferred_username` and
  verified `email` claims the provider sends. Register `https://<your host>/oidc/callback` as the redirect URI and allow
  the `openid`, `email` and `profile` scopes. If omitted, Cavil falls back to a dummy login that makes everyone an
  admin, which is fine for a first boot but must not be left on for a shared instance. A production instance shows a
  warning banner on every page while it is.
* `admin` - the login of the first administrator, who is made admin when logging in through OpenID Connect while the
  instance has no admin yet (see step 7).

To connect Cavil to your sources (Open Build Service, Gitea, or the bot API), also set the `obs`, `git` and
`external_link_sources` options - all documented in `cavil.conf`. These can be added later.

In production mode Cavil also picks up a mode-specific config file next to your main one automatically - a
`cavil.production.conf` beside `cavil.conf` is merged on top of it - which is a convenient place to keep
production-only overrides separate from shared settings.

The configuration file is Perl, so any value can also come from an environment variable, which suits containers and
secret stores: `pg => $ENV{CAVIL_PG}` or `secrets => [$ENV{CAVIL_SECRET}]`.

### 4. Run setup

Cavil does **not** change its database on its own. The `setup` command creates the tables, loads the 28,000+ curated
license patterns (an empty instance can't recognize any license) and schedules the recurring maintenance tasks
described in the [Maintenance](Maintenance.md) guide:

```sh
CAVIL_CONF=/path/to/cavil.conf script/cavil setup
```

It only does what is still missing, so it is safe to run as often as you like, and it is the same command you run
after every upgrade (see [Upgrading](#upgrading)).

### 5. Set up the AI classifier

The keyword scanner has a false-positive rate around 80%; the classifier is what tells real license text from that
noise, and all of Cavil's automated snippet resolution builds on its verdict. Without it you get raw keyword matching
drowning in false positives, so a classifier is required for a real instance.

The [openSUSE HuggingFace org](https://huggingface.co/openSUSE) publishes models fine-tuned for this task (e.g.
`Cavil-Qwen3.5-4B`), best served with a [llama.cpp](https://github.com/ggml-org/llama.cpp) server (a GPU helps; it can
run on the Cavil host or a separate machine):

```sh
llama-server Cavil-Qwen3.5-4B.f16.gguf --host localhost --port 5000 --api-key TOKEN
```

Then add the matching block to `cavil.conf`:

```perl
classifier => {
  type  => 'llama_cpp',
  url   => 'http://localhost:5000',
  token => 'TOKEN'
}
```

Cavil runs classification automatically as new snippets come in, so there is nothing else to schedule. The only data
sent to the model is the raw candidate snippet, and **embargoed packages are never sent to the classifier** (this
exclusion is enforced in Cavil itself for compliance; do not work around it).

Cavil also still speaks the older classifier API, if you would rather run one of the legacy implementations
([Character-level-cnn-pytorch](https://github.com/kraih/Character-level-cnn-pytorch/) or
[llm-lawyer](https://github.com/kraih/llm-lawyer)). Omit the `type` key from the `classifier` block in that case.

### 6. Start the web application and workers

Run the web application with the `prefork` command in production mode, and start at least one worker. Both read
`CAVIL_CONF`:

```sh
CAVIL_CONF=/path/to/cavil.conf script/cavil prefork -m production --proxy -l http://*:4000
CAVIL_CONF=/path/to/cavil.conf script/cavil minion worker
```

Use `prefork` rather than Hypnotoad here: Hypnotoad is built for signal-driven zero-downtime reloads and only reacts to
a subset of signals, which does not fit a systemd-managed service well. Run each process as its own systemd unit. A
typical `ExecStart` for the web app, tuned to the host, looks like:

```
ExecStart=/path/to/cavil/script/cavil prefork -m production --proxy -w 20 -c 1 -i 100 -H 900 -G 800 -l http://*:4000
```

The flags let you size and tune the server (adjust the numbers to your hardware):

* `-m production` - production mode (short, systemd-friendly logs).
* `--proxy` - trust the reverse proxy's forwarding headers, so client addresses and HTTPS are seen correctly.
* `-w` - number of worker processes; `-c` - maximum concurrent connections per worker.
* `-i` / `-H` / `-G` - inactivity, heartbeat and graceful-shutdown timeouts in seconds; generous values suit
  long-running requests such as large uploads and report generation.
* `-l` - the address to listen on.

Run the worker as its own systemd unit alongside it. Its `ExecStart` is simply the `minion worker` command, with `-j`
setting how many jobs it processes in parallel (size this to the host's CPU and memory):

```
ExecStart=/path/to/cavil/script/cavil minion worker -m production -j 22
```

For a real deployment:

* **Put a reverse proxy in front of it (strongly recommended).** Run nginx (or similar) in front of the app to
  terminate TLS and forward requests, and keep the application port off the public network (firewall or a loopback
  bind). The proxy has its own request size limit (nginx `client_max_body_size` defaults to 1 MB), raise it to at
  least Cavil's `max_request_size` or large uploads fail at the proxy.
* **Run them as services under a dedicated user.** Run the web app and worker(s) as separate systemd units owned by an
  unprivileged user that owns the checkout, `checkout_dir` and config. Size the worker count and worker job concurrency
  to the host's CPU and memory (`max_worker_rss` and `max_task_memory` cap their memory use).
* **Plan for disk and backups.** The `checkout_dir` cache is the largest, fastest-growing consumer of space, so put it
  on a large volume and keep the cleanup task scheduled. Back up the database regularly and test a restore; patterns
  can also be exported with `script/cavil sync -e` as an extra copy.

### 7. Become the first admin

With `admin` set to your login in `cavil.conf` (step 3), log in through OpenID Connect and you are the administrator.
This only happens while the instance has no admin at all, so removing the role from that login later sticks as long as
someone else is admin.

Everybody else gets their roles from an admin. Users are created on first login, so you can't grant a role to someone
who hasn't signed in yet. Once they have, list the users to find their id and add a role:

```sh
CAVIL_CONF=/path/to/cavil.conf script/cavil user
CAVIL_CONF=/path/to/cavil.conf script/cavil user -A lawyer <id>
```

Roles are capability bundles: `admin` runs the instance and curates patterns, `lawyer` curates and carries the legal
sign-off, `manager` signs off as a non-lawyer expert, `contributor` proposes patterns, `classifier` classifies
snippets, and `uploader` can only make ephemeral one-off uploads. Use `-A`/`-R` to add and remove them; the full
capability matrix is in the [Architecture](Architecture.md) guide.

### 8. Review the settings

Some decisions are made in the web interface rather than in `cavil.conf`. Log in as the admin, open **Settings** from
the account menu, and check that automatic acceptance matches what your organisation is comfortable with: which risk
levels Cavil may accept without a person, and which placeholder packages are always accepted. The defaults are a
reasonable start. The same page holds the list of files Cavil should never unpack.

Two more sections connect Cavil to the outside world. Under **Bot tokens**, add one token for every bot that will
submit packages, such as the Open Build Service or Gitea integration; until there is at least one token the bot API
refuses every request. Under **SBOM**, enter the name and email address of your organisation, so the SBOMs Cavil
generates say who created them.

Finally, open **Status** to see whether anything is still missing (see below).

## Checking your instance

The **Status** section of the Settings page (admins only) checks the things a new or changed instance most often gets
wrong, and marks each one green, amber or red: the database schema, the license patterns, running workers, the
maintenance schedules, the classifier, the tools needed to unpack archives, free space for `checkout_dir`, the
`secrets`, the SBOM configuration and the login. The same checks run on the command line, which helps before the web
application is reachable, and the command fails when any check found an error:

```sh
CAVIL_CONF=/path/to/cavil.conf script/cavil doctor
```

For monitoring, load balancers and container health checks, `GET /health` answers `200 ok` as long as the web
application can reach its database, and `503` otherwise. It reveals nothing else and needs no login.

## Upgrading

A new Cavil version can change the database schema, and workers still running the old code must never meet the new
schema. So an upgrade goes like this:

1. Stop the web application, so no new work comes in.
2. Wait until the job queue is empty (the **Minion Dashboard** in the account menu shows it).
3. Stop all workers.
4. Update Cavil and rebuild the assets (`npm i && npm run build`).
5. Run `script/cavil setup`.
6. Start the workers and the web application again.

`setup` checks this for you: as long as workers are running or jobs are queued, it refuses to touch the schema and
says what is still running. When nothing needs migrating it never refuses, so it is just as safe to run on every
start.

New Cavil versions can also ship new license patterns. `setup` never adds them to an instance that already has
patterns, because lawyers may have removed or reworded some on purpose. It tells you how many shipped patterns are not
part of your instance; [Maintenance](Maintenance.md#applying-shipped-license-patterns) explains how to review and add
them.

## Next steps

Your instance is now ready to review packages. To feed it work, connect the
[OBS bot](https://github.com/openSUSE/openSUSE-release-tools) or the
[Gitea bot](https://github.com/openSUSE/cavil-gitea), upload tarballs directly from the UI, or use the REST/MCP APIs
documented in the [Bot API](BotAPI.md) and [User API](UserAPI.md) guides.

For ongoing care - reindexing after pattern updates, cleaning up obsolete reports, and retrying failed jobs, all via
Minion's built-in scheduler - see the [Maintenance](Maintenance.md) guide. For how Cavil works internally, see the
[Architecture](Architecture.md) guide.
