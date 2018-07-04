# when a queue comes online (or its node connects), it sends a message to this process to start workers.
defmodule Honeydew.WorkerStarter do
  use GenServer
  alias Honeydew.WorkerGroupsSupervisor
  require Logger

  def start_link(queue) do
    GenServer.start_link(__MODULE__, queue, name: Honeydew.process(queue, :worker_starter))
  end

  def init(queue) do
    # this process starts after the WorkerGroupsSupervisor, so we can send it start requests
    queue
    |> Honeydew.get_all_queues
    |> Enum.each(&WorkerGroupsSupervisor.start_group(queue, &1))

    {:ok, queue}
  end

  def handle_cast({:queue_available, queue_pid}, queue) do
    Logger.info "[Honeydew] Queue #{inspect queue_pid} from #{inspect queue} on node #{node(queue_pid)} became available, starting workers ..."

    {:ok, _} = WorkerGroupsSupervisor.start_group(queue, queue_pid)

    {:noreply, queue}
  end

end
