Honeydew 💪🏻🍈
========
[![Build Status](https://travis-ci.org/koudelka/honeydew.svg?branch=master)](https://travis-ci.org/koudelka/honeydew)
[![Hex pm](https://img.shields.io/hexpm/v/honeydew.svg?style=flat)](https://hex.pm/packages/honeydew)

Honeydew (["Honey, do!"](http://en.wiktionary.org/wiki/honey_do_list)) is a pluggable job queue + worker pool for Elixir.

- Workers are permanent and hold immutable state (a database connection, for example).
- Workers are issued only one job at a time, a job is only ever removed from the queue when it succeeds.
- Queues can exist locally, on another node in the cluster, or on a remote queue server (rabbitmq, etc...).
- If a worker crashes while processing a job, the job is recovered and a "failure mode" (abandon, move, retry, etc) is executed.
- Jobs are enqueued using `async/3` and you can receive replies with `yield/2`, somewhat like [Task](http://elixir-lang.org/docs/stable/elixir/Task.html).
- Queues, workers, dispatch strategies and failure/success modes are all plugable with user modules.
- Can optionally heal your cluster after a disconnect or downed node.

Honeydew attempts to provide "at least once" job execution, it's possible that circumstances could conspire to execute a job, and prevent Honeydew from reporting that success back to the queue. I encourage you to write your jobs idempotently.

Honeydew isn't intended as a simple resource pool, the user's code isn't executed in the requesting process. Though you may use it as such, there are likely other alternatives that would fit your situation better.


### tl;dr
- Check out the [examples](https://github.com/koudelka/honeydew/tree/master/examples).
- Enqueue and receive responses with `async/3` and `yield/2`.
- Emit job progress with `progress/1`
- Queue/Worker status with `Honeydew.status/1`
- Suspend and resume with `Honeydew.suspend/1` and `Honeydew.resume/1`
- List jobs with `Honeydew.filter/2`
- Cancel jobs with `Honeydew.cancel/2`

### Queue API Support
|                        | async/2 + yield/2 |       filter/2     |    status/1    |     cancel/2   | suspend/1 + resume/1 |
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

[2] assuming you chose a replicated database to back ecto (tested with cockroachdb). 
    Mnesia replication may require manual intevention after a significant netsplit

### Ecto Poll Queue

The Ecto Poll Queue is an experimental queue designed to painlessly turn an already-existing Ecto schema into a queue, using your repo as the backing store.

Check out the included [example project](https://github.com/koudelka/honeydew/tree/master/examples/ecto_poll_queue), and its README.

## Getting Started

In your mix.exs file:

```elixir
defp deps do
  [{:honeydew, "~> 1.0.4"}]
end
```

You can run honeydew on a single node, or distributed over a cluster. Please see the README files included with the [examples](https://github.com/koudelka/honeydew/tree/master/examples).


### Suspend and Resume
You can suspend a queue (halt the distribution of new jobs to workers), by calling `Honeydew.suspend(:my_queue)`, then resume with `Honeydew.resume(:my_queue)`.

### Cancelling Jobs
To cancel a job that hasn't yet run, use `Honeydew.cancel/2`. If the job was successfully cancelled before execution, `:ok` will be returned. If the job wasn't present in the queue, `nil`. If the job is currently being executed, `{:error, :in_progress}`.

### Job Progress
Your jobs can emit their current status, i.e. "downloaded 10/50 items", using the `progress/1` function given to your job module by `use Honeydew.Progress`

Check out the [simple example](https://github.com/koudelka/honeydew/tree/master/examples/local/simple.exs).


### Queue Options
There are various options you can pass to `queue_spec/2` and `worker_spec/3`, see the [Honeydew](https://github.com/koudelka/honeydew/blob/master/lib/honeydew.ex) module.

### Failure Modes
When a worker crashes, a monitoring process runs the `handle_failure/3` function from the selected module on the queue's node. Honeydew ships with two failure modes, at present:

- `Honeydew.FailureMode.Abandon`: Simply forgets about the job.
- `Honeydew.FailureMode.Move`: Removes the job from the original queue, and places it on another.
- `Honeydew.FailureMode.Retry`: Re-attempts the job on its original queue a number of times, then calls another failure mode after the final failure.

See `Honeydew.queue_spec/2` to select a failure mode.

### Success Modes
When a job completes successfully, the monitoring process runs the `handle_success/2` function from the selected module on the queue's node. You'll likely want to use this callback for monitoring purposes. You can use a job's `:enqueued_at`, `:started_at` and `:completed_at` fields to calculate various time intervals.

See `Honeydew.queue_spec/2` to select a success mode.

## The Dungeon

### Job Lifecycle
In general, a job goes through the following stages:

```
- The requesting process calls `async/2`, which packages the task tuple/fn up into a "job" then sends
  it to a member of the queue group.

- The queue process will enqueue the job, then take one of the following actions:
  ├─ If there is a worker available, the queue will dispatch the job immediately to the waiting
  |  worker via the selected dispatch strategy.
  └─ If there aren't any workers available, the job will remain in the queue until a worker announces
     that it's ready

- Upon dispatch, the queue "reserves" the job (marks it as in-progress), then spawns a local Monitor
  process to watch the worker. The monitor starts a timer after which the job will be returned to the queue.
  This is done to avoid blocking the queue waiting for confirmation from a worker that it has received the job.
  └─ When the worker receives the job, it informs the monitor associated with the job. The monitor
     then watches the worker in case the job crashes.
     ├─ When the job succeeds:
     |  ├─ If the job was enqueued with `reply: true`, the result is sent.
     |  ├─ The worker sends an acknowledgement message to the monitor.
     |  |─ The monitor sends an acknowledgement to the queue to remove the job.
     |  |─ The monitor executes the selected success mode
     |  └─ The worker informs the queue that it's ready for a new job. The queue checks the worker in with the
     |     dispatcher.
     └─ If the worker crashes, the monitor executes the selected failure mode and terminates.
```


### Queues
Queues are the most critical location of state in Honeydew, a job will not be removed from the queue unless it has either been successfully executed, or been dealt with by the configured failure mode.

Honeydew includes a few basic queue modules:
 - A simple FIFO queue implemented with the `:queue` and `Map` modules, this is the default.
 - An Mnesia queue, configurable in all the ways mnesia is, for example:
   * Run with replication (with queues running on multiple nodes)
   * Persist jobs to disk (dets)
   * Follow various safety modes ("access contexts").
 - An Ecto-backed queue that automatically enqueues jobs when a new row is inserted.

If you want to implement your own queue, check out the included queues as a guide. Try to keep in mind where exactly your queue state lives, is your queue process(es) where jobs live, or is it a completely stateless connector for some external broker? Or a hybrid? I'm excited to see what you come up with, please open a PR! <3

### Dispatchers
Honeydew provides the following dispatchers:

- `Honeydew.Dispatcher.LRUNode` - Least Recently Used Node (sends jobs to the least recently used worker on the least recently used node, the default for global queues)
- `Honeydew.Dispatcher.LRU` - Least Recently Used Worker (FIFO, the default for local queues)
- `Honeydew.Dispatcher.MRU` - Most Recently Used Worker (LIFO)

You can also use your own dispatching strategy by passing it to `Honeydew.queue_spec/2`. Check out the [built-in dispatchers](https://github.com/koudelka/honeydew/tree/master/lib/honeydew/dispatcher) for reference.

### Worker State
Worker state is immutable, the only way to change it is to cause the worker to crash and let the supervisor restart it.

Your worker module's `init/1` function must return `{:ok, state}`. If anything else is returned or the function raises an error, the worker will die and restart after a given time interval (by default, five seconds).

### TODO:
- let the user decide if they want to `:ignore` during their init/1, to allow errors to bubble up the supervision tree.
- statistics?
- `yield_many/2` support?
- benchmark mnesia queue's dual filter implementations, discard one?

### Acknowledgements

Thanks to Marcelo Gornstein (@marcelo), for his [failing worker restart strategy](https://web.archive.org/web/20170929101642/http://inaka.net/blog/2012/11/29/every-day-erlang/).
