# when a queue comes online (or its node connects), it sends a message to this process to start workers.
defmodule Honeydew.WorkerStarter do
  use GenServer
  alias Honeydew.WorkerGroupSupervisor
  require Logger

  def start_link(queue) do
    GenServer.start_link(__MODULE__, queue, name: Honeydew.process(queue, __MODULE__))
  end

  def init(queue) do
    # this process starts after the WorkerGroupSupervisor, so we can send it start requests
    queue
    |> Honeydew.get_all_queues
    |> Enum.each(&WorkerGroupSupervisor.start_worker_group(queue, &1))

    {:ok, queue}
  end

  def handle_cast({:queue_available, queue_pid}, queue) do
    Logger.info "[Honeydew] Queue #{inspect queue_pid} from #{inspect queue} on node #{node(queue_pid)} became available, starting workers ..."

    {:ok, _} = WorkerGroupSupervisor.start_worker_group(queue, queue_pid)

    {:noreply, queue}
  end

end
