defmodule Honeydew.NodeMonitorSupervisor do
  use DynamicSupervisor
  alias Honeydew.NodeMonitor

  def start_link([queue, nodes]) do
    opts = [name: Honeydew.supervisor(queue, :node_monitor)]

    {:ok, supervisor} = DynamicSupervisor.start_link(__MODULE__, [], opts)

    Enum.each(nodes, fn node ->
      DynamicSupervisor.start_child(supervisor, {NodeMonitor, node})
    end)

    {:ok, supervisor}
  end

  @impl true
  def init(_) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
