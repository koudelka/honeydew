defmodule Honeydew.WorkersPerQueueSupervisor do
  use Supervisor, restart: :transient
  alias Honeydew.WorkerSupervisor
  alias Honeydew.QueueMonitor

  def start_link(queue, opts, queue_pid) do
    Supervisor.start_link(__MODULE__, [queue, opts, queue_pid], [])
  end

  @impl true
  def init([queue, opts, queue_pid]) do
    [
      {WorkerSupervisor, [queue, opts, queue_pid]},
      {QueueMonitor, [self(), queue_pid]}
    ]
    |> Supervisor.init(strategy: :rest_for_one)
  end
end
