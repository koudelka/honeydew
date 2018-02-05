# when a queue dies, this process hears about it and stops its associated worker group.
defmodule Honeydew.QueueMonitor do
  use GenServer
  require Logger

  defmodule State do
    defstruct [:worker_group_pid, :queue_pid]
  end

  def start_link(worker_group_pid, queue_pid) do
    GenServer.start_link(__MODULE__, [worker_group_pid, queue_pid])
  end

  def init([worker_group_pid, queue_pid]) do
    Process.monitor(queue_pid)
    {:ok, %State{worker_group_pid: worker_group_pid, queue_pid: queue_pid}}
  end

  def handle_info({:DOWN, _, _, queue_pid, _}, %State{worker_group_pid: worker_group_pid, queue_pid: queue_pid} = state) do
    Logger.info "[QueueMonitor] Queue process #{inspect queue_pid} from node #{node queue_pid} stopped, stopping local workers."

    Supervisor.stop(worker_group_pid)

    {:noreply, state}
  end

  def handle_info(msg, state) do
    Logger.warn "[QueueMonitor] Received unexpected message #{inspect msg}"
    {:noreply, state}
  end
end
