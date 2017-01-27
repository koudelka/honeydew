defmodule Honeydew.Dispatcher.LRUNode do
  alias Honeydew.Dispatcher.LRU

  # TODO: docs

  def init do
    # {node_queue, workers}
    {:ok, {:queue.new, Map.new}}
  end

  def available?({_node_queue, workers}) do
    workers
    |> Map.values
    |> Enum.any?(&LRU.available?/1)
  end

  def check_in(worker, {node_queue, workers}) do
    node = worker_node(worker)

    {node_queue, node_workers} =
      workers
      |> Map.get(node)
      |> case do
           nil ->
             # this node isn't currently known
             {:ok, node_workers} = LRU.init
             {:queue.in(node, node_queue), node_workers}
           node_workers ->
             # there's already at least one worker from this node present
             {node_queue, node_workers}
         end

    {node_queue, Map.put(workers, node, LRU.check_in(worker, node_workers))}
  end

  def check_out(job, {node_queue, workers} = state) do
    with {{:value, node}, node_queue} <- :queue.out(node_queue),
         %{^node => node_workers} <- workers,
         {worker, node_workers} when not is_nil(worker) <- LRU.check_out(job, node_workers) do
      if :queue.is_empty(node_workers) do
        {worker, {node_queue, Map.delete(workers, node)}}
      else
        {worker, {:queue.in(node, node_queue), Map.put(workers, node, node_workers)}}
      end
    else _ ->
      {nil, state}
    end
  end

  def remove(worker, {node_queue, workers}) do
    node = worker_node(worker)

    with %{^node => node_workers} <- workers,
         node_workers <- LRU.remove(worker, node_workers) do
      if LRU.available?(node_workers) do
        {node_queue, Map.put(workers, node, node_workers)}
      else
        {:queue.filter(&(&1 != node), node_queue), Map.delete(workers, node)}
      end
    else _ ->
        # this means that we've been asked to remove a worker we don't know about
        # this should never happen :o
        {node_queue, workers}
    end
  end

  # for testing
  defp worker_node({_worker, node}), do: node
  defp worker_node(worker) do
    :erlang.node(worker)
  end

end
