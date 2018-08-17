### Simple Local Example

![local queue](local.png)

Here's a barebones example of a local, in-memory Honeydew queue.

Let's create a basic worker module:

```elixir
defmodule Worker do
  @behaviour Honeydew.Worker

  def hello(thing) do
    IO.puts "Hello #{thing}!"
  end
end
```

Then we'll ask Honeydew to start both the queue and workers in its supervision tree.

```elixir
defmodule App do
  def start do
    :ok = Honeydew.start_queue(:my_queue)
    :ok = Honeydew.start_workers(:my_queue, Worker)
  end
end
```

A task is simply a tuple with the name of a function and arguments, or a `fn`. In our case, `{:hello, ["World"]}`.

We'll add tasks to the queue using `async/3`, a worker will then pick up the job and execute it.


```elixir
iex(1)> {:hello, ["World"]} |> Honeydew.async(:my_queue)
Hello World!
```

The `async/3` function returns a `Honeydew.Job` struct. You can call `cancel/1` with it, if you want to try to kill the job.
