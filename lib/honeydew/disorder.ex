defmodule Honeydew.Disorder do
  alias Honeydew.Job

  defmodule Behaviour do
    @type id :: {node, node_uniq :: integer, sort_key :: integer}
    @callback queue_name(name :: atom | String.t) :: atom
    @callback enqueue(name :: atom | String.t, id, Job.t) :: :ok
    @callback get({name :: atom | String.t, id}) :: Job.t | nil
    @callback delete(name :: atom | String.t, id) :: :ok | {:error, reason :: term}
    @callback keys_for_node(node, name :: atom | String.t) :: [id]
  end

  if Code.ensure_loaded?(Disorder) do
    @behaviour Behaviour

    defdelegate enqueue(name, id, job), to: Disorder
    defdelegate delete(name, id), to: Disorder
    defdelegate get(bucket_key), to: Disorder.Service
    defdelegate keys_for_node(node, bucket), to: Disorder.Service
    defdelegate queue_name(name), to: Disorder.Util
  end
end
