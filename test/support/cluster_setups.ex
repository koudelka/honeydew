defmodule Honeydew.Support.ClusterSetups do
  alias Honeydew.Support.Cluster

  def start_queue_node(queue) do
    fn ->
      :ok = Honeydew.start_queue(queue)
    end
    |> start_node(queue, :queue)
  end

  def start_worker_node(queue) do
    fn ->
      :ok = Honeydew.start_workers(queue, Stateless)
    end
    |> start_node(queue, :worker)
  end

  defp start_node(function, {:global, name} = queue, type) do
    {:ok, node} =
      [name, type]
      |> Enum.join("-")
      |> Cluster.spawn_node

    me = self()

    # seems to be necessary to get pg2 to sync with the slaves
    Honeydew.create_groups(queue)

    Node.spawn_link(node, fn ->
      function.()
      send me, :ready
      Process.sleep(:infinity) # sleep so as to not terminate, and cause linked supervisor to crash
    end)

    receive do
      :ready -> {:ok, %{node: node}}
    end
  end
end
