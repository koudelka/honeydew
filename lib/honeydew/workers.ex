defmodule Honeydew.Workers do
  @moduledoc false

  use Supervisor
  alias Honeydew.WorkerRootSupervisor

  @type name :: Honeydew.queue_name()
  @type mod_or_mod_args :: Honeydew.mod_or_mod_args()
  @type worker_opts :: Honeydew.worker_opts()

  @spec workers() :: [name]
  def workers do
    __MODULE__
    |> Supervisor.which_children
    |> Enum.map(fn {queue, _, _, _} -> queue end)
    |> Enum.sort
  end

  @spec stop_workers(name) :: :ok | {:error, :not_running}
  def stop_workers(name) do
    with :ok <- Supervisor.terminate_child(__MODULE__, name) do
      Supervisor.delete_child(__MODULE__, name)
    end
  end

  @spec start_workers(name, mod_or_mod_args, worker_opts) :: :ok
  def start_workers(name, module_and_args, opts \\ []) do
    {module, args} =
      case module_and_args do
        module when is_atom(module) -> {module, []}
        {module, args} -> {module, args}
      end

    opts = %{
      ma: {module, args},
      num: opts[:num] || 10,
      init_retry_secs: opts[:init_retry_secs] || 5,
      shutdown: opts[:shutdown] || 10_000,
      nodes: opts[:nodes] || []
    }

    unless Code.ensure_loaded?(module) do
      raise ArgumentError, invalid_module_error(module)
    end

    Honeydew.create_groups(name)

    with {:ok, _} <- Supervisor.start_child(__MODULE__, {WorkerRootSupervisor, [name, opts]}) do
      :ok
    end
  end

  def start_link(args) do
    Supervisor.start_link(__MODULE__, args, name: __MODULE__)
  end

  @impl true
  def init(_args) do
    Supervisor.init([], strategy: :one_for_one)
  end

  def invalid_module_error(module) do
    "unable to find module #{inspect module} for workers"
  end
end
