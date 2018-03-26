defmodule Honeydew.Disorder do
  alias Honeydew.Job

  defmodule Behaviour do
    @type id :: {node, node_uniq :: integer, sort_key :: integer}

    @callback enqueue(name :: atom | String.t, id, Job.t) :: :ok | {:error, reason :: term}
    @callback get({name :: atom | String.t, id}) :: {:ok, Job.t} | {:error, reason :: term}
    @callback delete(name :: atom | String.t, id) :: :ok | {:error, reason :: term}
    @callback keys_for_node(node, name :: atom | String.t) :: [id]
  end

  if Code.ensure_loaded?(Disorder) do
    @behaviour Behaviour
    @behaviour Disorder.Queue

    defdelegate enqueue(name, id, job), to: Disorder
    defdelegate delete(name, id), to: Disorder
    defdelegate get(bucket_key), to: Disorder.Service
    defdelegate keys_for_node(node, bucket), to: Disorder.Service

    @impl true
    def enqueue_id(name, id)
  end

  def enqueue_id(name, id) do
    name
    |> Honeydew.Queue.Disorder.queue_name
    |> GenServer.cast({:enqueue_id, id})
  end
end
