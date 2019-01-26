defmodule Honeydew.JobMonitor do
  @moduledoc false

  use GenServer, restart: :transient

  alias Honeydew.Crash
  alias Honeydew.Logger, as: HoneydewLogger
  alias Honeydew.Queue

  require Logger
  require Honeydew

  # when the queue casts a job to a worker, it spawns a local JobMonitor with the job as state,
  # the JobMonitor watches the worker, if the worker dies (or its node is disconnected), the JobMonitor returns the
  # job to the queue. it waits @claim_delay miliseconds for the worker to confirm receipt of the job.

  @claim_delay 1_000 # ms

  defmodule State do
    @moduledoc false

    defstruct [:queue_pid, :worker, :job, :failure_mode, :success_mode, :progress]
  end

  def start_link(job, queue_pid, failure_mode, success_mode) do
    GenServer.start_link(__MODULE__, [job, queue_pid, failure_mode, success_mode])
  end

  def init([job, queue_pid, failure_mode, success_mode]) do
    Process.send_after(self(), :return_job, @claim_delay)

    {:ok, %State{job: job,
                 queue_pid: queue_pid,
                 failure_mode: failure_mode,
                 success_mode: success_mode,
                 progress: :awaiting_claim}}
  end


  #
  # Internal API
  #

  def claim(job_monitor, job), do: GenServer.call(job_monitor, {:claim, job})
  def job_succeeded(job_monitor), do: GenServer.call(job_monitor, :job_succeeded)
  def job_failed(job_monitor, %Crash{} = reason), do: GenServer.call(job_monitor, {:job_failed, reason})
  def status(job_monitor), do: GenServer.call(job_monitor, :status)
  def progress(job_monitor, progress), do: GenServer.call(job_monitor, {:progress, progress})


  def handle_call({:claim, job}, {worker, _ref}, %State{worker: nil} = state) do
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

  def handle_call(:job_succeeded, {worker, _ref}, %State{job: job, queue_pid: queue_pid, worker: worker, success_mode: success_mode} = state) do
    job = %{job | completed_at: System.system_time(:millisecond)}

    Queue.ack(queue_pid, job)

    with {success_mode_module, success_mode_args} <- success_mode,
      do: success_mode_module.handle_success(job, success_mode_args)

    {:stop, :normal, :ok, reset(state)}
  end

  def handle_call({:job_failed, reason}, {worker, _ref}, %State{worker: worker} = state) do
    execute_failure_mode(reason, state)

    {:stop, :normal, :ok, reset(state)}
  end

  # no worker has claimed the job, return it
  def handle_info(:return_job, %State{job: job, queue_pid: queue_pid, worker: nil} = state) do
    Queue.nack(queue_pid, job)

    {:stop, :normal, reset(state)}
  end
  def handle_info(:return_job, state), do: {:noreply, state}

  # worker died while busy
  def handle_info({:DOWN, _ref, :process, worker, reason}, %State{worker: worker, job: job} = state) do
    crash = Crash.new(:exit, reason)
    HoneydewLogger.job_failed(job, crash)
    execute_failure_mode(crash, state)

    {:stop, :normal, reset(state)}
  end

  def handle_info(msg, state) do
    Logger.warn "[Honeydew] Monitor #{inspect self()} received unexpected message #{inspect msg}"
    {:noreply, state}
  end

  defp reset(state) do
   %{state | job: nil, progress: :about_to_die}
  end

  defp execute_failure_mode(%Crash{} = crash, %State{job: job, failure_mode: {failure_mode, failure_mode_args}}) do
    failure_mode.handle_failure(job, format_failure_reason(crash), failure_mode_args)
  end

  defp format_failure_reason(%Crash{type: :exception, reason: exception, stacktrace: stacktrace}) do
    {exception, stacktrace}
  end

  defp format_failure_reason(%Crash{type: :throw, reason: thrown, stacktrace: stacktrace}) do
    {thrown, stacktrace}
  end

  defp format_failure_reason(%Crash{type: :exit, reason: reason}), do: reason
end
