Honeydew 💪🏻🍈
========
[![Build Status](https://travis-ci.org/koudelka/honeydew.svg?branch=master)](https://travis-ci.org/koudelka/honeydew)
[![Hex pm](https://img.shields.io/hexpm/v/honeydew.svg?style=flat)](https://hex.pm/packages/honeydew)

Honeydew (["Honey, do!"](http://en.wiktionary.org/wiki/honey_do_list)) is a pluggable job queue and worker pool for Elixir.

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

- Workers are permanent and hold immutable state (a database connection, for example).
- Workers are issued only one job at a time, a job is only ever removed from the queue when it succeeds or is instructed to abandon it.
- Queues can exist locally, on another node in the cluster, in your Ecto database, or on a remote queue server (rabbitmq, etc...).
- If a worker crashes while processing a job, the job is recovered and a "failure mode" (abandon, move, retry, etc) is executed.
- Jobs are enqueued using `async/3` and you can receive replies with `yield/2`, somewhat like [Task](https://hexdocs.pm/elixir/Task.html).
- Queues, workers, dispatch strategies and failure/success modes are all plugable with user modules.
- Can optionally heal your cluster after a disconnect or downed node.

Honeydew attempts to provide "at least once" job execution, it's possible that circumstances could conspire to execute a job, and prevent Honeydew from reporting that success back to the queue. I encourage you to write your jobs idempotently.

Honeydew isn't intended as a simple resource pool, the user's code isn't executed in the requesting process. Though you may use it as such, there are likely other alternatives that would fit your situation better, perhaps try [sbroker](https://github.com/fishcakez/sbroker).


### tl;dr
- Check out the [examples](https://github.com/koudelka/honeydew/tree/master/examples).
- Enqueue jobs with `Honeydew.async/3`.
- Receive responses with `Honeydew.yield/2`.
- Emit job progress with `progress/1`
- Queue/Worker status with `Honeydew.status/1`
- Suspend and resume with `Honeydew.suspend/1` and `Honeydew.resume/1`
- List jobs with `Honeydew.filter/2`
- Move jobs with `Honeydew.move/2`
- Cancel jobs with `Honeydew.cancel/2`

### Ecto Poll Queue

The Ecto Poll Queue is designed to painlessly turn an already-existing Ecto schema into a queue, using your repo as the backing store. This eliminates the possiblity of your database and work queue becoming out of sync, as well as eliminating the need to run a separate queue node.

Check out the included [example project](https://github.com/koudelka/honeydew/tree/master/examples/ecto_poll_queue), and its README.

## Getting Started

In your mix.exs file:

```elixir
defp deps do
  [{:honeydew, "~> 1.2.5"}]
end
```

### README
The rest of the README is broken out into slightly more digestable [sections](https://github.com/koudelka/honeydew/tree/master/README).

Also check out the README files included with the [examples](https://github.com/koudelka/honeydew/tree/master/examples).

## TODO:
- statistics?
- `yield_many/2` support?
- benchmark mnesia queue's dual filter implementations, discard one?
