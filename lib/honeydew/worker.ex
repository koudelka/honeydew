defmodule Honeydew.Worker do
  use GenServer
  require Logger
  require Honeydew
  alias Honeydew.Job

  @doc """
  Invoked when the worker starts up for the first time.
  """
  @callback init(args :: term) :: {:ok, state :: term}
  @optional_callbacks init: 1

  defmodule State do
    defstruct [:queue, :queue_pid, :module, :user_state]
  end

  @doc false
  def start_link(queue, %{ma: {module, args}, init_retry: init_retry_secs}, queue_pid) do
    GenServer.start_link(__MODULE__, [queue, queue_pid, module, args, init_retry_secs])
  end

  def init([queue, queue_pid, module, args, init_retry_secs]) do
    Process.flag(:trap_exit, true)
    state = %State{queue: queue, queue_pid: queue_pid, module: module}

    module.__info__(:functions)
    |> Enum.member?({:init, 1})
    |> worker_init(args, state)
    |> case do
         {:ok, state} ->
           queue
           |> Honeydew.group(:workers)
           |> :pg2.join(self())

           GenServer.cast(self(), :subscribe_to_queues)
           {:ok, state}
         bad ->
           Logger.warn("#{module}.init/1 must return {:ok, state}, got: #{inspect bad}, retrying in #{init_retry_secs}s...")
           :timer.apply_after(init_retry_secs * 1_000, Supervisor, :start_child, [Honeydew.supervisor(queue, :worker), []])
           :ignore
       end
  end

  @doc false
  def worker_init(true, args, %State{module: module} = state) do
    try do
      case apply(module, :init, [args]) do
        {:ok, user_state} ->
          {:ok, %{state | user_state: {:state, user_state}}}
        bad ->
          {:error, bad}
      end
    rescue e ->
        {:exception, e}
    end
  end
  def worker_init(false, _args, state), do: {:ok, %{state | user_state: :no_state}}

  def handle_cast({:run, %Job{task: task, from: from, monitor: monitor} = job}, %State{queue: queue, module: module, user_state: user_state} = state) do
    job = %{job | by: node()}

    :ok = GenServer.call(monitor, {:claim, job})
    Process.put(:monitor, monitor)

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

    :ok = GenServer.call(monitor, :ack)
    Process.delete(:monitor)

    queue
    |> Honeydew.get_queue
    |> GenServer.cast({:worker_ready, self()})

    {:noreply, state}
  end

  def handle_cast(:subscribe_to_queues, %State{queue: queue} = state) do
    Honeydew.debug "[Honeydew] Worker #{inspect self()} sending ready"
    queue
    |> Honeydew.get_all_members(:queues)
    |> Enum.each(&GenServer.cast(&1, {:monitor_me, self()}))

    queue
    |> Honeydew.get_all_members(:queues)
    |> Enum.each(&GenServer.cast(&1, {:worker_ready, self()}))

    {:noreply, state}
  end

  def handle_info({:EXIT, _pid, :normal}, state), do: {:noreply, state}
  def handle_info({:EXIT, _pid, :shutdown}, state), do: {:noreply, state}
  def handle_info({:EXIT, pid, reason}, state) do
    Logger.warn "[Honeydew] Worker #{inspect self()} died because linked process #{inspect pid} crashed"
    {:stop, reason, %{state | user_state: nil}}
  end

  def handle_info({_, {:DOWN, _, :normal}}, state), do: {:noreply, state}
  def handle_info({_, {:DOWN, _, :shutdown}}, state), do: {:noreply, state}
  def handle_info(msg, state) do
    Logger.warn "[Honeydew] Worker #{inspect self()} received unexpected message #{inspect msg}"
    {:noreply, state}
  end

  def terminate(reason, _state) do
    Logger.info "[Honeydew] Worker #{inspect self()} stopped because #{inspect reason}"
  end

end
