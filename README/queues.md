# Queues
Queues are the most critical location of state in Honeydew, a job will not be removed from the queue unless it has either been successfully executed, or been dealt with by the configured failure mode.

Honeydew includes a few basic queue modules:
 - A simple FIFO queue implemented with the `:queue` and `Map` modules, this is the default.
 - An Mnesia queue, configurable in all the ways mnesia is, for example:
   * Run with replication (with queues running on multiple nodes)
   * Persist jobs to disk (dets)
   * Follow various safety modes ("access contexts").
 - An Ecto-backed queue that automatically enqueues jobs when a new row is inserted.

If you want to implement your own queue, check out the included queues as a guide. Try to keep in mind where exactly your queue state lives, is your queue process(es) where jobs live, or is it a completely stateless connector for some external broker? A mix of the two?

### Queue Options
There are various options you can pass to `start_queue/2`, see the [Honeydew](https://github.com/koudelka/honeydew/blob/master/lib/honeydew.ex) module.

### Queue API Support
|                        | async/3 + yield/2 |       filter/2     |    status/1    |     cancel/2   | suspend/1 + resume/1 |
|------------------------|:-----------------:|:------------------:|:--------------:|:--------------:|:--------------------:|
| ErlangQueue (`:queue`) | ✅               | ✅<sup>1</sup>      | ✅             | ✅<sup>1</sup>|  ✅                  |
| Mnesia                 | ✅               | ✅<sup>1</sup>      | ✅<sup>1</sup> | ✅            |  ✅                  |
| Ecto Poll Queue        | ❌               | ❌                  | ✅             | ✅<sup>2</sup>|  ✅                  |

[1] this is "slow", O(num_job)

[2] can't return `{:error, :in_progress}`, only `:ok` or `{:error, :not_found}`

### Queue Comparison
|                        | disk-backed<sup>1</sup> | replicated<sup>2</sup> | datastore-coordinated | auto-enqueue |
|------------------------|:-----------------------:|:----------------------:|----------------------:|-------------:|
| ErlangQueue (`:queue`) | ❌                      | ❌                     |❌                     |❌           |
| Mnesia                 | ✅ (dets)               | ❌                     |❌                     |❌           |
| Ecto Poll Queue        | ✅                      | ✅                     |✅                     |✅           |

[1] survives node crashes 

[2] assuming you chose a replicated database to back ecto (tested with cockroachdb and postgres).
    Mnesia replication may require manual intevention after a significant netsplit

