defmodule Honeydew.NodeMonitorSupervisor do
  alias Honeydew.NodeMonitor

  def child_spec([queue, _nodes] = opts) do
    %{
      id: Honeydew.supervisor(queue, :node_monitor),
      start: {__MODULE__, :start_link, opts}
    }
  end

  def start_link(queue, nodes) do
    opts = [
      name: Honeydew.supervisor(queue, :node_monitor),
      strategy: :one_for_one
    ]

    {:ok, supervisor} = DynamicSupervisor.start_link(opts)

    Enum.each(nodes, fn node ->
      DynamicSupervisor.start_child(supervisor, [node])
    end)

    {:ok, supervisor}
  end
end
