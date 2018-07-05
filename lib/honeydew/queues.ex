defmodule Honeydew.Queues do
  use DynamicSupervisor
  alias Honeydew.Queue

  @type name :: Honeydew.queue_name()
  @type queue_spec_opt :: Honeydew.queue_spec_opt()

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
    {:ok, _} = DynamicSupervisor.start_child(__MODULE__, {Queue, opts})
    :ok
  end

  def start_link(args) do
    DynamicSupervisor.start_link(__MODULE__, args, name: __MODULE__)
  end

  @impl true
  def init(_args) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

end
