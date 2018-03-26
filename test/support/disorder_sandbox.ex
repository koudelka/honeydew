defmodule Honeydew.DisorderSandbox do
  alias Honeydew.Job

  @behaviour Honeydew.Disorder.Behaviour

  # A KV store is mostly sufficient to model Disorder
  def start(queue) do
    Agent.start(fn -> %{} end, name: process_name(queue))
  end

  @impl true
  def enqueue(queue, id, job) do
    queue
    |> process_name
    |> Agent.update(&Map.put(&1, id, job))

    Honeydew.Disorder.enqueue_id(queue, id)

    :ok
  end

  @impl true
  def delete(queue, id) do
    queue
    |> process_name
    |> Agent.update(&Map.delete(&1, id))

    :ok
  end

  @impl true
  def get({queue, id}) do
    queue
    |> process_name
    |> Agent.get(&Map.get(&1, id))
    |> case do
         nil -> {:error, :not_found}
         value -> {:ok, value}
       end
  end

  @impl true
  def keys_for_node(_node, queue) do
    queue
    |> process_name
    |> Agent.get(&Map.keys/1)
  end

  defp process_name(queue) do
    :"disorder_mock_#{queue}"
  end
end
