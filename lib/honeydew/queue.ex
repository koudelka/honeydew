defmodule Honeydew.Queue do
  use GenServer
  require Logger
  require Honeydew
  alias Honeydew.Job
  alias Honeydew.Monitor

  defmodule State do
    defstruct queue: nil,
      module: nil,
      private: nil,
      dispatcher: nil,
      suspended: false,
      failure_mode: nil,
      success_mode: nil,
      monitors: MapSet.new
  end

  @type job :: Job.t
  @type private :: term
  @type name :: Honeydew.queue_name

  @callback init(name, arg :: term) :: {:ok, private}
  @callback enqueue(job, private) :: {private, job}
  @callback reserve(private) :: {private, job}
  @callback ack(job, private) :: private
  @callback nack(job, private) :: private
  @callback status(private) :: %{:count => number, :in_progress => number, optional(atom) => any}
  @callback filter(private, function) :: [job]
  @callback cancel(job, private) :: {:ok | {:error, :in_progress} | nil, private}

  # stolen from GenServer, with a slight change
  @callback handle_call(request :: term, GenServer.from, state :: private) ::
              {:reply, reply, new_state}
              | {:reply, reply, new_state, timeout | :hibernate}
              | {:noreply, new_state}
              | {:noreply, new_state, timeout | :hibernate}
              | {:stop, reason, reply, new_state}
              | {:stop, reason, new_state}
            when reply: term, new_state: private, reason: term

  @callback handle_cast(request :: term, state :: private) ::
              {:noreply, new_state}
              | {:noreply, new_state, timeout | :hibernate}
              | {:stop, reason :: term, new_state}
            when new_state: private

  @callback handle_info(msg :: :timeout | term, state :: private) ::
              {:noreply, new_state}
              | {:noreply, new_state, timeout | :hibernate}
              | {:stop, reason :: term, new_state}
            when new_state: private

  @optional_callbacks handle_call: 3, handle_cast: 2, handle_info: 2

  def start_link(queue, module, args, dispatcher, failure_mode, success_mode) do
    GenServer.start_link(__MODULE__, [queue, module, args, dispatcher, failure_mode, success_mode])
  end

  def init([queue, module, args, {dispatcher, dispatcher_args}, failure_mode, success_mode]) do
    queue
    |> Honeydew.group(:queues)
    |> :pg2.join(self())

    with {:global, _name} <- queue,
      do: :ok = :net_kernel.monitor_nodes(true)

    queue
    |> Honeydew.get_all_members(:workers)
    |> subscribe_workers

    {:ok, state} = module.init(queue, args)

    {:ok, dispatcher_private} = :erlang.apply(dispatcher, :init, dispatcher_args)

    {:ok, %State{queue: queue,
                  module: module,
                  private: state,
                  failure_mode: failure_mode,
                  success_mode: success_mode,
                  dispatcher: {dispatcher, dispatcher_private}}}
  end

  def handle_cast({:monitor_me, worker}, state) do
    Process.monitor(worker)
    {:noreply, state}
  end

  def handle_cast({:worker_ready, worker}, state) do
    Honeydew.debug "[Honeydew] Queue #{inspect self()} ready for worker #{inspect worker}"

    state =
      state
      |> check_in_worker(worker)
      |> dispatch
    {:noreply, state}
  end

  #
  # Ack/Nack
  #

  def handle_cast({:ack, job}, %State{module: module, private: private} = state) do
    Honeydew.debug "[Honeydew] Job #{inspect job.private} acked in #{inspect self()}"
    {:noreply, %{state | private: module.ack(job, private)}}
  end

  def handle_cast({:nack, job}, %State{module: module, private: private} = state) do
    Honeydew.debug "[Honeydew] Job #{inspect job.private} nacked by #{inspect self()}"
    private = module.nack(job, private)

    {:noreply, dispatch(%{state | private: private})}
  end

  #
  # Suspend/Resume
  #

  def handle_cast(:resume, %State{suspended: false} = state), do: {:noreply, state}
  def handle_cast(:resume, state) do
    # resume(state)

    {:noreply, dispatch(%{state | suspended: false})}
  end

  def handle_cast(:suspend, %State{suspended: true} = state), do: {:noreply, state}
  def handle_cast(:suspend, state) do
    # suspend(state)

    {:noreply, %{state | suspended: true}}
  end

  def handle_cast(msg, %State{module: module} = state) do
    module.handle_cast(msg, state)
  end

  #
  # Enqueue
  #

  def handle_call({:enqueue, job}, _from, state) do
    {private, job} = do_enqueue(job, state)
    state = %{state | private: private} |> dispatch
    {:reply, {:ok, job}, state}
  end

  def handle_call(:status, _from, %State{module: module, private: private, suspended: suspended, monitors: monitors} = state) do

    status =
      private
      |> module.status
      |> Map.put(:suspended, suspended)
      |> Map.put(:monitors, MapSet.to_list(monitors))

    {:reply, status, state}
  end

  def handle_call({:filter, function}, _from, %State{module: module, private: private} = state) do
    # try to prevent user code crashing the queue
    reply =
      try do
        {:ok, module.filter(private, function)}
      rescue e ->
          {:error, e}
      end
    {:reply, reply, state}
  end

  def handle_call({:cancel, job}, _from, %State{module: module, private: private} = state) do
    {reply, private} = module.cancel(job, private)
    {:reply, reply, %{state | private: private}}
  end

  # debugging
  def handle_call(:"$honeydew.state", _from, state) do
    {:reply, state, state}
  end

  def handle_call(msg, from, %State{module: module} = state) do
    module.handle_call(msg, from, state)
  end

  #
  # Worker Discovery
  #

  # when a node connects, ask it if it has any honeydew workers for this queue
  # we do it like this as there's a race condition between receiving this message
  # and :pg2 synchronizing groups
  def handle_info({:nodeup, node}, %State{queue: {:global, _} = queue} = state) do
    Logger.info "[Honeydew] Connection to #{node} established, looking for workers..."

    :rpc.async_call(node, :pg2, :get_local_members, [Honeydew.group(queue, :workers)])

    {:noreply, state}
  end

  def handle_info({:nodedown, node}, %State{queue: {:global, _}} = state) do
    Logger.warn "[Honeydew] Lost connection to #{node}."
    {:noreply, state}
  end

  # rpc get-workers reply
  def handle_info({_promise_pid, {:promise_reply, {:error, {:no_such_group, _worker_group}}}}, state), do: {:noreply, state}
  def handle_info({_promise_pid, {:promise_reply, workers}}, state) do
    Honeydew.debug "[Honeydew] Found #{Enum.count(workers)} workers."
    subscribe_workers(workers)
    {:noreply, state}
  end


  def handle_info({:DOWN, _ref, :process, process, _reason}, %State{monitors: monitors} = state) do
    state =
      if MapSet.member?(monitors, process) do
        %{state | monitors: MapSet.delete(monitors, process)}
      else
        Honeydew.debug "[Honeydew] Queue #{inspect self()} saw worker #{inspect process} crash"
        remove_worker(state, process)
      end
    {:noreply, state}
  end

  def handle_info(msg, %State{module: module} = state) do
    module.handle_info(msg, state)
  end

  defp do_enqueue(job, %State{module: module, private: private}) do
    job
    |> struct(enqueued_at: System.system_time(:millisecond))
    |> module.enqueue(private)
  end

  defp subscribe_workers(workers) do
    Enum.each(workers, &GenServer.cast(&1, :subscribe_to_queues))
  end

  defp send_job(worker, job, %State{queue: queue, failure_mode: failure_mode, success_mode: success_mode, monitors: monitors} = state) do
    {:ok, monitor} = Monitor.start(job, queue, failure_mode, success_mode)
    Process.monitor(monitor)
    GenServer.cast(worker, {:run, %{job | monitor: monitor}})
    %{state | monitors: MapSet.put(monitors, monitor)}
  end

  defp dispatch(%State{suspended: true} = state), do: state
  defp dispatch(%State{module: module, private: private} = state) do
    with true <- worker_available?(state),
          {private, job} <- module.reserve(private),
          state <- %{state | private: private},
          {worker, state} when not is_nil(worker) <- check_out_worker(job, state) do
      Honeydew.debug "[Honeydew] Queue #{inspect self()} dispatching job #{inspect job.private} to #{inspect worker}"
      state = send_job(worker, job, state)
      dispatch(state)
    else _ -> state
    end
  end

  defp worker_available?(%State{dispatcher: {dispatcher, dispatcher_private}}) do
    dispatcher.available?(dispatcher_private)
  end

  defp check_out_worker(job, %State{dispatcher: {dispatcher, dispatcher_private}} = state) do
    {worker, dispatcher_private} = dispatcher.check_out(job, dispatcher_private)
    {worker, %{state | dispatcher: {dispatcher, dispatcher_private}}}
  end

  defp check_in_worker(%State{dispatcher: {dispatcher, dispatcher_private}} = state, worker) do
    dispatcher_private = dispatcher.check_in(worker, dispatcher_private)
    %{state | dispatcher: {dispatcher, dispatcher_private}}
  end

  defp remove_worker(%State{dispatcher: {dispatcher, dispatcher_private}} = state, worker) do
    dispatcher_private = dispatcher.remove(worker, dispatcher_private)
    %{state | dispatcher: {dispatcher, dispatcher_private}}
  end
end
