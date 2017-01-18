alias Experimental.GenStage

defmodule Honeydew do
  alias Honeydew.Job
  alias Honeydew.Queue

  #
  # Parts of this module were lovingly stolen from
  # https://github.com/elixir-lang/elixir/blob/v1.3.2/lib/elixir/lib/task.ex#L320
  #

  def async(task, queue, opts \\ [])
  def async(task, queue, reply: true) do
    {:ok, job} =
      %Job{task: task, from: {self(), make_ref()}, queue: queue}
      |> enqueue

    job
  end

  def async(task, queue, _opts) do
    {:ok, job} =
      %Job{task: task, queue: queue}
      |> enqueue

    job
  end

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

  def suspend(queue) do
    queue
    |> get_all_members(:queues)
    |> Enum.each(&Queue.suspend/1)
  end

  def resume(queue) do
    queue
    |> get_all_members(:queues)
    |> Enum.each(&Queue.resume/1)
  end

  def status(queue) do
    queue_status =
      queue
      |> get_queue
      |> GenStage.call(:status)

    busy_workers =
      queue
      |> get_all_members(:monitors)
      |> Enum.map(fn monitor ->
           try do
             GenServer.call(monitor, :current_job)
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

    %{queue: queue_status, workers: workers}
  end

  def filter(queue, function) do
    {:ok, jobs} =
      queue
      |> get_queue
      |> GenStage.call({:filter, function})

    jobs
  end

  def cancel(%Job{queue: queue} = job) do
    queue
    |> get_queue
    |> GenStage.call({:cancel, job})
  end

  # FIXME: remove
  def state(queue) do
    queue
    |> get_all_members(:queues)
    |> Enum.map(&GenStage.call(&1, :"$honeydew.state"))
  end

  @doc false
  def enqueue(%Job{queue: queue} = job) do
    queue
    |> get_queue
    |> case do
         {:error, {:no_such_group, _queue}} -> raise RuntimeError, no_queues_running_error(job)
         queue -> GenStage.call(queue, {:enqueue, job})
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

  @doc """
  Creates a supervision spec for a queue.

  `name` is how you'll refer to the queue to add a task.

  You can provide any of the following `opts`:
  - `queue` is the module that queue will use, you may also provide init/1 args: {module, args}
  - `dispatcher` the job dispatching strategy, must implement the `GenStage.Dispatcher` behaviour
  - `failure_mode`: the way that failed jobs should be handled. You can pass either a module, or {module, args}, the module must implement the `Honeydew.FailureMode` behaviour. `args` defaults to `[]`.

  For example:
    `Honeydew.queue_spec("my_awesome_queue")`
    `Honeydew.queue_spec("my_awesome_queue", queue: {MyQueueModule, [ip: "localhost"]})`
  """
  def queue_spec(name, opts \\ []) do
    {module, args} =
      case opts[:queue] do
        nil -> {Honeydew.Queue.ErlangQueue, []}
        module when is_atom(module) -> {module, []}
        {module, args} -> {module, args}
      end

    dispatcher = opts[:dispatcher] || GenStage.DemandDispatcher
    # this is intentionally undocumented, i'm not yet sure there's a real use case for multiple queue processes
    num = opts[:num] || 1

    failure_mode =
      case opts[:failure_mode] do
        nil -> {Honeydew.FailureMode.Abandon, []}
        module when is_atom(module) -> {module, []}
        {module, args} -> {module, args}
      end

    Honeydew.create_groups(name)

    Supervisor.Spec.supervisor(Honeydew.QueueSupervisor, [name, module, args, num, dispatcher, failure_mode])
  end

  @doc """
  Creates a supervision spec for workers.

  `queue` is the name of the queue that the workers pull jobs from
  `module` is the module that the workers in your queue will use, you may also provide init/1 args: {module, args}

  You can provide any of the following `opts`:
  - `num`: the number of workers to start
  - `init_retry`: the amount of time, in milliseconds, to wait before respawning a worker who's `init/1` function failed
  - `shutdown`: if a worker is in the middle of a job, the amount of time, in milliseconds, to wait before brutally killing it.

  For example:
    `Honeydew.worker_spec("my_awesome_queue", MyJobModule)`
    `Honeydew.worker_spec("my_awesome_queue", {MyJobModule, [key: "secret key"]}, num: 3)`
  """
  def worker_spec(name, module_and_args, opts \\ []) do
    {module, args} =
      case module_and_args do
        module when is_atom(module) -> {module, []}
        {module, args} -> {module, args}
      end

    num = opts[:num] || 10
    init_retry = opts[:init_retry] || 5
    shutdown = opts[:shutdown] || 10_000

    Honeydew.create_groups(name)

    Supervisor.Spec.supervisor(Honeydew.WorkerSupervisor, [name, module, args, num, init_retry, shutdown])
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

end
