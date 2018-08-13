defmodule Honeydew.PollQueue do
  require Logger
  alias Honeydew.Job
  alias Honeydew.Queue
  alias Honeydew.Queue.State, as: QueueState

  @behaviour Queue

  @type job :: Job.t()
  @type private :: any()
  @type name :: Honeydew.queue_name()
  @type filter :: atom()

  @callback init(name, arg :: any()) :: {:ok, private}
  @callback reserve(private) :: {job, private}
  @callback ack(job, private) :: private
  @callback nack(job, private) :: private
  @callback status(private) :: %{:count => number, :in_progress => number, optional(atom) => any}
  @callback cancel(job, private) :: {:ok | {:error, :in_progress | :not_found}, private}
  @callback filter(private, filter) :: [job]

  @callback handle_info(msg :: :timeout | term, state :: private) ::
              {:noreply, new_state}
              | {:noreply, new_state, timeout | :hibernate}
              | {:stop, reason :: term, new_state}
            when new_state: private

  defmodule State do
    defstruct [:queue, :source, :poll_interval]
  end

  @impl true
  def validate_args!(args) do
    validate_poll_interval!(args[:poll_interval])
  end

  defp validate_poll_interval!(interval) when is_integer(interval), do: :ok
  defp validate_poll_interval!(nil), do: :ok
  defp validate_poll_interval!(arg), do: raise invalid_poll_interval_error(arg)

  defp invalid_poll_interval_error(argument) do
    "Poll interval must be an integer number of seconds. You gave #{inspect argument}"
  end

  @impl true
  def init(queue, [source, args]) do
    poll_interval = args[:poll_interval] * 1_000 |> trunc

    {:ok, source_state} = source.init(queue, args)
    source = {source, source_state}

    poll(poll_interval)

    {:ok, %State{queue: queue, source: source, poll_interval: poll_interval}}
  end

  @impl true
  def enqueue(job, state) do
    nack(job, state)
    {state, job}
  end

  @impl true
  def reserve(%State{source: {source, source_state}} = state) do
    case source.reserve(source_state) do
      {:empty, source_state} ->
        {:empty, %{state | source: {source, source_state}}}

      {{:value, {id, job}}, source_state} ->
        {%{job | private: id}, %{state | source: {source, source_state}}}
    end
  end

  @impl true
  def ack(job, %State{source: {source, source_state}} = state) do
    %{state | source: {source, source.ack(job, source_state)}}
  end

  @impl true
  def nack(job, %State{source: {source, source_state}} = state) do
    %{state | source: {source, source.nack(job, source_state)}}
  end

  @impl true
  def status(%State{source: {source, source_state}}) do
    source.status(source_state)
  end

  @impl true
  def filter(%State{source: {source, source_state}}, filter) when is_atom(filter) do
    source.filter(source_state, filter)
  end

  @impl true
  def filter(_state, _filter) do
    raise "Implementations of PollQueue only support predefined filters (atoms)"
  end

  @impl true
  def cancel(job, %State{source: {source, source_state}} = state) do
    {response, source_state} = source.cancel(job, source_state)
    {response, %{state | source: {source, source_state}}}
  end

  @impl true
  def handle_info(:__poll__, %QueueState{private: %State{poll_interval: poll_interval}} = queue_state) do
    poll(poll_interval)
    {:noreply, Queue.dispatch(queue_state)}
  end

  @impl true
  def handle_info(msg, %QueueState{private: %State{source: {source, _source_state}}} = queue_state) do
    source.handle_info(msg, queue_state)
  end

  defp poll(poll_interval) do
    {:ok, _} = :timer.send_after(poll_interval, :__poll__)
  end
end
