defmodule Honeydew.Worker do
  use GenStage
  alias Honeydew.Job
  require Logger

  defmodule State do
    defstruct [:queue, :module, :user_state]
  end

  def start_link(queue, module, args, init_retry_secs) do
    GenStage.start_link(__MODULE__, [queue, module, args, init_retry_secs])
  end

  def init([queue, module, args, init_retry_secs]) do
    state = %State{queue: queue, module: module}

    module.__info__(:functions)
    |> Enum.member?({:init, 1})
    |> worker_init(args, state)
    |> case do
         {:ok, state} ->
           queue
           |> Honeydew.group(:workers)
           |> :pg2.join(self())

           GenStage.cast(self(), :subscribe_to_queues)
           {:consumer, state}
         bad ->
           Logger.warn("#{module}.init/1 must return {:ok, state}, got: #{inspect(bad)}, retrying...")
           :timer.apply_after(init_retry_secs, Supervisor, :start_child, [Honeydew.supervisor(queue, :worker), []])
           :ignore
       end
  end

  def worker_init(true, args, %State{module: module} = state) do
    try do
      case apply(module, :init, [args]) do
        {:ok, user_state} -> {:ok, %{state | user_state: {:state, user_state}}}
        bad -> {:error, bad}
      end
    rescue e ->
        {:exception, e}
    end
  end
  def worker_init(false, _args, state), do: {:ok, %{state | user_state: :no_state}}

  def handle_events([%Job{task: task, from: from, monitor: monitor} = job], _from, %State{module: module, user_state: user_state} = state) do
    job = %{job | by: node()}

    :ok = GenServer.call(monitor, {:claim, job})

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

    {:noreply, [], state}
  end

  def handle_cast(:subscribe_to_queues, %State{queue: queue} = state) do
    queue
    |> Honeydew.get_all_members(:queues)
    |> Enum.each(&GenStage.async_subscribe(self(), to: &1, max_demand: 1, min_demand: 0, cancel: :temporary))

    {:noreply, [], state}
  end

  def handle_info(msg, state) do
    Logger.warn "[Honeydew] Worker #{inspect self()} received unexpected message #{inspect msg}"
    {:noreply, state}
  end
end
