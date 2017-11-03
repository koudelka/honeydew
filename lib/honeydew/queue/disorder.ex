# TODO:
# - investigate alternate data structures for the queue itself, maybe a binary search
#   tree to maintain order during handoffs

defmodule Honeydew.Queue.Disorder do
  alias Honeydew.Job

  @behaviour Honeydew.Queue

  @disorder Application.get_env(:honeydew, :disorder, Honeydew.Disorder)

  defmodule PState do
    defstruct [:name, :queue, :reserved]
  end

  @impl true
  def init({:global, name}, []) do
    GenServer.cast(self(), :reload) # inits our private state
    Process.register(self(), @disorder.queue_name(name))
    {:ok, %PState{name: {:global, name}}}
  end

  #
  # Enqueue/Reservee
  #

  @impl true
  def enqueue(job, %PState{name: {:global, name}} = state) do
    job = %{job | private: mk_id()}

    # this stores the job in the disorder cluster and contacts the appropriate queue partition
    # which is most likely not this process.
    :ok = @disorder.enqueue(name, job.private, job)

    {state, job}
  end

  @impl true
  def enqueue_id(id, %PState{queue: queue} = state) do
    %{state | queue: :queue.in(id, queue)}
  end

  @impl true
  # if the job's already running (in `reserved`), just let it be
  def unenqueue_id(id, %PState{queue: queue} = state) do
    %{state | queue: :queue.filter(&!match?(%Job{private: ^id}, &1), queue)}
  end

  @impl true
  def reserve(%PState{name: {:global, name}, queue: queue, reserved: reserved} = state) do
    case :queue.out(queue) do
      {:empty, _queue} -> {:empty, state}

      {{:value, id}, queue} ->
        case @disorder.get({name, id}) do
          # it's possible for value to be nil if one of the N values fetched is a tombstone
          # or this node doesn't have access to the job for some reason (handoffs pending, maybe)
          nil -> reserve(state)
          job -> {%{state | queue: queue, reserved: MapSet.put(reserved, id)}, job}
        end
    end
  end

  #
  # Ack/Nack
  #

  @impl true
  def ack(%Job{private: id}, %PState{name: {:global, name}, reserved: reserved} = state) do
    @disorder.delete(name, id)
    %{state | reserved: MapSet.delete(reserved, id)}
  end

  #requeue a new job with a new id via enqueue/1
  @impl true
  def nack(%Job{private: id} = job, %PState{reserved: reserved} = state) do
    {state, _job} = enqueue(job, state)
    %{state | reserved: MapSet.delete(reserved, id)}
  end

  #
  # Helpers
  #

  @impl true
  def reload(%PState{name: {:global, name}} = state) do
    keys = @disorder.keys_for_node(node(), name)

    queue =
      keys
      |> Enum.sort_by(fn {_, _, time} -> time end)
      |> :queue.from_list

    %{state | queue: queue, reserved: MapSet.new}
  end

  @impl true
  def status(%PState{queue: queue, reserved: reserved}) do
    %{count: :queue.len(queue) + MapSet.size(reserved),
      in_progress: MapSet.size(reserved)}
  end

  # TODO: should this be entirely disabled for disorder, since it's a massive coverage call?
  @impl true
  def filter(_pstate, _function) do
    raise "filter is unsupported in disorder"
  end

  # TODO: contact all queue processes and ask them to cancel, since it's not guaranteed that
  #       the owning queue actually has the job enqueued (it could be on a fallback queue)
  @impl true
  def cancel(%Job{private: private}, {pending, in_progress}) do
    filter = fn
      %Job{private: ^private} -> false;
      _ -> true
    end

    new_pending = :queue.filter(filter, pending)

    reply = cond do
      :queue.len(pending) > :queue.len(new_pending) -> :ok
      in_progress |> Map.values |> Enum.filter(&(!filter.(&1))) |> Enum.count > 0 -> {:error, :in_progress}
      true -> nil
    end

    {reply, {new_pending, in_progress}}
  end

  # the first two elements try to guarantee a globally unique id, and the last element
  # is for rough global ordering, Disorder doesn't guarantee strict ordering, so this
  # is fine assuming that our system clock isn't completely wrong.
  def mk_id do
    {node(), :erlang.unique_integer, :erlang.system_time(:millisecond)}
  end
end
