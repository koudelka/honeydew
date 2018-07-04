defmodule Honeydew.WorkerGroupSupervisor do
  use Supervisor
  alias Honeydew.QueueMonitor
  alias Honeydew.WorkerSupervisor

  def start_link(queue, args, queue_pid) do
    opts = [name: Honeydew.supervisor(queue, :worker_group)]
    Supervisor.start_link(__MODULE__, [queue, args, queue_pid], opts)
  end

  @impl true
  def init([queue, opts, queue_pid]) do
    children = [
      {QueueMonitor, [self(), queue_pid]},
      {WorkerSupervisor, [queue, opts, queue_pid]}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
