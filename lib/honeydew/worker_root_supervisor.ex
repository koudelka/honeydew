defmodule Honeydew.WorkerRootSupervisor do
  @moduledoc false

  use Supervisor, restart: :transient
  alias Honeydew.WorkerGroupSupervisor
  alias Honeydew.WorkerStarter
  alias Honeydew.NodeMonitorSupervisor

  @type name :: Honeydew.queue_name()

  @spec child_spec([name | any()]) :: Supervisor.child_spec()
  def child_spec([name | _] = opts) do
    opts
    |> super
    |> Map.put(:id, name)
  end

  def start_link([queue, opts]) do
    Supervisor.start_link(__MODULE__, [queue, opts], [])
  end

  # if the worker group supervisor shuts down due to too many groups restarting,
  # we also want the WorkerStarter to die  so that it may restart the necessary
  # worker groups when the worker group supervisor comes back up
  @impl true
  def init([queue, opts]) do
    [
      {WorkerGroupSupervisor, [queue, opts]},
      {WorkerStarter, queue}
    ]
    |> add_node_supervisor(queue, opts)
    |> Supervisor.init(strategy: :rest_for_one)
  end

  defp add_node_supervisor(children, {:global, _} = queue, %{nodes: nodes}) do
    children ++ [{NodeMonitorSupervisor, [queue, nodes]}]
  end
  defp add_node_supervisor(children, _, _), do: children
end
