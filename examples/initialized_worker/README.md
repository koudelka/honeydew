### Initialized Worker Example

Oftentimes, you'll want to initialize your worker with some kind of state (a database connection, for example). You can do this by implementing the `init/1` callback. The arguments passed to it are those you provided to `Honeydew.start_workers/3`.

Let's create a worker module. Honeydew will call our worker's `init/1` and keep the `state` from an `{:ok, state}` return.

```elixir
defmodule Worker do

  def init([ip, port]) do
    {:ok, db} = Database.connect(ip, port)
    {:ok, db}
  end

  def run(id, db) do
    IO.puts "Sending email to user id #{id}!"

    id
    |> Database.find(db)
    |> send_email("Hello!")
  end

end
```

If your `init/1` function returns anything other than `{:ok, state}` or raises an error, Honeydew will retry your init function in ten seconds.

Then we'll ask Honeydew to start both the queue and workers in its supervision tree.

```elixir
defmodule App do
  def start do
    Honeydew.start_queue(:my_queue)
    Honeydew.start_workers(:my_queue, {Worker, ['127.0.0.1', 8087]})
  end
end
```

Add the task to your queue using `async/3`, Honeydew will append your state to the list of arguments.


```elixir
iex(1)> {:run, [123]} |> Honeydew.async(:my_queue)
Sending email to user id 123!
```

The `async/3` function returns a `Honeydew.Job` struct. You can call `cancel/1` with it, if you want to try to kill the job.
