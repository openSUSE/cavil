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

Be aware that some jobs have locks associated with them, which need to be released before they can be retried (or they
will finish without actually performing their task). To check you can look for a `pkg_$id: 1` entry (where `$id` is the
package id) in the notes section of the job metadata. Then use the `Locks` entry at the top to search for locks with
names like `processing_pkg_$id`, and release them (simialr to how you would retry a job) before actually retrying the
job.

Not all failures will be as self explanatory as HTTP timeouts and might require more investigation.
