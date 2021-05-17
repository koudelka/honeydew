defmodule Honeydew.Support.ClusterSetups do
  alias Honeydew.Support.Cluster
  alias Honeydew.Processes

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

    # seems to be necessary to get :pg to sync with the slaves
    Processes.start_process_group_scope(queue)

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
