# Cavil Maintenance

## Regular Maintenance

Maintenance tasks that should be performend regularly by humans.

### Cleaning up failed background jobs

Cavil is designed so that most failure conditions result in failed background jobs in the [Minion](https://minion.pm)
job queue. To investigate these you need a user account with the `admin` role. Once you have the role an entry
`Minion Dashboard` will show up in the UI menu.

On the Minion dashboard you will see job counts for all possible states. The one we are interested in is `Failed`. You
can click on the little arrow at the end of each entry in the job list to see all the associated metadata, which might
already explain what happened. For example `obs_import` jobs commonly fail with HTTP timeout errors if OBS had downtime
issues. Such cases can just be restarted by selecting the checkbox at the beginning of the job entry, and then clicking
the `Retry` button at the top.

Jobs that work on a package (look for a `pkg_$id: 1` entry, where `$id` is the package id, in the notes section of the
job metadata) claim it for their duration, and a job that died with its worker leaves that claim behind. Just retry it,
the claim names the job holding it, so the retried job takes it back. If you remove the job instead, the nightly
cleanup releases the package and requeues the work it never finished.

Not all failures will be as self explanatory as HTTP timeouts and might require more investigation.

### Maintaining the file exclude list

If you have configured an `exclude_file` in `cavil.conf`, it lets you keep whole files out of unpacking and indexing.
Its most important job is defensive: neutralizing hostile or pathological inputs that would otherwise break the
unpacker — zip bombs, archives that make `tar` loop forever, files with names that make unpacking fail, and
deliberately deep or malicious directory structures. It is also handy for cutting pure noise, such as generated code or
large vendored blobs that only clutter reports. When you find an input that hangs or fails the unpacker (often surfaced
as a stuck or failed Minion job), adding it here is usually the fix, so expect this list to grow over time.

Each line is a rule of the form `package-name-glob : filename`, where the glob is matched against the package name, so
you can scope an exclusion to a single package or a whole family of them. Lines beginning with `#` are comments. For
example:

```
# Files that make the unpacker hang or fail
buildah: test.tar
onedrive: bad-file-name.tar.xz

# Malicious deep directory structures (a glob matches a whole package family)
gcc*: pax-global-records.tar
docker: pax-global-records.tar

# Zip bombs
SecLists: zip-bomb.zip
SecLists: zbxl.zip
```

One thing to keep in mind: exclusions are applied when a package is **unpacked**, not during pattern matching. A normal
reindex (`script/cavil rindex`) re-runs the matcher against the files already on disk, so it will **not** drop files you
have just added to the exclude list. Those changes only take effect the next time a package is unpacked. To roll a
change out across packages that were already processed, re-unpack them with the paced
`script/cavil unpack --rebatch` procedure described in
[Rolling out a preprocessing change](#rolling-out-a-preprocessing-change-paced-re-unpacking) below.

## Automated Maintenance

Maintenance tasks that can be automated.

### Scheduling recurring jobs

Minion has a built-in scheduler, so recurring maintenance no longer needs an external `cron` job or systemd timer. You
register a schedule once with `script/cavil minion schedule`, and your Minion workers will dispatch the due jobs on their
own (as long as at least one worker is running).

```sh
    # Reindex everything every Saturday at 20:00
    script/cavil minion schedule -e weekly_reindexing -c '0 20 * * 6' -t reindex_all

    # Clean up obsolete reports every day at 01:00
    script/cavil minion schedule -e daily_cleanup -c '0 1 * * *' -t obsolete

    # Collect builds that died halfway, every hour
    script/cavil minion schedule -e hourly_sweep -c '25 * * * *' -t sweep_builds
```

The `-e` value is just a name for the schedule (used to update, pause, or remove it later), `-c` is a standard cron
expression, and `-t` is the Minion task to enqueue. You can list, pause, resume, and remove schedules with the same
command:

```sh
    script/cavil minion schedule                       # list all schedules
    script/cavil minion schedule -P weekly_reindexing  # pause
    script/cavil minion schedule -r weekly_reindexing  # resume
    script/cavil minion schedule -R weekly_reindexing  # remove
```

The `reindex_all` and `obsolete` tasks are exactly what the manual commands below enqueue, so scheduling them is the
recommended way to run reindexing and cleanup.

### Collecting abandoned builds

A rebuild can die halfway: a worker is killed, a job fails and is removed from the queue, an admin deletes a job that
was still running. What it leaves behind is a package claimed by a job that no longer exists. Nothing is broken - the
rows the dead build wrote are invisible to readers, and the live report is served as usual - but the package is stuck:
a reindex request for it is only written down, because the claim makes it look busy, and whoever would have acted on
that request is gone. Once a request is recorded the report page also turns read-only, since the report on screen may
no longer match the patterns that exist.

`sweep_builds` is what collects those. It takes a package over only once Minion confirms nothing is queued or running
for it, discards the abandoned rows, and requeues the build that was never finished. The nightly cleanup runs it too,
so scheduling it hourly only decides how long a stuck package stays stuck - a day, or an hour. It is cheap enough for
that: the usual answer, that there is nothing to collect, is a handful of indexed lookups.

### Weekly reindexing

To keep your reports and checksums fresh even after new license patterns have been added or updated, we recommend
reindexing in regular intervals (we do it every weekend). Schedule the `reindex_all` task as shown above, or trigger a
one-off run manually with `script/cavil rindex`.

### Weekly cleanup

To free up space you can run cleanup in regular intervals. Schedule the `obsolete` task as shown above, or trigger a
one-off run manually with `script/cavil cleanup`. It helps to organize reports into products to exclude them from
cleanup.

### Refreshing snippet resolutions

When snippet folding is enabled, each snippet occurrence carries a stored resolution (`fold`, `clear`, `overlap`, or
unresolved) that the report, file browser, SPDX export and Classify Snippets filter all read. It is recomputed
automatically whenever a package is reindexed, so the weekly `script/cavil rindex` keeps it current. After changing a
fold/clear/overlap threshold you can apply the new decision without a full reindex by running `script/cavil snippets
--resolve`, which recomputes the resolutions for every package (much cheaper than reindexing, but still substantial at
scale). If the similarity scorer itself changed, run `script/cavil snippets --rescore` first, since resolutions are
derived from those scores. The scores are built from per-license fingerprints that Cavil keeps in the database and
updates automatically as patterns change; only if the way snippets are turned into those fingerprints ever changes do you
need to rebuild them in bulk with `script/cavil patterns --backfill-shingles` before re-scoring.

### Rolling out a preprocessing change (paced re-unpacking)

A reindex (`script/cavil rindex`) re-runs pattern matching against the *already unpacked* files, so it does **not**
pick up a change to the preprocessing step (for example the HTML/XML markup stripping). Those changes only take effect
when a package is **re-unpacked**, which is far more expensive, so it should be spread out rather than triggered for the
whole fleet at once.

`script/cavil unpack --rebatch` re-unpacks one batch of the oldest non-obsolete packages and prints the newest package
id it reached as the offset for the next call. The jobs are enqueued at a low Minion priority (below normal imports), so
they yield to live review traffic and cascade through index/analyze/report on their own. Work through the fleet at
whatever pace your workload allows:

```sh
    # Start at the beginning (500 packages by default)
    script/cavil unpack --rebatch
    # -> "Next offset: 67890"

    # Later, when the workers have drained, continue from that offset (larger batch, say)
    script/cavil unpack --rebatch 67890 --batch 1000
    # -> "Next offset: 143120"
```

Repeat until it prints `Caught up`. Because it always starts from the oldest packages and advances by id, it is safe to
stop and resume at any time. If the change ever needs to be rolled back, revert it and run the same catch-up again.
