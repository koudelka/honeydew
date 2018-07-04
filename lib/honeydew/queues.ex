defmodule Honeydew.Queues do

  @type queue_name :: Honeydew.queue_name()
  @type mod_or_mod_args :: Honeydew.mod_or_mod_args()
  @type worker_spec_opt :: Honeydew.worker_spec_opt()

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

  - `supervisor_opts`: options accepted by `Supervisor.child_spec()`.

  - `suspended`: Start queue in suspended state. Defaults to `false`.

  For example:

  - `{Honeydew.Queues, ["my_awesome_queue"])`

  - `{Honeydew.Queues, ["my_awesome_queue", queue: {MyQueueModule, [ip: "localhost"]},
                                            dispatcher: {Honeydew.Dispatcher.MRU, []}])`
  """
  # @spec child_spec([queue_name, [queue_spec_opt]]) :: Supervisor.child_spec()
  @spec child_spec([...]) :: Supervisor.child_spec()
  def child_spec([name]), do: child_spec([name, []])

  def child_spec([name | opts]) do
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

    suspended = Keyword.get(opts, :suspended, false)

    supervisor_opts =
      opts
      |> Keyword.get(:supervisor_opts, [])
      |> Enum.into(%{})

    opts = [num, name, module, args, dispatcher, failure_mode, success_mode, suspended]

    %{id: {:queue, name},
      start: {__MODULE__, :start_link, [opts]},
      type: :supervisor}
    |> Map.merge(supervisor_opts)
  end

  def start_link([num | [name | _] = queue_opts]) do
    Honeydew.create_groups(name)

    opts = [strategy: :one_for_one,
            name: Honeydew.supervisor(name, :queue),
            # what would be sane settings here?
            # if a queue dies because it's trying to connect to a remote host,
            # should we delay the restart like with workers?
            max_restarts: num,
            max_seconds: 5]

    {:ok, supervisor} = DynamicSupervisor.start_link(opts)

    # start up workers
    Enum.each(1..num, fn _ ->
      {:ok, _} = DynamicSupervisor.start_child(supervisor, {Honeydew.Queue, queue_opts})
    end)

    {:ok, supervisor}
  end

end
