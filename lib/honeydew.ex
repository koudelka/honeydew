defmodule Honeydew do
  @moduledoc """
  A pluggable job queue + worker pool for Elixir.
  """

  alias Honeydew.Job
  require Logger

  @type mod_or_mod_args :: module | {module, args :: term}
  @type queue_name :: String.t | atom | {:global, String.t | atom}
  @type supervisor_opts :: Keyword.t
  @type async_opt :: [{:reply, true}]
  @type task :: {atom, [arg :: term]}

  @typedoc """
  Result of a `Honeydew.Job`
  """
  @type result :: term

  #
  # Parts of this module were lovingly stolen from
  # https://github.com/elixir-lang/elixir/blob/v1.3.2/lib/elixir/lib/task.ex#L320
  #

  @doc """
  Runs a task asynchronously.

  Raises a `RuntimeError` if `queue` process is not available.

  ## Examples

  To run a task asynchronously.

      Honeydew.async({:ping, ["127.0.0.1"]}, :my_queue)

  To run a task asynchronously and wait for result.

      # Without pipes
      job = Honeydew.async({:ping, ["127.0.0.1"]}, :my_queue, reply: true)
      Honeydew.yield(job)

      # With pipes
      result =
        {:ping, ["127.0.0.1"]}
        |> Honeydew.async(:my_queue, reply: true)
        |> Honeydew.yield()
  """
  @spec async(task, queue_name, [async_opt]) :: Job.t | no_return
  def async(task, queue, opts \\ [])
  def async(task, queue, reply: true) do
    {:ok, job} =
      task
      |> Job.new(queue)
      |> struct(from: {self(), make_ref()})
      |> enqueue

    job
  end

  def async(task, queue, _opts) do
    {:ok, job} =
      task
      |> Job.new(queue)
      |> enqueue

    job
  end

  @doc """
  Wait for a job to complete and return result.

  Returns the result of a job, or `nil` on timeout. This function must be
  called from the same process that called `async/3`.

  ## Example

  Calling `yield/2` with different timeouts.

      iex> job = Honeydew.async({:ping, ["127.0.0.1"], :my_queue, reply: true)
      iex> Honeydew.yield(job, 2000)
      nil
      # Result comes in at 3 seconds
      iex> Honeydew.yield(job, 5000)
      :pong
      iex> Honeydew.yield(job, 10_000)
      nil # <- because the message has already arrived and been handled

  The only time `yield/2` would ever return the result more than once is if
  the job executes more than once (as Honeydew aims for at-least-once execution).
  """
  @spec yield(Job.t, timeout) :: result | nil
  def yield(job, timeout \\ 5000)
  def yield(%Job{from: nil} = job, _), do: raise ArgumentError, reply_not_requested_error(job)
  def yield(%Job{from: {owner, _}} = job, _) when owner != self(), do: raise ArgumentError, invalid_owner_error(job)

  def yield(%Job{from: {_, ref}}, timeout) do
    receive do
      %Job{from: {_, ^ref}, result: result} ->
        result # may be {:ok, term} or {:exit, term}
    after
      timeout ->
        nil
    end
  end

  @doc """
  Suspends job processing for a queue.
  """
  @spec suspend(queue_name) :: :ok
  def suspend(queue) do
    queue
    |> get_all_members(:queues)
    |> Enum.each(&GenServer.cast(&1, :suspend))
  end

  @doc """
  Resumes job processing for a queue.
  """
  @spec resume(queue_name) :: :ok
  def resume(queue) do
    queue
    |> get_all_members(:queues)
    |> Enum.each(&GenServer.cast(&1, :resume))
  end

  def status(queue) do
    queue_status =
      queue
      |> get_queue
      |> GenServer.call(:status)

    busy_workers =
      queue_status
      |> Map.get(:monitors)
      |> Enum.map(fn monitor ->
           try do
             GenServer.call(monitor, :status)
           catch
             # the monitor may have shut down
             :exit, _ -> nil
           end
         end)
      |> Enum.reject(&(!&1))
      |> Enum.into(%{})

    workers =
      queue
      |> get_all_members(:workers)
      |> Enum.map(&{&1, nil})
      |> Enum.into(%{})
      |> Map.merge(busy_workers)

    %{queue: Map.delete(queue_status, :monitors), workers: workers}
  end

  @doc """
  Filters the jobs currently on the queue.

  Please Note -- This function returns a `List`, not a `Stream`, so calling it
  can be memory intensive when invoked on a large queue.

  ## Examples

  Filter jobs with a specific task.

      Honeydew.filter(:my_queue, &match?(%Honeydew.Job{task: {:ping, _}}, &1))

  Return all jobs.

      Honeydew.filter(:my_queue, fn _ -> true end)
  """
  @spec filter(queue_name, (Job.t -> boolean)) :: [Job.t]
  def filter(queue, function) do
    {:ok, jobs} =
      queue
      |> get_queue
      |> GenServer.call({:filter, function})

    jobs
  end

  @doc """
  Cancels a job.

  The return value depends on the status of the job.

  * `:ok` - Job had not been started and was able to be cancelled.
  * `{:error, :in_progress}` - Job was in progress and unable to be cancelled.
  * `nil` - Job was not found on the queue (or already processed) and was unable
    to be cancelled.
  """
  @spec cancel(Job.t) :: :ok | {:error, :in_progress} | nil
  def cancel(%Job{queue: queue} = job) do
    queue
    |> get_queue
    |> GenServer.call({:cancel, job})
  end

  # FIXME: remove
  def state(queue) do
    queue
    |> get_all_members(:queues)
    |> Enum.map(&GenServer.call(&1, :"$honeydew.state"))
  end

  @doc false
  def enqueue(%Job{queue: queue} = job) do
    queue
    |> get_queue
    |> case do
         {:error, {:no_such_group, _queue}} -> raise RuntimeError, no_queues_running_error(job)
         queue -> GenServer.call(queue, {:enqueue, job})
       end
  end

  @doc false
  def invalid_owner_error(job) do
    "job #{inspect job} must be queried from the owner but was queried from #{inspect self()}"
  end

  @doc false
  def reply_not_requested_error(job) do
    "job #{inspect job} didn't request a reply when enqueued, set `:reply` to `true`, see `async/3`"
  end

  @doc false
  def no_queues_running_error(%Job{queue: {:global, _} = queue} = job) do
    "can't enqueue job #{inspect job} because there aren't any queue processes running for the distributed queue `#{inspect queue}, are you connected to the cluster?`"
  end

  @doc false
  def no_queues_running_error(%Job{queue: queue} = job) do
    "can't enqueue job #{inspect job} because there aren't any queue processes running for `#{inspect queue}`"
  end

  @type queue_spec_opt ::
    {:queue, mod_or_mod_args} |
    {:dispatcher, mod_or_mod_args} |
    {:failure_mode, mod_or_mod_args | nil} |
    {:success_mode, mod_or_mod_args | nil} |
    {:supervisor_opts, supervisor_opts}

  @doc """
  Creates a supervision spec for a queue.

  `name` is how you'll refer to the queue to add a task.

  You can provide any of the following `opts`:

  - `queue`: is the module that queue will use. Defaults to
    `Honeydew.Queue.ErlangQueue`. You may also provide args to the queue's
    `c:Honeydew.Queue.init/2` callback using the following format:
    `{module, args}`.
  - `dispatcher`: the job dispatching strategy, `{module, init_args}`.

  - `failure_mode`: the way that failed jobs should be handled. You can pass
    either a module, or `{module, args}`. The module must implement the
    `Honeydew.FailureMode` behaviour. Defaults to
    `{Honeydew.FailureMode.Abandon, []}`.

  - `success_mode`: a callback that runs when a job successfully completes. You
     can pass either a module, or `{module, args}`. The module must implement
     the `Honeydew.SuccessMode` behaviour. Defaults to `nil`.

  - `supervisor_opts`: options accepted by `Supervisor.Spec.supervisor/3`.

  For example:

  - `Honeydew.queue_spec("my_awesome_queue")`

  - `Honeydew.queue_spec("my_awesome_queue", queue: {MyQueueModule, [ip: "localhost"]}, dispatcher: {Honeydew.Dispatcher.MRU, []})`
  """
  @spec queue_spec(queue_name, [queue_spec_opt]) :: Supervisor.Spec.spec
  def queue_spec(name, opts \\ []) do
    {module, args} =
      case opts[:queue] do
        nil -> {Honeydew.Queue.ErlangQueue, []}
        module when is_atom(module) -> {module, []}
        {module, args} -> {module, args}
      end

    dispatcher =
      opts[:dispatcher] ||
      case name do
        {:global, _} -> {Honeydew.Dispatcher.LRUNode, []}
        _ -> {Honeydew.Dispatcher.LRU, []}
      end

    # this is intentionally undocumented, i'm not yet sure there's a real use case for multiple queue processes
    num = opts[:num] || 1

    failure_mode =
      case opts[:failure_mode] do
        nil -> {Honeydew.FailureMode.Abandon, []}
        {module, args} -> {module, args}
        module when is_atom(module) -> {module, []}
      end

    {failure_module, failure_args} = failure_mode
    :ok = failure_module.validate_args!(failure_args) # will raise on failure


    success_mode =
      case opts[:success_mode] do
        nil -> nil
        {module, args} -> {module, args}
        module when is_atom(module) -> {module, []}
      end

    with {success_module, success_args} <- success_mode do
      :ok = success_module.validate_args!(success_args) # will raise on failure
    end

    supervisor_opts =
      opts
      |> Keyword.get(:supervisor_opts, [])
      |> Keyword.put_new(:id, {:queue, name})

    Honeydew.create_groups(name)

    Supervisor.Spec.supervisor(
      Honeydew.QueueSupervisor,
      [name, module, args, num, dispatcher, failure_mode, success_mode],
      supervisor_opts)
  end

  @type worker_spec_opt ::
    {:num, non_neg_integer} |
    {:init_retry, non_neg_integer} |
    {:supervisor_opts, supervisor_opts} |
    {:nodes, [node]}

  @doc """
  Creates a supervision spec for workers.

  `queue` is the name of the queue that the workers pull jobs from.

  `module` is the module that the workers in your queue will use. You may also
  provide `c:Honeydew.Worker.init/1` args with `{module, args}`.

  You can provide any of the following `opts`:

  - `num`: the number of workers to start. Defaults to `10`.

  - `init_retry`: the amount of time, in seconds, to wait before respawning
     a worker whose `c:Honeydew.Worker.init/1` function failed. Defaults to `5`.

  - `shutdown`: if a worker is in the middle of a job, the amount of time, in
     milliseconds, to wait before brutally killing it. Defaults to `10_000`.

  - `supervisor_opts` options accepted by `Supervisor.Spec.supervisor/3`.

  - `nodes`: for :global queues, you can provide a list of nodes to stay
     connected to (your queue node and enqueuing nodes). Defaults to `[]`.

  For example:

  - `Honeydew.worker_spec("my_awesome_queue", MyJobModule)`

  - `Honeydew.worker_spec("my_awesome_queue", {MyJobModule, [key: "secret key"]}, num: 3)`

  - `Honeydew.worker_spec({:global, "my_awesome_queue"}, MyJobModule, nodes: [:clientfacing@dax, :queue@dax])`
  """
  @spec worker_spec(queue_name, mod_or_mod_args, [worker_spec_opt])
    :: Supervisor.Spec.spec
  def worker_spec(name, module_and_args, opts \\ []) do
    {module, args} =
      case module_and_args do
        module when is_atom(module) -> {module, []}
        {module, args} -> {module, args}
      end

    num = opts[:num] || 10
    init_retry = opts[:init_retry] || 5
    shutdown = opts[:shutdown] || 10_000
    nodes = opts[:nodes] || []

    supervisor_opts =
      opts
      |> Keyword.get(:supervisor_opts, [])
      |> Keyword.put_new(:id, {:worker, name})

    Honeydew.create_groups(name)

    Supervisor.Spec.supervisor(
      Honeydew.WorkerGroupSupervisor,
      [name, module, args, num, init_retry, shutdown, nodes],
      supervisor_opts)
  end

  @groups [:workers,
           :monitors,
           :queues]

  Enum.each(@groups, fn group ->
    @doc false
    def group(queue, unquote(group)) do
      name(queue, unquote(group))
    end
  end)

  @supervisors [:worker,
                :worker_group,
                :node_monitor,
                :queue]

  Enum.each(@supervisors, fn supervisor ->
    @doc false
    def supervisor(queue, unquote(supervisor)) do
      name(queue, "#{unquote(supervisor)}_supervisor")
    end
  end)


  @doc false
  def create_groups(queue) do
    Enum.each(@groups, fn name ->
      queue |> group(name) |> :pg2.create
    end)
  end

  @doc false
  def delete_groups(queue) do
    Enum.each(@groups, fn name ->
      queue |> group(name) |> :pg2.delete
    end)
  end

  @doc false
  def get_all_members({:global, _} = queue, name) do
    queue |> group(name) |> :pg2.get_members
  end

  @doc false
  def get_all_members(queue, name) do
    get_all_local_members(queue, name)
  end

  # we need to know local members to shut down local components
  @doc false
  def get_all_local_members(queue, name) do
    queue |> group(name) |> :pg2.get_local_members
  end


  @doc false
  def get_queue({:global, _name} = queue) do
    queue |> group(:queues) |> :pg2.get_closest_pid
  end

  @doc false
  def get_queue(queue) do
    queue
    |> group(:queues)
    |> :pg2.get_local_members
    |> case do
         [] -> nil
         members when is_list(members) -> Enum.random(members)
         error -> error
       end
  end


  defp name({:global, queue}, component) do
    name([:global, queue], component)
  end

  defp name(queue, component) do
    ["honeydew", component, queue] |> List.flatten |> Enum.join(".") |> String.to_atom
  end

  @doc false
  defmacro debug(ast) do
    quote do
      fn ->
        Logger.debug unquote(ast)
      end
    end
  end

end
