# Cavil Setup Guide

This guide takes you through setting up a fresh Cavil instance for production. It sticks to the essentials: what to
install, how to configure the core settings, and the order in which to bring the pieces up. Every configuration option
is documented inline in the shipped `cavil.conf`, so this guide points you there for the details rather than repeating
them.

If you just want to try Cavil out locally, the fastest path is the staging scripts described in the
[README](../README.md#getting-started); this guide is for a real deployment.

## What you will be running

A working Cavil instance is made of a few cooperating pieces:

* **A web application** — the [Mojolicious](https://mojolicious.org) app that serves the review UI and the REST/MCP
  APIs. This is what you point your browser at.
* **One or more background workers** — [Minion](https://minion.pm) jobs do all the real work (downloading, unpacking,
  license matching, analysis, report generation). The web app only enqueues jobs; nothing happens until a worker runs.
* **A PostgreSQL database** — the single source of truth for packages, users, patterns, reports and the job queue.
* **The curated license patterns** — the 28,000+ patterns Cavil ships with, loaded into the database.
* **An AI text classifier** — a required component that separates genuine license text from scanner noise (see below).

The web app and the workers are the same program (`script/cavil`) started differently, reading the same config file.
Restart both after any configuration change.

## Prerequisites

* **PostgreSQL** with the `pgcrypto` and `pg_trgm` extensions available (any supported release). Cavil enables
  `pgcrypto` itself during migration, but the server must provide it — hence `postgresql-contrib` below.
* **Perl and system dependencies.** On openSUSE, install them as packages; the full list is in the `cpanfile` and can
  otherwise be installed from CPAN (`cpanm --installdeps .`). `Spooky::Patterns::XS` is an XS module and needs a C
  toolchain.
* **Node.js with npm** to build the web UI assets.

```sh
sudo zypper in -C postgresql-server postgresql-contrib
sudo zypper in -C perl-Mojolicious perl-Mojolicious-Plugin-Webpack \
  perl-Mojo-Pg perl-Minion perl-File-Unpack2 perl-HTML-Parser perl-Cpanel-JSON-XS \
  perl-Spooky-Patterns-XS perl-Mojolicious-Plugin-OAuth2 perl-Mojo-JWT \
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

* `secrets` — a list of your own random strings used to sign session cookies. Never keep the default.
* `pg` — the connection string for the database from step 1 (e.g. `postgresql://user@/legaldb`).
* `checkout_dir` — a directory on a **large** disk where unpacked source is kept for reindexing.
* `tmp_dir` — a directory for incoming files before they are moved into `checkout_dir`.
* `cache_dir` — a directory for temporary files shared between indexing processes.
* `classifier` — the AI classifier connection (see step 6).
* `openid` — OpenID Connect settings for real user login. If omitted, Cavil falls back to a dummy login that makes
  everyone an admin, which is fine for a first boot but must not be left on for a shared instance.

To connect Cavil to your sources (Open Build Service, Gitea, or the bot API), also set the `obs`, `git`,
`external_link_sources` and `tokens` options — all documented in `cavil.conf`. These can be added later.

In production mode Cavil also picks up a mode-specific config file next to your main one automatically — a
`cavil.production.conf` beside `cavil.conf` is merged on top of it — which is a convenient place to keep
production-only overrides separate from shared settings.

### 4. Run the database migrations

Cavil does **not** migrate automatically. Run it once now, and again after every upgrade:

```sh
CAVIL_CONF=/path/to/cavil.conf script/cavil migrate
```

### 5. Load the license patterns

An empty instance can't recognize any license. Load the curated set:

```sh
CAVIL_CONF=/path/to/cavil.conf script/cavil sync -i lib/Cavil/resources/license_patterns.jsonl
```

### 6. Set up the AI classifier

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

### 7. Start the web application and workers

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

* `-m production` — production mode (short, systemd-friendly logs).
* `--proxy` — trust the reverse proxy's forwarding headers, so client addresses and HTTPS are seen correctly.
* `-w` — number of worker processes; `-c` — maximum concurrent connections per worker.
* `-i` / `-H` / `-G` — inactivity, heartbeat and graceful-shutdown timeouts in seconds; generous values suit
  long-running requests such as large uploads and report generation.
* `-l` — the address to listen on.

Run the worker as its own systemd unit alongside it. Its `ExecStart` is simply the `minion worker` command, with `-j`
setting how many jobs it processes in parallel (size this to the host's CPU and memory):

```
ExecStart=/path/to/cavil/script/cavil minion worker -m production -j 22
```

For a real deployment:

* **Put a reverse proxy in front of it (strongly recommended).** Run nginx (or similar) in front of the app to
  terminate TLS and forward requests, and keep the application port off the public network (firewall or a loopback
  bind).
* **Run them as services under a dedicated user.** Run the web app and worker(s) as separate systemd units owned by an
  unprivileged user that owns the checkout, `checkout_dir` and config. Size the worker count and worker job concurrency
  to the host's CPU and memory (`max_worker_rss` and `max_task_memory` cap their memory use).
* **Plan for disk and backups.** The `checkout_dir` cache is the largest, fastest-growing consumer of space, so put it
  on a large volume and keep the cleanup task scheduled. Back up the database regularly and test a restore; patterns
  can also be exported with `script/cavil sync -e` as an extra copy.

### 8. Create your first admin user

Users are created on first login, so you can't grant a role to someone who hasn't signed in yet:

1. Start the web app and log in once as the future administrator (with OpenID Connect this creates a `user`-role
   account).
2. List users to find its id, then grant the `admin` role:

```sh
CAVIL_CONF=/path/to/cavil.conf script/cavil user
CAVIL_CONF=/path/to/cavil.conf script/cavil user -A admin <id>
```

Roles are capability bundles: `admin` runs the instance and curates patterns, `lawyer` curates and carries the legal
sign-off, `manager` signs off as a non-lawyer expert, `contributor` proposes patterns, and `classifier` classifies
snippets. Use `-A`/`-R` to add and remove them; the full capability matrix is in the
[Architecture](Architecture.md) guide.

## Next steps

Your instance is now ready to review packages. To feed it work, connect the
[OBS bot](https://github.com/openSUSE/openSUSE-release-tools) or the
[Gitea bot](https://github.com/openSUSE/cavil-gitea), upload tarballs directly from the UI, or use the REST/MCP APIs
documented in the [API](API.md) and [User API](UserAPI.md) guides.

For ongoing care — reindexing after pattern updates, cleaning up obsolete reports, and retrying failed jobs, all via
Minion's built-in scheduler — see the [Maintenance](Maintenance.md) guide. For how Cavil works internally, see the
[Architecture](Architecture.md) guide.
