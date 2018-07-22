defmodule Honeydew.Dispatcher.LRUNode do
  alias Honeydew.Dispatcher.LRU

  # TODO: docs

  def init do
    # {node_queue, node -> lrus}
    {:ok, {:queue.new, Map.new}}
  end

  def available?({_node_queue, lrus}) do
    lrus
    |> Map.values
    |> Enum.any?(&LRU.available?/1)
  end

  def check_in(worker, {node_queue, lrus}) do
    node = worker_node(worker)

    {node_queue, lru} =
      lrus
      |> Map.get(node)
      |> case do
           nil ->
             # this node isn't currently known
             {:ok, lru} = LRU.init
             {:queue.in(node, node_queue), lru}
           lru ->
             # there's already at least one worker from this node present
             {node_queue, lru}
         end

    {node_queue, Map.put(lrus, node, LRU.check_in(worker, lru))}
  end

  def check_out(job, {node_queue, lrus} = state) do
    with {{:value, node}, node_queue} <- :queue.out(node_queue),
         %{^node => lru} <- lrus,
         {worker, lru} when not is_nil(worker) <- LRU.check_out(job, lru) do
      unless LRU.available?(lru) do
        {worker, {node_queue, Map.delete(lrus, node)}}
      else
        {worker, {:queue.in(node, node_queue), Map.put(lrus, node, lru)}}
      end
    else _ ->
      {nil, state}
    end
  end

  def remove(worker, {node_queue, lrus}) do
    node = worker_node(worker)

    with %{^node => lru} <- lrus,
         lru <- LRU.remove(worker, lru) do
      if LRU.available?(lru) do
        {node_queue, Map.put(lrus, node, lru)}
      else
        {:queue.filter(&(&1 != node), node_queue), Map.delete(lrus, node)}
      end
    else _ ->
        # this means that we've been asked to remove a worker we don't know about
        # this should never happen :o
        {node_queue, lrus}
    end
  end

  def known?(worker, {_node_queue, lrus}) do
    Enum.any?(lrus, fn {_node, lru} -> LRU.known?(worker, lru) end)
  end

  # for testing
  defp worker_node({_worker, node}), do: node
  defp worker_node(worker) do
    :erlang.node(worker)
  end
end
