defmodule Honeydew.Worker do
  use GenServer
  require Logger
  require Honeydew
  alias Honeydew.Job
  alias Honeydew.JobMonitor
  alias Honeydew.Queue
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
    defstruct [:queue,
               :queue_pid,
               :module,
               :has_init_fcn,
               :init_args,
               :init_retry_secs,
               :start_opts,
               {:ready, false},
               {:private, :no_state}]
  end

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
  def init([_supervisor, queue, %{ma: {module, init_args}, init_retry_secs: init_retry_secs}, queue_pid] = start_opts) do
    Process.flag(:trap_exit, true)

    queue
    |> Honeydew.group(Workers)
    |> :pg2.join(self())

    has_init_fcn =
      :functions
      |> module.__info__
      |> Enum.member?({:init, 1})

    module_init()

    {:ok, %State{queue: queue,
                 queue_pid: queue_pid,
                 module: module,
                 init_args: init_args,
                 init_retry_secs: init_retry_secs,
                 start_opts: start_opts,
                 has_init_fcn: has_init_fcn}}
  end

  #
  # Internal API
  #

  def run(worker, job, job_monitor), do: GenServer.cast(worker, {:run, %{job | job_monitor: job_monitor}})
  def module_init(me \\ self()), do: GenServer.cast(me, :module_init)
  def ready(ready), do: GenServer.cast(self(), {:ready, ready})


  @doc false
  def do_module_init(%State{has_init_fcn: false} = state) do
    %{state | ready: true} |> send_ready_or_callback
  end

  def do_module_init(%State{module: module, init_args: init_args} = state) do
    try do
      case apply(module, :init, [init_args]) do
        {:ok, private} ->
          %{state | private: {:state, private}, ready: true}
        bad ->
          Logger.warn("#{module}.init/1 must return {:ok, state :: any()}, got: #{inspect bad}")
          %{state | ready: false}
      end
    rescue e ->
      Logger.warn("#{module}.init/1 must return {:ok, state :: any()}, but raised #{inspect e}")
      %{state | ready: false}
    catch e ->
      Logger.warn("#{module}.init/1 must return {:ok, state :: any()}, but threw #{inspect e}")
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


  #
  # the job monitor's timer will nack the job, since we're not going to claim it
  #
  defp do_run(%Job{task: task, from: from, job_monitor: job_monitor} = job, %State{ready: true,
                                                                                   queue_pid: queue_pid,
                                                                                   module: module,
                                                                                   private: private}) do
    job = %{job | by: node()}

    :ok = JobMonitor.claim(job_monitor, job)
    Process.put(:job_monitor, job_monitor)

    private_args =
      case private do
        {:state, s} -> [s]
        :no_state   -> []
      end

    try do
      result =
        case task do
          f when is_function(f) -> apply(f, private_args)
          f when is_atom(f)     -> apply(module, f, private_args)
          {f, a}                -> apply(module, f, a ++ private_args)
        end
      {:ok, result}
    rescue e ->
        {:error, {e, System.stacktrace()}}
    catch e ->
        # this will catch exit signals too, which is ok, we just need to shut down in a
        # controlled manner due to a problem with a process that the user linked to
        {:error, {e, System.stacktrace()}}
    end
    |> case do
         {:ok, result} ->
           job = %{job | result: {:ok, result}}

           with {owner, _ref} <- from,
             do: send(owner, job)

           :ok = JobMonitor.job_succeeded(job_monitor)
           Process.delete(:job_monitor)

           Queue.worker_ready(queue_pid)
           :ok

         {:error, e} ->
           :ok = JobMonitor.job_failed(job_monitor, e)
           Process.delete(:job_monitor)
           :error
       end
  end


  @impl true
  def handle_cast(:module_init, state) do
    {:noreply, do_module_init(state)}
  end

  def handle_cast({:run, job}, state) do
    case do_run(job, state) do
      :ok ->
        {:noreply, state}
      :error ->
        restart_worker(state)
    end
  end

  #
  # Our Queue died, our QueueMonitor will stop us soon.
  #
  @impl true
  def handle_info({:EXIT, queue_pid, _reason}, %State{queue: queue, queue_pid: queue_pid} = state) do
    Logger.warn "[Honeydew] Worker #{inspect queue} (#{inspect self()}) saw its queue die, stopping..."
    restart_worker(state)
  end

  def handle_info(msg, %State{queue: queue} = state) do
    Logger.warn "[Honeydew] Worker #{inspect queue} (#{inspect self()}) received unexpected message #{inspect msg}, stopping..."
    restart_worker(state)
  end

  @impl true
  def terminate(:normal, _state), do: :ok
  def terminate(:shutdown, _state), do: :ok
  def terminate({:shutdown, _}, _state), do: :ok
  def terminate(reason, _state) do
    Logger.info "[Honeydew] Worker #{inspect self()} stopped because #{inspect reason}"
  end

  defp restart_worker(%State{start_opts: start_opts} = state) do
    WorkerSupervisor.start_worker(start_opts)
    {:stop, :normal, state}
  end
end
