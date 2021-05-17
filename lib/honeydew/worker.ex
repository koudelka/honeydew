defmodule Honeydew.Worker do
  @moduledoc """
    A Honeydew Worker, how you specify your jobs.
  """
  use GenServer
  require Logger
  require Honeydew

  alias Honeydew.Crash
  alias Honeydew.Job
  alias Honeydew.JobMonitor
  alias Honeydew.Logger, as: HoneydewLogger
  alias Honeydew.Processes
  alias Honeydew.Queue
  alias Honeydew.JobRunner
  alias Honeydew.Workers
  alias Honeydew.WorkerSupervisor

  @type private :: term

  @doc """
  Invoked when the worker starts up for the first time.
  """
  @callback init(args :: term) :: {:ok, state :: private}

  @doc """
  Invoked when `init/1` returns anything other than `{:ok, state}` or raises an error
  """
  @callback init_failed() :: any()

  @optional_callbacks init: 1, init_failed: 0

  defmodule State do
    @moduledoc false

    defstruct [:queue,
               :queue_pid,
               :module,
               :has_init_fcn,
               :init_args,
               :init_retry_secs,
               :start_opts,
               :job_runner,
               :job,
               {:ready, false},
               {:private, :no_state}]
  end

  @doc false
  def child_spec([_supervisor, _queue, %{shutdown: shutdown}, _queue_pid] = opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      restart: :transient,
      shutdown: shutdown
    }
  end

  @doc false
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @impl true
  @doc false
  def init([_supervisor, queue, %{ma: {module, init_args}, init_retry_secs: init_retry_secs}, queue_pid] = start_opts) do
    Process.flag(:trap_exit, true)

    :ok = Processes.join_group(Workers, queue, self())

    has_init_fcn =
      :functions
      |> module.__info__
      |> Enum.member?({:init, 1})

    {:ok, %State{queue: queue,
                 queue_pid: queue_pid,
                 module: module,
                 init_args: init_args,
                 init_retry_secs: init_retry_secs,
                 start_opts: start_opts,
                 has_init_fcn: has_init_fcn}, {:continue, :module_init}}
  end

  #
  # Internal API
  #

  @doc false
  def run(worker, job, job_monitor), do: GenServer.cast(worker, {:run, %{job | job_monitor: job_monitor}})
  @doc false
  def module_init(me \\ self()), do: GenServer.cast(me, :module_init)
  @doc false
  def ready(ready), do: GenServer.cast(self(), {:ready, ready})
  @doc false
  def job_finished(worker, job), do: GenServer.call(worker, {:job_finished, job})


  defp do_module_init(%State{has_init_fcn: false} = state) do
    %{state | ready: true} |> send_ready_or_callback
  end

  defp do_module_init(%State{module: module, init_args: init_args} = state) do
    try do
      case apply(module, :init, [init_args]) do
        {:ok, private} ->
          %{state | private: {:state, private}, ready: true}
        bad ->
          HoneydewLogger.worker_init_crashed(module, Crash.new(:bad_return_value, bad))
          %{state | ready: false}
      end
    rescue e ->
      HoneydewLogger.worker_init_crashed(module, Crash.new(:exception, e, __STACKTRACE__))
      %{state | ready: false}
    catch
      :exit, reason ->
        HoneydewLogger.worker_init_crashed(module, Crash.new(:exit, reason))
        %{state | ready: false}
      e ->
        HoneydewLogger.worker_init_crashed(module, Crash.new(:throw, e, __STACKTRACE__))
        %{state | ready: false}
    end
    |> send_ready_or_callback
  end

  defp send_ready_or_callback(%State{queue_pid: queue_pid, ready: true} = state) do
    Honeydew.debug "[Honeydew] Worker #{inspect self()} sending ready"

    Process.link(queue_pid)
    Queue.worker_ready(queue_pid)

    state
  end

  defp send_ready_or_callback(%State{module: module, init_retry_secs: init_retry_secs} = state) do
    :functions
    |> module.__info__
    |> Enum.member?({:failed_init, 0})
    |> if do
      module.failed_init
    else
      Logger.info "[Honeydew] Worker #{inspect self()} re-initing in #{init_retry_secs}s"
      :timer.apply_after(init_retry_secs * 1_000, __MODULE__, :module_init, [self()])
    end

    state
  end

  defp do_run(%Job{job_monitor: job_monitor} = job, %State{module: module, private: private} = state) do
    job = %{job | by: node()}

    :ok = JobMonitor.claim(job_monitor, job)

    {:ok, job_runner} = JobRunner.run_link(job, module, private)

    %{state | job_runner: job_runner, job: job}
  end

  defp do_job_finished(%Job{result: {:ok, result}, job_monitor: job_monitor}, %State{queue_pid: queue_pid}) do
    :ok = JobMonitor.job_succeeded(job_monitor, result)

    Process.delete(:job_monitor)
    Queue.worker_ready(queue_pid)

    :ok
  end

  defp do_job_finished(%Job{result: {:error, %Crash{} = crash}, job_monitor: job_monitor} = job, _state) do
    HoneydewLogger.job_failed(job, crash)
    :ok = JobMonitor.job_failed(job_monitor, crash)
    Process.delete(:job_monitor)

    :error
  end

  @impl true
  @doc false
  def handle_continue(:module_init, state) do
    {:noreply, do_module_init(state)}
  end

  @doc false
  def handle_continue({:job_finished, job}, state) do
    case do_job_finished(job, state) do
      :ok ->
        {:noreply, state}
      :error ->
        restart(state)
    end
  end

  @impl true
  @doc false
  def handle_cast(:module_init, state), do: {:noreply, do_module_init(state)}
  def handle_cast({:run, job}, state), do: {:noreply, do_run(job, state)}

  @impl true
  @doc false
  def handle_call({:job_finished, job}, {job_runner, _ref}, %State{job_runner: job_runner} = state) do
    Process.unlink(job_runner)
    {:reply, :ok, %{state | job_runner: nil, job: nil}, {:continue, {:job_finished, job}}}
  end

  #
  # Our Queue died, our QueueMonitor will stop us soon.
  #
  @impl true
  @doc false
  def handle_info({:EXIT, queue_pid, _reason}, %State{queue: queue, queue_pid: queue_pid} = state) do
    Logger.warn "[Honeydew] Worker #{inspect queue} (#{inspect self()}) saw its queue die, stopping..."
    {:noreply, state}
  end

  def handle_info({:EXIT, _pid, :normal}, %State{job_runner: nil} = state), do: {:noreply, state}
  def handle_info({:EXIT, _pid, :shutdown}, %State{job_runner: nil} = state), do: {:noreply, state}
  def handle_info({:EXIT, _pid, {:shutdown, _}}, %State{job_runner: nil} = state), do: {:noreply, state}

  def handle_info({:EXIT, job_runner, reason}, %State{job_runner: job_runner, queue: queue, job: job} = state) do
    Logger.warn "[Honeydew] Worker #{inspect queue} (#{inspect self()}) saw its job runner (#{inspect job_runner}) die during a job, restarting..."
    job = %{job | result: {:error, Crash.new(:exit, reason)}}
    {:noreply, state, {:continue, {:job_finished, job}}}
  end

  def handle_info(msg, %State{queue: queue} = state) do
    Logger.warn "[Honeydew] Worker #{inspect queue} (#{inspect self()}) received unexpected message #{inspect msg}, restarting..."
    restart(state)
  end


  defp restart(%State{start_opts: start_opts} = state) do
    WorkerSupervisor.start_worker(start_opts)
    {:stop, :normal, state}
  end
end
