defmodule Honeydew.JobMonitor do
  use GenServer
  require Logger
  require Honeydew

  # when the queue casts a job to a worker, it spawns a local Monitor with the job as state,
  # the Monitor watches the worker, if the worker dies (or its node is disconnected), the Monitor returns the
  # job to the queue. it waits @claim_delay miliseconds for the worker to confirm receipt of the job.

  @claim_delay 5_000 # ms

  defmodule State do
    defstruct [:queue_pid, :worker, :job, :failure_mode, :success_mode, :progress]
  end

  def start_link(job, queue_pid, failure_mode, success_mode) do
    GenServer.start_link(__MODULE__, [job, queue_pid, failure_mode, success_mode])
  end

  def init([job, queue_pid, failure_mode, success_mode]) do
    Process.send_after(self(), :return_job, @claim_delay)

    {:ok, %State{job: job, queue_pid: queue_pid, failure_mode: failure_mode, success_mode: success_mode, progress: :awaiting_claim}}
  end

  def handle_call({:claim, job}, {worker, _ref}, state) do
    Honeydew.debug "[Honeydew] Monitor #{inspect self()} had job #{inspect job.private} claimed by worker #{inspect worker}"
    Process.monitor(worker)
    job = %{job | started_at: System.system_time(:millisecond)}
    {:reply, :ok, %{state | job: job, worker: worker, progress: :running}}
  end

  def handle_call(:status, _from, %State{job: job, worker: worker, progress: progress} = state) do
    {:reply, {worker, {job, progress}}, state}
  end

  def handle_call({:progress, progress}, _from, state) do
    {:reply, :ok, %{state | progress: {:running, progress}}}
  end

  def handle_call(:ack, {worker, _ref}, %State{job: job, queue_pid: queue_pid, worker: worker, success_mode: success_mode} = state) do
    job = %{job | completed_at: System.system_time(:millisecond)}

    GenServer.cast(queue_pid, {:ack, job})

    with {success_mode_module, success_mode_args} <- success_mode,
      do: success_mode_module.handle_success(job, success_mode_args)

    {:stop, :normal, :ok, reset(state)}
  end

  # no worker has claimed the job, return it
  def handle_info(:return_job, %State{job: job, queue_pid: queue_pid, worker: nil} = state) do
    GenServer.cast(queue_pid, {:nack, job})

    {:stop, :normal, reset(state)}
  end
  def handle_info(:return_job, state), do: {:noreply, state}

  # worker died while busy
  def handle_info({:DOWN, _ref, :process, worker, reason}, %State{worker: worker, job: job, failure_mode: {failure_mode, failure_mode_args}} = state) do
    failure_mode.handle_failure(job, reason, failure_mode_args)

    {:stop, :normal, reset(state)}
  end

  def handle_info(msg, state) do
    Logger.warn "[Honeydew] Monitor #{inspect self()} received unexpected message #{inspect msg}"
    {:noreply, state}
  end

  defp reset(state) do
   %{state | job: nil, progress: :about_to_die}
  end
end
