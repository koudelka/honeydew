# Queues
Queues are the most critical location of state in Honeydew, a job will not be removed from the queue unless it has either been successfully executed, or been dealt with by the configured failure mode.

Honeydew includes a few basic queue modules:
 - An Mnesia queue, configurable in all the ways mnesia is, for example:
   * Run with replication (with queues running on multiple nodes)
   * Persist jobs to disk (dets)
   * Follow various safety modes ("access contexts").
 - A fast FIFO queue implemented with the `:queue` and `Map` modules.
 - An Ecto-backed queue that automatically enqueues jobs when a new row is inserted.

If you don't explicitly specify a queue to use, Honeydew will use an in-memory Mnesia store.

### Queue Options
There are various options you can pass to `start_queue/2`, see the [Honeydew](https://hexdocs.pm/honeydew/Honeydew.html) module docs.

### API Support Differences
|                        | async/3 + yield/2 |       filter/2     |     cancel/2   | async/3 + `delay_secs` | exponential retry |
|------------------------|:-----------------:|:------------------:|:--------------:|:----------------------:|:-----------------:|
| ErlangQueue (`:queue`) | ✅                | ✅<sup>1</sup>     | ✅<sup>1</sup> | ✅                     | ✅                |
| Mnesia                 | ✅                | ✅                 | ✅             | ✅                     | ✅                |
| Ecto Poll Queue        | ❌                | ❌                 | ✅             | ❌                     | ✅                |

[1] this is "slow", O(num_job)

### Queue Comparison
|                        | disk-backed<sup>1</sup> | replicated<sup>2</sup> | datastore-coordinated | auto-enqueue |
|------------------------|:-----------------------:|:----------------------:|----------------------:|-------------:|
| ErlangQueue (`:queue`) | ❌                      | ❌                     |❌                     |❌           |
| Mnesia                 | ✅ (dets)               | ❌                     |❌                     |❌           |
| Ecto Poll Queue        | ✅                      | ✅                     |✅                     |✅           |

[1] survives node crashes 

[2] assuming you chose a replicated database to back ecto (tested with cockroachdb and postgres).
    Mnesia replication may require manual intevention after a significant netsplit

### Plugability
If you want to implement your own queue, check out the included queues as a guide. Try to keep in mind where exactly your queue state lives, is your queue process(es) where jobs live, or is it a completely stateless connector for some external broker? A mix of the two?
