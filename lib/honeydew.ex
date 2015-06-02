defmodule Honeydew do
  @doc """
        Creates a supervision spec for a pool.

        `pool_name` is how you'll refer to the queue to add a task.
        `worker_module` is the module that the workers in your queue will run.
        `worker_opts` are arguments handed to your module's `init/1`

        You can provide any of the following `pool_opts`:
          - `workers`: the number of workers in the pool
          - `max_failures`: the maximum number of times a job is allowed to fail before it's abandoned
          - `init_retry_secs`: the amount of time, in seconds, to wait before respawning a worker who's `init/1` function failed
      """
  def child_spec(pool_name, worker_module, worker_opts, pool_opts \\ []) do
    Supervisor.Spec.supervisor(Honeydew.Supervisor, [pool_name, worker_module, worker_opts, pool_opts])
  end


  @doc false
  def work_queue_name(worker_module, pool_name) do
    Module.concat([Honeydew, worker_module, pool_name])
  end


  defmacro __using__(_env) do
    quote do
      @doc """
        Enqueue a job, and don't wait for the result, similar to GenServer's `cast/2`

        The task can be:
        - a function that takes the worker's state as an argument. `fn(state) -> IO.inspect(state) end`
        - the name of a function implemented in your worker module, with optional arguments:
            `cast(:your_function)`
            `cast({:your_function, [:an_arg, :another_arg]})`
      """
      def cast(pool_name, task) do
        __MODULE__
        |> Honeydew.work_queue_name(pool_name)
        |> GenServer.cast({:add_task, task})
      end

      @doc """
        Enqueue a job, and wait for the result, similar to GenServer's `call/3`

        Supports the same argument as `cast/1` above, and an additional `timeout` argument.
      """
      def call(pool_name, task, timeout \\ 5000) do
        __MODULE__
        |> Honeydew.work_queue_name(pool_name)
        |> GenServer.call({:add_task, task}, timeout)
      end

      @doc """
        Gets the current status of the worker's queue (work queue, backlog, waiting/working workers)
      """
      def status(pool_name) do
        __MODULE__
        |> Honeydew.work_queue_name(pool_name)
        |> GenServer.call(:status)
      end
    end
  end

end
