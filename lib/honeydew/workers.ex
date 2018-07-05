defmodule Honeydew.Workers do
  use DynamicSupervisor
  alias Honeydew.WorkerRootSupervisor

  @type queue_name :: Honeydew.queue_name()
  @type mod_or_mod_args :: Honeydew.mod_or_mod_args()
  @type worker_spec_opt :: Honeydew.worker_spec_opt()

  def start_workers(name, module_and_args, opts \\ []) do
    {module, args} =
      case module_and_args do
        module when is_atom(module) -> {module, []}
        {module, args} -> {module, args}
      end

    opts = %{
      ma: {module, args},
      num: opts[:num] || 10,
      init_retry: opts[:init_retry] || 5,
      shutdown: opts[:shutdown] || 10_000,
      nodes: opts[:nodes] || []
    }

    unless Code.ensure_loaded?(module) do
      raise ArgumentError, invalid_module_error(module)
    end

    Honeydew.create_groups(name)

    {:ok, _} = DynamicSupervisor.start_child(__MODULE__, {WorkerRootSupervisor, [name, opts]})
    :ok
  end

  def start_link(args) do
    DynamicSupervisor.start_link(__MODULE__, args, name: __MODULE__)
  end

  @impl true
  def init(_args) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def invalid_module_error(module) do
    "unable to find module #{inspect module} for workers"
  end
end
