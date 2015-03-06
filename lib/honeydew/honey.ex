defmodule Honeydew.Honey do
  use GenServer
  require Logger
  alias Honeydew.HoneySupervisor

  def start_link(honey_module, honey_init_args \\ [], retry_secs \\ 0) do
    GenServer.start_link(__MODULE__, [honey_module, honey_init_args, retry_secs])
  end

  def start(honey_module, honey_init_args \\ [], retry_secs \\ 0) do
    GenServer.start(__MODULE__, [honey_module, honey_init_args, retry_secs])
  end

  def init([honey_module, honey_init_args, retry_secs]) do
    Process.flag(:trap_exit, true)
    init_result = \
      try do
        apply(honey_module, :init, [honey_init_args])
      rescue e ->
        {:error, e}
      end

    # consumes the possible DOWN message thrown by the honey module's init/0
    receive do
    after
      50 -> :ok
    end
    Process.flag(:trap_exit, false)

    case init_result do
      {:ok, state} ->
        job_list = Honeydew.job_list(honey_module)
        GenServer.call(job_list, :monitor_me)
        GenServer.cast(self, :ask_for_job)
        Logger.info("#{honey_module}.init/1 succeeded.")
        {:ok, {job_list, honey_module, state}}
      error ->
        :timer.apply_after(retry_secs * 1000, HoneySupervisor, :start_child, [honey_module, honey_init_args, retry_secs])
        Logger.warn("#{honey_module}.init/1 must return {:ok, state}, got: #{inspect(error)}, retrying in #{retry_secs}s")
        :ignore
    end
  end


  def handle_cast(:ask_for_job, {job_list, honey_module, honey_state} = state) do
    job = GenServer.call(job_list, :job_please, :infinity)
    result = \
      case job.task do
        f when is_function(f) -> f.(honey_state)
        f when is_atom(f)     -> apply(honey_module, f, [honey_state])
        {f, a}                -> apply(honey_module, f, a ++ [honey_state])
      end

    if job.from do
      GenServer.reply(job.from, result)
    end

    GenServer.cast(self, :ask_for_job)
    {:noreply, state}
  end


  defmacro __using__(_env) do
    quote do
      @job_list Honeydew.job_list(__MODULE__)

      @doc """
        Starts the Honey's worker pool, `honey_init_args` will be passed to the Honey's `init/1` function.

        You can provide any of the following pool options:
          - `workers`: the number of workers in the pool
          - `max_failrues`: the maximum number of times a job is allowed to fail before it's abandoned
          - `init_retry_secs`: the amount of time, in seconds, to wait before respawning a worker who's `init/1` function failed
      """
      def start_pool(honey_init_args, opts \\ []) do
        Honeydew.start_pool(__MODULE__, honey_init_args, opts)
      end

      @doc """
        Enqueue a job, and don't wait for the result, similar to GenServer's `cast/2`

        The task can be:
        - a function that takes the honey's state as an argument. `fn(state) -> IO.inspect(state) end`
        - the name of a function implemented in your honey module, with optional arguments:
            `cast(:your_function)`
            `cast({:your_function, [:an_arg, :another_arg]})`
      """
      def cast(task) do
        GenServer.cast(@job_list, {:add_task, task})
      end

      @doc """
        Enqueue a job, and wait for the result, similar to GenServer's `call/3`

        Supports the same argument as `cast/1` above, and an additional `timeout` argument.
      """
      def call(task, timeout \\ 5000) do
        GenServer.call(@job_list, {:add_task, task}, timeout)
      end

      @doc """
        Gets the current status of the honey's home (job list, backlog, waiting/working honeys)
      """
      def status do
        job_list = Honeydew.job_list(__MODULE__)
        GenServer.call(job_list, :status)
      end
    end
  end

end
