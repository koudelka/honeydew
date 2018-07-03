defmodule Honeydew.NodeMonitorSupervisor do
  alias Honeydew.NodeMonitor

  def child_spec([queue, _nodes] = opts) do
    %{
      id: Honeydew.supervisor(queue, :node_monitor),
      start: {__MODULE__, :start_link, opts},
      supervisor: true
    }
  end

  def start_link(queue, nodes) do
    opts = [name: Honeydew.supervisor(queue, :node_monitor)]

    {:ok, supervisor} = DynamicSupervisor.start_link(opts)

    Enum.each(nodes, fn node ->
      DynamicSupervisor.start_child(supervisor, {NodeMonitor, [node]})
    end)

    {:ok, supervisor}
  end
end
