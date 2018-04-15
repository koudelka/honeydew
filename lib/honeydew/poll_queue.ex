defmodule Honeydew.PollQueue do
  require Logger
  alias Honeydew.Job
  alias Honeydew.Queue
  alias Honeydew.Queue.State, as: QueueState

  @behaviour Queue

  @type job :: Job.t()
  @type private :: any()
  @type name :: Honeydew.queue_name()

  @callback init(name, arg :: any()) :: {:ok, private}
  @callback reserve(private) :: {job, private}
  @callback ack(job, private) :: private
  @callback nack(job, private) :: private
  @callback status(private) :: %{:count => number, :in_progress => number, optional(atom) => any}

  @callback handle_info(msg :: :timeout | term, state :: private) ::
              {:noreply, new_state}
              | {:noreply, new_state, timeout | :hibernate}
              | {:stop, reason :: term, new_state}
            when new_state: private

  defmodule State do
    defstruct [:queue, :source, :interval]
  end

  @impl true
  def init(queue, [source, args]) do
    interval = Keyword.get(args, :interval, 1_000)

    {:ok, source_state} = source.init(queue, args)
    source = {source, source_state}

    poll(interval)

    {:ok, %State{queue: queue, source: source, interval: interval}}
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
  def filter(_state, _function) do
    raise "filter/2 is unsupported for poll queues"
  end

  @impl true
  def cancel(_job, _state) do
    raise "cancel/2 is unsupported for poll queues"
  end

  @impl true
  def handle_info(:__poll__, %QueueState{private: %State{interval: interval}} = queue_state) do
    poll(interval)
    {:noreply, Queue.dispatch(queue_state)}
  end

  @impl true
  def handle_info(msg, %QueueState{private: %State{source: {source, _source_state}}} = queue_state) do
    source.handle_info(msg, queue_state)
  end

  defp poll(interval) do
    {:ok, _} = :timer.send_after(interval, :__poll__)
  end
end
