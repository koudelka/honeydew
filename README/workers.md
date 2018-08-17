# Workers

Workers can be completely stateless, or initialized with state by implementing the `init/1` callback.

Worker state is immutable, the only way to change it is to cause the worker to crash and let Honeydew restart it.

Your worker module's `init/1` function must return `{:ok, state}`. If anything else is returned or your callback raises an error, the worker will execute your `failed_init/0` callback, if you've implemented it. If not, the worker will attempt to re-initialize in five seconds.

Check out the [initialized worker example](https://github.com/koudelka/honeydew/examples/initialized_worker).

If you'd like to re-initialize the worker from within your `failed_init/0` callback, you can do it like so:

```elixir
defmodule FailedInitWorker do
  def init(_) do
    raise "init failed"
  end

  def failed_init do
    Honeydew.reinitialize_worker()
  end
end
```
