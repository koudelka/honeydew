Honeydew 💪🏻🍈
========
[![Build Status](https://travis-ci.org/koudelka/honeydew.svg?branch=master)](https://travis-ci.org/koudelka/honeydew)
[![Hex pm](https://img.shields.io/hexpm/v/honeydew.svg?style=flat)](https://hex.pm/packages/honeydew)

Honeydew (["Honey, do!"](http://en.wiktionary.org/wiki/honey_do_list)) is a pluggable job queue and worker pool for Elixir, focused on at-least-once execution.

```elixir
defmodule MyWorker do
  def do_a_thing do
    IO.puts "doing a thing!"
  end
end

:ok = Honeydew.start_queue(:my_queue)
:ok = Honeydew.start_workers(:my_queue, MyWorker)

:do_a_thing |> Honeydew.async(:my_queue)

# => "doing a thing!"
```

__Isolation__
  - Jobs are run in isolated one-time-use processes.
  - Optionally stores immutable state loaned to each worker (a database connection, for example).
  - [Initialized Worker](https://github.com/koudelka/honeydew/tree/master/examples/initialized_worker)

__Strong Job Custody__ 
  - Jobs don't leave the queue until either they succeed, are explicitly abandoned or are moved to another queue.
  - Workers are issued only one job at a time, no batching.
  - If a worker crashes while processing a job, the job is reset and a "failure mode" (e.g. abandon, move, retry) is executed.
  - [Job Lifecycle](https://github.com/koudelka/honeydew/blob/master/README/job_lifecycle.md)

__Clusterable Components__
  - Queues, workers and your enqueuing processes can exist anywhere in the BEAM cluster. 
  - [Global Queues](https://github.com/koudelka/honeydew/tree/master/examples/global)

__Plugability__
  - [Queues](https://github.com/koudelka/honeydew/blob/master/README/queues.md), [workers](https://github.com/koudelka/honeydew/blob/master/README/workers.md), [dispatch strategies](https://github.com/koudelka/honeydew/blob/master/README/dispatchers.md), [failure modes and success modes](https://github.com/koudelka/honeydew/blob/master/README/success_and_failure_modes.md) are all plugable with user modules.
  - No forced dependency on external queue services.

__Batteries Included__
  - [Mnesia Queue](https://github.com/koudelka/honeydew/tree/master/examples/mnesia.exs), for in-memory/persistence and simple distribution scenarios. (default)
  - [Ecto Queue](#ecto), to turn an Ecto schema into its own work queue, using your database.
  - [Fast In-Memory Queue](https://github.com/koudelka/honeydew/tree/master/examples/local), for fast processing of recreatable jobs without delay requirements.
  - Can optionally heal the cluster after a disconnect or downed node when using a [Global Queue](https://github.com/koudelka/honeydew/tree/master/examples/global).
  - [Delayed Jobs](https://github.com/koudelka/honeydew/tree/master/examples/delayed_job.exs)
  - [Exponential Retry](https://github.com/koudelka/honeydew/tree/master/lib/honeydew/failure_mode/exponential_retry.ex), even works with Ecto queues!


__Easy API__
  - Jobs are enqueued using `async/3` and you can receive replies with `yield/2`, somewhat like [Task](https://hexdocs.pm/elixir/Task.html).
  - [API Overview](https://github.com/koudelka/honeydew/blob/master/README/api.md)
  - [Hex Docs](https://hexdocs.pm/honeydew/Honeydew.html)


### <a name="ecto">Ecto Queue</a>

The Ecto Queue is designed to painlessly turn your Ecto schema into a queue, using your repo as the backing store.

- You don't need to explicitly enqueue jobs, that's handled for you (for example, sending a welcome email when a new User is inserted).
- Eliminates the possibility of your database and work queue becoming out of sync
- As the database is the queue, you don't need to run a separate queue node.
- You get all of the high-availability, consistency and distribution semantics of your chosen database.

Check out the included [example project](https://github.com/koudelka/honeydew/tree/master/examples/ecto_poll_queue), and its README.


## Getting Started

In your mix.exs file:

```elixir
defp deps do
  [{:honeydew, "~> 1.4.1"}]
end
```

### tl;dr
- Check out the [examples](https://github.com/koudelka/honeydew/tree/master/examples).
- Enqueue jobs with `Honeydew.async/3`, delay jobs by passing `delay_secs: <integer>`.
- Receive responses with `Honeydew.yield/2`.
- Emit job progress with `progress/1`
- Queue/Worker status with `Honeydew.status/1`
- Suspend and resume with `Honeydew.suspend/1` and `Honeydew.resume/1`
- List jobs with `Honeydew.filter/2`
- Move jobs with `Honeydew.move/2`
- Cancel jobs with `Honeydew.cancel/2`


### README
The rest of the README is broken out into slightly more digestible [sections](https://github.com/koudelka/honeydew/tree/master/README).

Also, check out the README files included with each of the [examples](https://github.com/koudelka/honeydew/tree/master/examples).

### CHANGELOG
It's worth keeping abreast with the [CHANGELOG](https://github.com/koudelka/honeydew/blob/master/CHANGELOG.md)
