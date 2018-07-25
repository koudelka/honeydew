defmodule Honeydew.Queue do
  use GenServer, restart: :transient
  require Logger
  require Honeydew
  alias Honeydew.Job
  alias Honeydew.JobMonitor
  alias Honeydew.Worker
  alias Honeydew.WorkerStarter
  alias Honeydew.Queues

  defmodule State do
    defstruct [:queue,
               :module,
               :private,
               :dispatcher,
               :failure_mode,
               :success_mode,
               {:suspended, false},
               {:job_monitors, %{}}]
  end

  @type job :: Job.t
  @type private :: term
  @type name :: Honeydew.queue_name
  @type filter :: Honeydew.filter()

  @callback init(name, arg :: term) :: {:ok, private}
  @callback enqueue(job, private) :: {private, job}
  @callback reserve(private) :: {job, private}
  @callback ack(job, private) :: private
  @callback nack(job, private) :: private
  @callback status(private) :: %{:count => number, :in_progress => number, optional(atom) => any}
  @callback filter(private, filter) :: [job]
  @callback cancel(job, private) :: {:ok | {:error, :in_progress | :not_found}, private}

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

  @spec child_spec([name | any()]) :: Supervisor.child_spec()
  def child_spec([name | _] = opts) do
    opts
    |> super
    |> Map.put(:id, name)
  end

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @impl true
  def init([queue, module, args, {dispatcher, dispatcher_args}, failure_mode, success_mode, suspended]) do
    Process.flag(:trap_exit, true)

    :ok =
      queue
      |> Honeydew.group(Queues)
      |> :pg2.create

    :ok =
      queue
      |> Honeydew.group(Queues)
      |> :pg2.join(self())

    with {:global, _name} <- queue,
      do: :ok = :net_kernel.monitor_nodes(true)

    start_workers(queue)

    {:ok, state} = module.init(queue, args)

    {:ok, dispatcher_private} = :erlang.apply(dispatcher, :init, dispatcher_args)

    {:ok, %State{queue: queue,
                  module: module,
                  private: state,
                  failure_mode: failure_mode,
                  success_mode: success_mode,
                  suspended: suspended,
                  dispatcher: {dispatcher, dispatcher_private}}}
  end

  #
  # Honeydew API
  #

  def enqueue(queue_process, job), do: GenServer.call(queue_process, {:enqueue, job})
  def status(queue_process), do: GenServer.call(queue_process, :status)
  def filter(queue_process, filter), do: GenServer.call(queue_process, {:filter, filter})
  def cancel(queue_process, job), do: GenServer.call(queue_process, {:cancel, job})
  def resume(queue_process), do: GenServer.call(queue_process, :resume)
  def suspend(queue_process), do: GenServer.call(queue_process, :suspend)

  #
  # Internal API
  #

  def worker_ready(queue_process), do: GenServer.cast(queue_process, {:worker_ready, self()})
  def worker_not_ready(queue_process), do: GenServer.cast(queue_process, {:worker_not_ready, self()})
  def ack(queue_process, job), do: GenServer.cast(queue_process, {:ack, job})
  def nack(queue_process, job), do: GenServer.cast(queue_process, {:nack, job})


  defp do_enqueue(job, %State{module: module, private: private} = state) do
    {private, job} =
      job
      |> struct(enqueued_at: System.system_time(:millisecond))
      |> module.enqueue(private)
    state = %{state | private: private} |> dispatch
    {job, state}
  end

  defp do_status(%State{module: module, private: private, suspended: suspended, job_monitors: job_monitors}) do
    private
    |> module.status
    |> Map.put(:suspended, suspended)
    |> Map.put(:job_monitors, Map.keys(job_monitors))
  end

  defp do_filter(filter, %State{module: module, private: private}) do
    # try to prevent user code crashing the queue
    try do
      {:ok, module.filter(private, filter)}
    rescue e ->
        {:error, e}
    end
  end

  defp do_cancel(job, %State{module: module, private: private} = state) do
    {reply, private} = module.cancel(job, private)
    {reply, %{state | private: private}}
  end

  defp do_resume(%State{suspended: false} = state), do: state
  defp do_resume(state) do
    # module.resume(state)
    dispatch(%{state | suspended: false})
  end

  defp do_suspend(%State{suspended: true} = state), do: state
  defp do_suspend(state) do
    # module.suspend(state)
    %{state | suspended: true}
  end

  #
  # Worker Lifecycle
  #

  def do_worker_ready(worker, state) do
    Honeydew.debug "[Honeydew] Queue #{inspect self()}, worker #{inspect worker} is ready."

    state
    |> check_in_worker(worker)
    |> dispatch
  end

  def do_worker_not_ready(worker, state) do
    Honeydew.debug "[Honeydew] Queue #{inspect self()}, worker #{inspect worker} is NOT ready."

    remove_worker(state, worker)
  end

  def node_up(queue, node) do
    Logger.info "[Honeydew] Connection to #{node} established, asking it to start workers for queue #{inspect queue}"
    start_workers(queue, node)
  end

  def node_down(node) do
    Logger.warn "[Honeydew] Lost connection to #{node}."
  end

  def worker_stopped(worker, state) do
    Honeydew.debug "[Honeydew] Queue #{inspect self()} saw worker #{inspect worker} stop normally"
    remove_worker(state, worker)
  end

  def worker_crashed(worker, reason, state) do
    Logger.warn "[Honeydew] Queue #{inspect self()} saw worker #{inspect worker} crash because #{inspect reason}"
    remove_worker(state, worker)
  end

  #
  # Job Monitor Lifecycle
  #

  def job_monitor_stopped(job_monitor, %State{job_monitors: job_monitors} = state) do
    %{state | job_monitors: Map.delete(job_monitors, job_monitor)}
  end

  def job_monitor_crashed(job_monitor, reason, %State{job_monitors: job_monitors} = state) do
    {job, job_monitors} = Map.pop(job_monitors, job_monitor)
    Logger.warn "[Honeydew] Job Monitor #{inspect job_monitor} crashed, this really should never happen, is there a bug in the success/failure mode module? Reason: #{inspect reason} Job: #{inspect job}"
    %{state | job_monitors: job_monitors}
  end

  #
  # Ack/Nack
  #

  def do_ack(job, %State{module: module, private: private} = state) do
    Honeydew.debug "[Honeydew] Job #{inspect job.private} acked in #{inspect self()}"
    %{state | private: module.ack(job, private)}
  end

  def do_nack(job, %State{module: module, private: private} = state) do
    Honeydew.debug "[Honeydew] Job #{inspect job.private} nacked by #{inspect self()}"
    dispatch(%{state | private: module.nack(job, private)})
  end

  #
  # GenServer Callbacks
  #

  @impl true
  def handle_call({:enqueue, job}, _from, state) do
    {job, state} = do_enqueue(job, state)
    {:reply, {:ok, job}, state}
  end

  def handle_call({:cancel, job}, _from,  state) do
    {reply, state} = do_cancel(job, state)
    {:reply, reply, state}
  end

  def handle_call(:status, _, state), do: {:reply, do_status(state), state}
  def handle_call({:filter, filter}, _, state), do: {:reply, do_filter(filter, state), state}
  def handle_call(:resume, _, state), do: {:reply, :ok, do_resume(state)}
  def handle_call(:suspend, _, state), do: {:reply, :ok, do_suspend(state)}
  def handle_call(msg, from, %State{module: module} = state), do: module.handle_call(msg, from, state)

  @impl true
  def handle_cast({:worker_ready, worker}, state), do: {:noreply, do_worker_ready(worker, state)}
  def handle_cast({:worker_not_ready, worker}, state), do: {:noreply, do_worker_not_ready(worker, state)}
  def handle_cast({:ack, job}, state), do: {:noreply, do_ack(job, state)}
  def handle_cast({:nack, job}, state), do: {:noreply, do_nack(job, state)}
  def handle_cast(msg, %State{module: module} = state), do: module.handle_cast(msg, state)

  @impl true
  def handle_info({:nodeup, node}, %State{queue: {:global, _} = queue} = state) do
    node_up(queue, node)
    {:noreply, state}
  end

  def handle_info({:nodedown, node}, %State{queue: {:global, _}} = state) do
    node_down(node)
    {:noreply, state}
  end

  def handle_info({:EXIT, process, reason}, state), do: process_halted(process, reason, state)
  def handle_info({:DOWN, _ref, :process, process, reason}, state), do: process_halted(process, reason, state)

  def handle_info(msg, %State{queue: queue, module: module} = state) do
    :functions
    |> module.__info__
    |> Enum.member?({:handle_info, 2})
    |> if do
      module.handle_info(msg, state)
    else
      Logger.warn "[Honeydew] Queue #{inspect queue} (#{inspect self()}) received unexpected message #{inspect msg}"
      {:noreply, state}
    end
  end


  defp process_halted(process, :normal, state), do: process_finished(process, state)
  defp process_halted(process, :shutdown, state), do: process_finished(process, state)
  defp process_halted(process, {:shutdown, _}, state), do: process_finished(process, state)
  defp process_halted(process, reason, state), do: process_crashed(process, reason, state)

  defp process_finished(process, state) do
    state =
      case process_type(process, state) do
        :worker -> worker_stopped(process, state)
        :job_monitor -> job_monitor_stopped(process, state)
        :unknown ->
          Logger.warn "[Honeydew] Received non-crash EXIT/DOWN message for unknown process #{inspect process}"
          state
      end
    {:noreply, state}
  end

  defp process_crashed(process, reason, state) do
    state =
      case process_type(process, state) do
        :worker -> worker_crashed(process, reason, state)
        :job_monitor -> job_monitor_crashed(process, reason, state)
        :unknown ->
          Logger.warn "[Honeydew] Received EXIT/DOWN message for unknown process #{inspect process}, reason: #{inspect reason}"
          state
      end
    {:noreply, state}
  end

  defp process_type(process, %State{job_monitors: job_monitors, dispatcher: {dispatcher, dispatcher_private}}) do
    cond do
      Map.has_key?(job_monitors, process) -> :job_monitor
      dispatcher.known?(process, dispatcher_private) -> :worker
      true -> :unknown
    end
  end

  defp start_workers({:global, _} = queue) do
    :known # start workers on this node too, if need be
    |> :erlang.nodes
    |> Enum.each(&start_workers(queue, &1))
  end

  defp start_workers(queue) do
    start_workers(queue, node())
  end

  defp start_workers(queue, node) do
    WorkerStarter.queue_available(queue, node)
  end

  defp send_job(worker, job, %State{failure_mode: failure_mode, success_mode: success_mode, job_monitors: job_monitors} = state) do
    {:ok, job_monitor} = JobMonitor.start_link(job, self(), failure_mode, success_mode)
    Worker.run(worker, job, job_monitor)
    %{state | job_monitors: Map.put(job_monitors, job_monitor, job)}
  end

  def dispatch(%State{suspended: true} = state), do: state
  def dispatch(%State{module: module, private: private} = state) do
    with true <- worker_available?(state),
          {%Job{} = job, private} <- module.reserve(private),
          state <- %{state | private: private},
          {worker, state} when not is_nil(worker) <- check_out_worker(job, state) do
      Honeydew.debug "[Honeydew] Queue #{inspect self()} dispatching job #{inspect job.private} to #{inspect worker}"
      worker
      |> send_job(job, state)
      |> dispatch
    else
      # no worker available
      false -> state
      # empty queue, we update the private state as the queue may have had an id enqueued,
      # but decided that the job was invalid (or missing, see Disorder queue's reserve/1)
      {:empty, private} -> %{state | private: private}
      # dispatcher didn't provide a worker
      {nil, state} -> state
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
