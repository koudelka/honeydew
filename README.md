Honeydew
========

Honeydew (["Honey, do!"](http://en.wiktionary.org/wiki/honey_do_list)) is a worker pool library for Elixir.

- Workers ("Honeys") are permanent and hold immutable state.
- Honeys pull jobs from the work queue ("Job List").
- Tasks are executed using `cast/1` and `call/2`, somewhat like a `GenServer`.
- If a Honey crashes while processing a job, the job is recovered and placed back on the queue.

## Usage
Simply create a module and `use Honeydew`, then start the pool with `YourModule.start_pool/2`.

You can request tasks be processed using `cast/1` or `call/2`, like so:

`Your.Module.cast({:insert_thing_in_db, ["key", "value"]})`
`Your.Module.call({:get_thing_from_db, ["key"]}) # -> "value"`

## Example
```elixir
# This is your worker
defmodule CatFeedingHoney do
  use Honeydew

  def init(pantry_location) do
    Pantry.init(pantry_location)
  end

  # the last argument is always the honey's state
  def make_snack(kind, kitty, pantry) do
    snack = Pantry.get(pantry, :snacks, kind)
    "#{snack} snack for #{kitty}!"
  end

  def go_shopping(pantry) do
    Pantry.put(pantry, :snacks, :tuna)
    IO.puts("went shopping")
  end
end


# This is your database
defmodule Pantry do
  def init(_location) do
    {:ok, :pantry_connection}
  end

  def get(_pantry_connection, _shelf, item) do
    item
  end

  def put(_pantry_connection, _shelf, item) do
    item
  end
end

CatFeedingHoney.start_pool("kitchen")

#
# Blocking call
#
CatFeedingHoney.call(:make_snack, [:tuna, :darwin]) # -> "tuna snack for darwin!"

#
# Non-blocking cast
#
CatFeedingHoney.cast(:go_shopping) # -> prints "went shopping"

#
# You can pass arbitrary functions to be executed, too.
#
CatFeedingHoney.call(fn(pantry) -> IO.inspect pantry end) # -> :pantry_connection

```

## Worker State
Worker State itself is immutable, the only way to change it is to cause the worker to crash and restart.

Your worker module's `init/1` function must return `{:ok, state}`. If anything else is returned or the function raises an error, the worker will die and restart after a given time interval (by default, five seconds).

## Configuration

### Worker Respawn Delay
You can configure the worker module's respawn delay time, in case `init/1` fails, like so:

`Your.Module.start_pool([:some_worker_args], init_retry_secs: 20)`

### Maximum Failures
Jobs are only allowed to fail a certain number of times before they are no longer retried (default, three times), this is also configurable via `start_pool/1`:

`Your.Module.start_pool([:some_worker_args], max_failures: 5)`

(at present, jobs that fail too much are abandoned, but in the future will be written to disk)

### Number of Workers

Honeydew will supervise the number of workers you specify (default, ten worker)

`Your.Module.start_pool[:some_worker_args], workers: 50)`


## Process Tree
After calling `Your.Module.start_pool/2`, a process tree like this will be created under the supervision of Honeydew:

```
Honeydew.Supervisor
└── Honeydew.Your.Module.HomeSupervisor
    ├── Honeydew.Your.Module.JobList
    └── Honeydew.Your.Module.HoneySupervisor
        ├── Honeydew.Honey
        ├── Honeydew.Honey
        ├── Honeydew.Honey
        └── Honeydew.Honey
```

## Disclaimer

This library is under active development, please don't use it in production yet, and please contribute if you find it useful! :)

## Acknowledgements

Thanks to @marcelog, for his [failing worker restart strategy](http://inaka.net/blog/2012/11/29/every-day-erlang/).
