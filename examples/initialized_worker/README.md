### Initialized Worker Example

Oftentimes, you'll want to initialize your worker with some kind of state (a database connection, for example). You can do this by implementing the `init/1` callback. The arguments passed to it are those you provided to `Honeydew.start_workers/3`.

Let's create a worker module. Honeydew will call our worker's `init/1` and keep the `state` from an `{:ok, state}` return.

```elixir
defmodule Worker do

  def init([ip, port]) do
    {:ok, db} = Database.connect(ip, port)
    {:ok, db}
  end

  def send_email(id, db) do
    %{name: name, email: email} = Database.find(id, db)

    IO.puts "sending email to #{email}"
    IO.inspect "hello #{name}, want to enlarge ur keyboard by 500%???"
  end

end
```

If your `init/1` function returns anything other than `{:ok, state}` or raises an error, Honeydew will retry your init function in five seconds.


We'll ask Honeydew to start both the queue and workers in its supervision tree.

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
Sending email to koudelka+honeydew@ryoukai.org!
"hello koudelka, want to enlarge ur keyboard by 500%???"
```
