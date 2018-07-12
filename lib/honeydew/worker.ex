defmodule Honeydew.Worker do
  use GenServer
  require Logger
  require Honeydew
  alias Honeydew.Job
  alias Honeydew.Queue

  @type private :: term

  @doc """
  Invoked when the worker starts up for the first time.
  """
  @callback init(args :: term) :: {:ok, state :: term}

  @callback handle_info(msg :: :timeout | term, state :: private) ::
  {:noreply, new_state}
  | {:noreply, new_state, timeout | :hibernate}
  | {:stop, reason :: term, new_state}
  when new_state: private

  @optional_callbacks init: 1, handle_info: 2

  defmodule State do
    defstruct [:queue,
               :queue_pid,
               :module,
               :has_init_fcn?,
               :init_args,
               {:user_state, :no_state}]
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

    GenServer.cast(self(), :init)

    has_init_fcn =
      :functions
      |> module.__info__
      |> Enum.member?({:init, 1})

    {:ok, %State{queue: queue,
                 queue_pid: queue_pid,
                 module: module,
                 has_init_fcn?: has_init_fcn,
                 init_args: init_args}}
  end

  def run(worker, job, job_monitor) do
    GenServer.cast(worker, {:run, %{job | job_monitor: job_monitor}})
  end

  @doc false
  def do_module_init(%State{has_init_fcn?: false} = state), do: send_ready(state)
  def do_module_init(%State{module: module, init_args: init_args} = state) do
    try do
      case apply(module, :init, [init_args]) do
        {:ok, user_state} ->
          %{state | user_state: {:state, user_state}}
        bad ->
          Logger.warn("#{module}.init/1 must return {:ok, state}, got: #{inspect bad}")
          state
      end
    rescue e ->
        Logger.warn("#{module}.init/1 must return {:ok, state}, but raised #{inspect e}")
        state
    end
    |> send_ready
  end

  defp send_ready(%State{queue_pid: queue_pid} = state) do
    Honeydew.debug "[Honeydew] Worker #{inspect self()} sending ready"

    Process.link(queue_pid)
    Queue.worker_ready(queue_pid)

    state
  end

  defp do_run(%Job{task: task, from: from, job_monitor: job_monitor} = job, %State{queue_pid: queue_pid, module: module, user_state: user_state}) do
    job = %{job | by: node()}

    :ok = GenServer.call(job_monitor, {:claim, job})
    Process.put(:job_monitor, job_monitor)

    user_state_args =
      case user_state do
        {:state, s} -> [s]
        :no_state   -> []
      end

    result =
      case task do
        f when is_function(f) -> apply(f, user_state_args)
        f when is_atom(f)     -> apply(module, f, user_state_args)
        {f, a}                -> apply(module, f, a ++ user_state_args)
      end

    job = %{job | result: {:ok, result}}

    with {owner, _ref} <- from,
      do: send(owner, job)

    :ok = GenServer.call(job_monitor, :ack)
    Process.delete(:job_monitor)

    GenServer.cast(queue_pid, {:worker_ready, self()})
  end


  @impl true
  def handle_cast(:init, state) do
    {:noreply, do_module_init(state)}
  end

  def handle_cast({:run, job}, state) do
    do_run(job, state)
    {:noreply, state}
  end

  @impl true
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

  @impl true
  def terminate(:normal, _state), do: :ok
  def terminate(:shutdown, _state), do: :ok
  def terminate({:shutdown, _}, _state), do: :ok
  def terminate(reason, _state) do
    Logger.info "[Honeydew] Worker #{inspect self()} stopped because #{inspect reason}"
  end

end
