# when a queue dies, this process hears about it and stops its associated worker group.
defmodule Honeydew.QueueMonitor do
  use GenServer
  require Logger

  defmodule State do
    defstruct [:workers_per_queue_pid, :queue_pid]
  end

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  def init([workers_per_queue_pid, queue_pid]) do
    Process.monitor(queue_pid)
    {:ok, %State{workers_per_queue_pid: workers_per_queue_pid, queue_pid: queue_pid}}
  end

  def handle_info({:DOWN, _, _, queue_pid, _}, %State{workers_per_queue_pid: workers_per_queue_pid, queue_pid: queue_pid} = state) do
    Logger.info "[Honeydew] Queue process #{inspect queue_pid} on node #{node queue_pid} stopped, stopping local workers."

    Supervisor.stop(workers_per_queue_pid)

    {:noreply, state}
  end

  def handle_info(msg, state) do
    Logger.warn "[QueueMonitor] Received unexpected message #{inspect msg}"
    {:noreply, state}
  end
end
