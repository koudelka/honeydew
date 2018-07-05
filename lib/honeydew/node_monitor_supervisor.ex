defmodule Honeydew.NodeMonitorSupervisor do
  use DynamicSupervisor
  alias Honeydew.NodeMonitor

  def start_link([queue, nodes]) do
    {:ok, supervisor} = DynamicSupervisor.start_link(__MODULE__, [], [])

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
