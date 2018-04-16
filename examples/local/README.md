### Local Queue Example
![local queue](local.png)

There's an uncaring firehose of data pointed at us, we need to store it all in our database, Riak. The requester isn't expecting a response, and we can't drop a write due to overloaded workers.

Let's create a worker module. Honeydew will call our worker's `init/1` and keep the `state` from an `{:ok, state}` return.

Our workers are going to call functions from our module, the last argument will be the worker's state, `riak` in this case.

```elixir
defmodule Riak do
  @moduledoc """
    This is an example Worker to interface with Riak.
    You'll need to add the erlang riak driver to your mix.exs:
    `{:riakc, ">= 2.4.1}`
  """

  @behaviour Honeydew.Worker

  def init([ip, port]) do
    :riakc_pb_socket.start_link(ip, port) # returns {:ok, riak}
  end

  def up?(riak) do
    :riakc_pb_socket.ping(riak) == :pong
  end

  def put(bucket, key, obj, content_type, riak) do
    :ok = :riakc_pb_socket.put(riak, :riakc_obj.new(bucket, key, obj, content_type))
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

Then we'll start the both a queue and workers in our supervision tree.

```elixir
defmodule App do
  def start do
    children = [
      Honeydew.queue_spec(:riak),
      Honeydew.worker_spec(:riak, {Riak, ['127.0.0.1', 8087]}, num: 5, init_retry_secs: 10)
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
```

A task is simply a tuple with the name of a function and arguments, or a `fn`.

We'll add tasks to the queue using `async/3` and wait for responses with `yield/2`. To tell Honeydew that we expect a response from the job, we'll specify `reply: true`, like so:

```elixir
iex(1)> :up? |> Honeydew.async(:riak, reply: true) |> Honeydew.yield
{:ok, true}

iex(2)> {:put, ["bucket", "key", "value", "text/plain"]} |> Honeydew.async(:riak)
%Honeydew.Job{by: nil, failure_private: nil, from: nil, monitor: nil,
 private: -576460752303422557, queue: :riak, result: nil,
 task: {:put, ["bucket", "key", "value", "text/plain"]}}

iex(3)> {:get, ["bucket", "key"]} |> Honeydew.async(:riak, reply: true) |> Honeydew.yield
{:ok, "value"}

# our worker is holding a riak connection (a pid) as its state, let's ask that pid what its state is.
iex(4)> fn riak -> {riak, :sys.get_state(riak)} end |> Honeydew.async(:riak, reply: true) |> Honeydew.yield
{:ok,
 {#PID<0.256.0>,
  {:state, '127.0.0.1', 8087, false, false, #Port<0.8365>, false, :gen_tcp,
   :undefined, {[], []}, 1, [], :infinity, :undefined, :undefined, :undefined,
   :undefined, [], 100}}}
```

If you pass `reply: true`, and you never call `yield/2` to read the result, your process' mailbox may fill up after multiple calls. Don't do that.

(Ignoring the response of the `:put` above is just used as an exmaple, you probably want to check the return value of a database insert unless you have good reason to ignore it)

The `Honeydew.Job` struct above is used to track the status of a job, you can send it to `cancel/1`, if you want to try to kill the job.
