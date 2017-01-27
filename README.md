Honeydew 💪🏻🍈
========

Honeydew (["Honey, do!"](http://en.wiktionary.org/wiki/honey_do_list)) is a pluggable job queue + worker pool for Elixir.

- Workers are permanent and hold immutable state (a network connection, for example).
- Workers are issued only one job at a time, a job is only ever removed from the queue when it succeeds.
- Queues can exist locally, on another node in the cluster, or on a remote queue server (rabbitmq, etc...).
- Jobs are enqueued using `async/3` and you can receive replies with `yield/2`, somewhat like [Task](http://elixir-lang.org/docs/stable/elixir/Task.html).
- If a worker crashes while processing a job, the job is recovered and a "failure mode" (abandon, requeue, etc) is executed.
- Queues, workers, dispatch strategies and failure modes are all plugable with user modules.

Honeydew attempts to provide "at least once" job execution, it's possible that circumstances could conspire to execute a job, and prevent Honeydew from reporting that success back to the queue. I encourage you to write your jobs idepotently.

Honeydew isn't intended as a simple resource pool, the user's code isn't executed in the requesting process. Though you may use it as such, there are likely other alternatives that would fit your situation better.


### tl;dr
- Check out the [examples](https://github.com/koudelka/honeydew/tree/master/examples).
- Enqueue and receive responses with `async/3` and `yield/2`.
- Suspend and resume with `Honeydew.suspend/1` and `Honeydew.resume/1`
- List jobs with `Honeydew.filter/2`
- Queue status with `Honeydew.status/1`
- Cancel jobs with `Honeydew.cancel/2`

### Queue Feature Support
|                        | filter | status | cancel | in-memory | disk-backed |
|------------------------|:------:|:------:|:------:|:---------:|:-----------:|
| ErlangQueue (`:queue`) | ✅*    | ✅     | ✅*    | ✅       | ❌         |
| Mnesia                 | ✅*    | ✅*    | ✅     | ✅ (ets) | ✅ (dets)   |
- * careful with this, it's slow, O(n)


## Getting Started

In your mix.exs file:

```elixir
defp deps do
  [{:honeydew, "~> 1.0.0-rc1"}]
end
```

You can run honeydew on a single node, or with components distributed over a cluster.

### Local Queue Example
![local queue](https://github.com/koudelka/honeydew/blob/master/doc/local.png)

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

### Distributed Queue Example
![distributed queue](https://github.com/koudelka/honeydew/blob/master/doc/distributed.png)

Say we've got some pretty heavy tasks that we want to distribute over a farm of background job processing nodes, they're too heavy to process on our client-facing nodes. In a distributed Erlang scenario, you have the option of distributing Honeydew's various components around different nodes in your cluster. Honeydew is basically a simple collection of queue processes and worker processes. Honeydew detects when nodes go up and down, and reconnects workers.

To start a global queue, pass a `{:global, name}` tuple when you start Honeydew's components

In this example, we'll use the Mnesa queue with stateless workers.

We'll start the queue on node `queue@dax` with:

```elixir
defmodule QueueApp do
  def start do
    nodes = [node()]

    children = [
      Honeydew.queue_spec({:global, :my_queue}, queue: {Honeydew.Queue.Mnesia, [nodes, [disc_copies: nodes], []]})
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end

iex(queue@dax)1> QueueApp.start
{:ok, #PID<0.209.0>}
```

And we'll run our workers on `background@dax` with:
```elixir
defmodule HeavyTask do
  def work_really_hard(secs) do
    :timer.sleep(1_000 * secs)
    IO.puts "I worked really hard for #{secs} secs!"
  end
end

defmodule WorkerApp do
  def start do
    children = [
      Honeydew.worker_spec({:global, :my_queue}, HeavyTask, num: 10)
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end

iex(background@dax)1> Node.ping :queue@dax
:pong

iex(background@dax)2> WorkerApp.start
{:ok, #PID<0.205.0>}
```

(note that in this case, our worker is stateless, so we left out `init/1`)

You can connect the nodes together at any point in the process, Honeydew will automatically detect where its components are running.

Then on any node in the cluster, we can enqueue a job:

```elixir
iex(clientfacing@dax)1> Node.ping :queue@dax
:pong

iex(clientfacing@dax)2> {:work_really_hard, [5]} |> Honeydew.async({:global, :my_queue})
%Honeydew.Job{by: nil, failure_private: nil, from: nil, monitor: nil,
 private: {false, -576460752303423485}, queue: {:global, :my_queue},
 result: nil, task: {:work_really_hard, [5]}}
````

The job will run on the worker node, five seconds later it'll print `I worked really hard for 5 secs!`


There's one important caveat that you should note, Honeydew doesn't yet support OTP failover/takeover, so please be careful in production. I'll send you three emoji of your choice if you submit a PR. :)

### Suspend and Resume
You can suspend a queue (halt the distribution of new jobs to workers), by calling `Honeydew.suspend(:my_queue)`, then resume with `Honeydew.resume(:my_queue)`.

### Cancelling Jobs
To cancel a job that hasn't yet run, use `Honeydew.cancel/2`. If the job was successfully cancelled before execution, `:ok` will be returned. If the job wasn't present in the queue, `nil`. If the job is currently being executed, `{:error, :in_progress}`.

### Queue Options
There are various options you can pass to `queue_spec/2` and `worker_spec/3`, see the [Honeydew](https://github.com/koudelka/honeydew/blob/master/lib/honeydew.ex) module.

### Failure Modes
When a worker crashes, a monitoring process runs the `handle_failure/4` function from the selected module on the queue's node. Honeydew ships with two failure modes, at present:

- `Abandon`: Simply forgets about the job.
- `Requeue`: Removes the job from the original queue, and places it on another.

See `Honeydew.queue_spec/2` to select a failure mode.

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
     |  ├─ The worker sends an acknowledgement message to the monitor. The monitor sends an
     |  |  acknowledgement to the queue to remove the job.
     |  └─ The worker informs the queue that it's ready for a new job. The queue checks the worker in with the
     |     dispatcher.
     └─ If the worker crashes, the monitor executes the selected "Failure Mode" and terminates.
```


### Queues
Queues are the most critical location of state in Honeydew, a job will not be removed from the queue unless it has either been successfully executed, or been dealt with by the configured failure mode.

Honeydew includes a few basic queue modules:
 - A simple FIFO queue implemented with the `:queue` and `Map` modules, this is the default.
 - An Mnesia queue, configurable in all the ways mnesia is, for example:
   * Run with replication (with queues running on multiple nodes) 
   * Persist jobs to disk (dets)
   * Follow various safety modes ("access contexts").

If you want to implement your own queue, check out the included queues as a guide. Try to keep in mind where exactly your queue state lives, is your queue process(es) where jobs live, or is it a completely stateless connector for some external broker? Or a hybrid? I'm excited to see what you come up with, please open a PR! <3

### Dispatchers
Honeydew provides the following dispatchers:

- `Honeydew.Dispatcher.LRUNode` - Least Recently Used Node (sends jobs to the least recently used worker on the least recently used node, the default for global queues)
- `Honeydew.Dispatcher.LRU` - Most Recently Used Worker (LIFO, the default for local queues)
- `Honeydew.Dispatcher.MRU` - Most Recently Used Worker (LIFO)

You can also use your own dispatching strategy by passing it to `Honeydew.queue_spec/2`. Check out the [built-in dispatchers](https://github.com/koudelka/honeydew/tree/master/lib/honeydew/dispatcher) for reference.

### Worker State
Worker state is immutable, the only way to change it is to cause the worker to crash and let the supervisor restart it.

Your worker module's `init/1` function must return `{:ok, state}`. If anything else is returned or the function raises an error, the worker will die and restart after a given time interval (by default, five seconds).

### TODO:
- failover/takeover for global queues
- statistics?
- `yield_many/2` support?
- benchmark mnesia queue's dual filter implementations, discard one?
- using a global queue, control which node executes a job on-the-fly with a dispatcher
- more tests

### Acknowledgements

Thanks to @marcelog, for his [failing worker restart strategy](http://inaka.net/blog/2012/11/29/every-day-erlang/).
