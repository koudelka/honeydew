defmodule Honeydew.WorkerGroupSupervisor do
  alias Honeydew.{QueueMonitor, WorkerSupervisor}

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, opts}
    }
  end

  def start_link(queue, opts, queue_pid) do
    children = [
      QueueMonitor.child_spec([self(), queue_pid], queue: queue),
      {WorkerSupervisor, [queue, opts, queue_pid]}
    ]

    supervisor_opts = [strategy: :one_for_one,
                       name: Honeydew.supervisor(queue, :worker_group)]

    Supervisor.start_link(children, supervisor_opts)
  end
end
