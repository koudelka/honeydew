defmodule Honeydew.DisorderSandbox do
  alias Honeydew.Job

  @behaviour Honeydew.Disorder.Behaviour

  @impl true
  def enqueue(_name, _id, _job) do
    :ok
  end

  @impl true
  def delete(_name, _id) do
    :ok
  end

  @impl true
  def get({_queue, :doesnt_exit}), do: nil
  def get({_queue, id}) do
    %Job{private: id}
  end

  @impl true
  def keys_for_node(_node, _bucket) do
    [Honeydew.Queue.Disorder.mk_id()]
  end

  @impl true
  def queue_name(name) do
    ["test_queue_name", name] |> Enum.join(".") |> String.to_atom
  end
end
