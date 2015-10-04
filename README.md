Honeydew
========

Honeydew (["Honey, do!"](http://en.wiktionary.org/wiki/honey_do_list)) is a job queue + worker pool for Elixir.

- Workers are permanent and hold immutable state.
- Workers pull jobs from the work queue.
- Tasks are executed using `cast/2` and `call/2`, somewhat like a `GenServer`.
- If a worker crashes while processing a job, the job is recovered and placed back on the queue.

## Getting Started

In your mix.exs file:

```elixir
defp deps do
  [{:honeydew, " ~> 0.0.8"}]
end
```

## Usage
Create a worker module and `use Honeydew`, then start the pool in your supervision tree with `Honeydew.child_spec/4`.

Honeydew will call your worker's `init/1` and will keep the state from `{:ok, state}`.

You can add tasks to the queue using `cast/2` or `call/2`, like so:

`Database.cast(:poolname, {:put, ["key", "value"]})`

`Database.call(:poolname, :up?)`

## Example

```elixir
defmodule Riak do
  use Honeydew

  @moduledoc """
    This is an example Worker to interface with Riak.
    You'll need to add the erlang riak driver to your mix.exs:
      `{:riakc, github: "basho/riak-erlang-client"}`
  """

  def init({ip, port}) do
    :riakc_pb_socket.start_link(ip, port)
  end

  def up?(riak) do
    :riakc_pb_socket.ping(riak) == :pong
  end

  def put(bucket, key, obj, content_type, riak) do
    :riakc_pb_socket.put(riak, :riakc_obj.new(bucket, key, obj, content_type))
  end

  def get(bucket, key, riak) do
    case :riakc_pb_socket.get(riak, bucket, key) do
      {:ok, obj} -> :riakc_obj.get_value(obj)
      {:error, :notfound} -> nil
      error -> error
    end
  end
end

```

Add the pool to your application's supervision tree:

```elixir
def start(_type, _args) do
  import Supervisor.Spec, warn: false

  children = [
    Honeydew.child_spec(:riak_pool, Riak, {'127.0.0.1', 8087})
  ]

  Supervisor.start_link(children, strategy: :one_for_one))
end
```

```elixir
iex(1)> Riak.call(:riak_pool, :up?)
true
iex(2)> Riak.cast(:riak_pool, {:put, ["bucket", "key", "value", "text/plain"]})
:ok
iex(3)> Riak.call(:riak_pool, {:get, ["bucket", "key"]})                       
"value"
```

## Worker State
Worker state is immutable, the only way to change it is to cause the worker to crash and let the supervisor restart it.

Your worker module's `init/1` function must return `{:ok, state}`. If anything else is returned or the function raises an error, the worker will die and restart after a given time interval (by default, five seconds).

## Pool Options

`Honeydew.child_spec/4`'s last argument is a keyword list of pool options.

See the [Honeydew](https://github.com/koudelka/honeydew/blob/master/lib/honeydew.ex) module for the possible options.


## Process Tree

```
Honeydew.Supervisor
├── Honeydew.WorkQueue
└── Honeydew.WorkerSupervisor
    └── Honeydew.Worker (x 10, by default)
```

## TODO:

- Failure backends
  - :abandon
  - :requeue
    - delay interval
    - action after max_tries (abandon, keep in queue, marshal)
- Distribution
  - jobs in mnesia, to allow other nodes to run work queues?

## Acknowledgements

Thanks to @marcelog, for his [failing worker restart strategy](http://inaka.net/blog/2012/11/29/every-day-erlang/).
