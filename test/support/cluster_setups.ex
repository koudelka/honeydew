defmodule Honeydew.Support.ClusterSetups do
  alias Honeydew.Support.Cluster
  alias Honeydew.Queue.ErlangQueue

  def start_queue_node(queue) do
    [queue, queue: ErlangQueue]
    |> Honeydew.Queues.child_spec
    |> start_node(queue, :queue)
  end

  def start_worker_node(queue) do
    queue
    |> Honeydew.worker_spec(Stateless)
    |> start_node(queue, :worker)
  end

  defp start_node(supervision_spec, {:global, name} = queue, type) do
    {:ok, node} =
      [name, type]
      |> Enum.join("-")
      |> Cluster.spawn_node

    me = self()

    # seems to be necessary to get pg2 to sync with the slaves
    Honeydew.create_groups(queue)

    Node.spawn_link(node, fn ->
      {:ok, sup} = Supervisor.start_link([supervision_spec], strategy: :one_for_one, restart: :transient)
      send me, {:sup, sup}
      Process.sleep(:infinity) # sleep so as to not terminate, and cause linked supervisor to crash
    end)

    receive do
      {:sup, sup} -> %{node: node, sup: sup}
    end
  end
end
