# when a queue comes online (or its node connects), it sends a message to this process to start workers.
defmodule Honeydew.WorkerStarter do
  @moduledoc false

  use GenServer

  alias Honeydew.WorkerGroupSupervisor
  alias Honeydew.Processes

  require Logger

  # called by a queue to tell the workerstarter to start workers
  def queue_available(queue, node) do
    GenServer.cast({Processes.process(queue, __MODULE__), node}, {:queue_available, self()})
  end

  def start_link(queue) do
    GenServer.start_link(__MODULE__, queue, name: Processes.process(queue, __MODULE__))
  end

  def init(queue) do
    queue
    |> Processes.get_queues()
    |> Enum.each(&WorkerGroupSupervisor.start_worker_group(queue, &1))

    {:ok, queue}
  end

  def handle_cast({:queue_available, queue_pid}, queue) do
    Logger.info "[Honeydew] Queue process #{inspect queue_pid} from #{inspect queue} on node #{node(queue_pid)} became available, starting workers ..."

    {:ok, _} = WorkerGroupSupervisor.start_worker_group(queue, queue_pid)

    {:noreply, queue}
  end
end
