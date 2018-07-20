defmodule Honeydew.Worker do
  use GenServer
  require Logger
  require Honeydew
  alias Honeydew.Job
  alias Honeydew.Queue

  @init_retry_secs 5

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
               {:ready, false},
               {:private, :no_state}]
  end

  def child_spec(args, shutdown) do
    args
    |> child_spec
    |> Map.put(:restart, :transient)
    |> Map.put(:shutdown, shutdown)
  end

  @doc false
  def start_link([queue, %{ma: {module, init_args}}, queue_pid]) do
    GenServer.start_link(__MODULE__, [queue, queue_pid, module, init_args,])
  end

  @impl true
  def init([queue, queue_pid, module, init_args]) do
    Process.flag(:trap_exit, true)

    queue
    |> Honeydew.group(:workers)
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
                 has_init_fcn: has_init_fcn}}
  end


  def run(worker, job, job_monitor) do
    GenServer.cast(worker, {:run, %{job | job_monitor: job_monitor}})
  end

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
    end
    |> send_ready_or_callback
  end

  defp send_ready_or_callback(%State{queue_pid: queue_pid, ready: true} = state) do
    Honeydew.debug "[Honeydew] Worker #{inspect self()} sending ready"

    Process.link(queue_pid)
    Queue.worker_ready(queue_pid)

    state
  end

  defp send_ready_or_callback(%State{module: module} = state) do
    :functions
    |> module.__info__
    |> Enum.member?({:failed_init, 0})
    |> if do
      module.failed_init
    else
      Logger.info "[Honeydew] Worker #{inspect self()} re-initing in #{@init_retry_secs}s"
      :timer.apply_after(@init_retry_secs * 1_000, __MODULE__, :module_init, [self()])
    end

    state
  end


  #
  # the job monitor's timer will nack the job, since we're not going to claim it
  #
  defp do_run(%Job{task: task, from: from, job_monitor: job_monitor} = job, %State{ready: true, queue_pid: queue_pid, module: module, private: private}) do
    job = %{job | by: node()}

    :ok = GenServer.call(job_monitor, {:claim, job})
    Process.put(:job_monitor, job_monitor)

    private_args =
      case private do
        {:state, s} -> [s]
        :no_state   -> []
      end

    result =
      case task do
        f when is_function(f) -> apply(f, private_args)
        f when is_atom(f)     -> apply(module, f, private_args)
        {f, a}                -> apply(module, f, a ++ private_args)
      end

    job = %{job | result: {:ok, result}}

    with {owner, _ref} <- from,
      do: send(owner, job)

    :ok = GenServer.call(job_monitor, :ack)
    Process.delete(:job_monitor)

    GenServer.cast(queue_pid, {:worker_ready, self()})
  end


  @impl true
  def handle_cast(:module_init, state) do
    {:noreply, do_module_init(state)}
  end

  def handle_cast({:run, job}, state) do
    do_run(job, state)
    {:noreply, state}
  end

  @impl true
  def handle_info(msg, %State{queue: queue} = state) do
    Logger.warn "[Honeydew] Queue #{inspect queue} (#{inspect self()}) received unexpected message #{inspect msg}"
    {:noreply, state}
  end

  @impl true
  def terminate(:normal, _state), do: :ok
  def terminate(:shutdown, _state), do: :ok
  def terminate({:shutdown, _}, _state), do: :ok
  def terminate(reason, _state) do
    Logger.info "[Honeydew] Worker #{inspect self()} stopped because #{inspect reason}"
  end
end
