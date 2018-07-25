defmodule Honeydew.Queues do
  use Supervisor
  alias Honeydew.Queue

  @type name :: Honeydew.queue_name()
  @type queue_spec_opt :: Honeydew.queue_spec_opt()

  @spec queues() :: [name]
  def queues do
    __MODULE__
    |> Supervisor.which_children
    |> Enum.map(fn {queue, _, _, _} -> queue end)
    |> Enum.sort
  end

  @spec stop_queue(name) :: :ok | {:error, :not_running}
  def stop_queue(name) do
    with :ok <- Supervisor.terminate_child(__MODULE__, name) do
      Supervisor.delete_child(__MODULE__, name)
    end
  end

  @spec start_queue(name, [queue_spec_opt]) :: :ok
  def start_queue(name, opts) do
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

    Honeydew.create_groups(name)

    opts = [name, module, args, dispatcher, failure_mode, success_mode, suspended]
    {:ok, _} = Supervisor.start_child(__MODULE__, {Queue, opts})
    :ok
  end

  def start_link(args) do
    Supervisor.start_link(__MODULE__, args, name: __MODULE__)
  end

  @impl true
  def init(_args) do
    Supervisor.init([], strategy: :one_for_one)
  end

end
