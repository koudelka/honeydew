defmodule Honeydew.WorkerGroupSupervisor do
  alias Honeydew.{QueueMonitor, WorkerSupervisor}

  def start_link(queue, opts, queue_pid) do
    import Supervisor.Spec

    children = [worker(QueueMonitor, [self(), queue_pid]),
                supervisor(WorkerSupervisor, [queue, opts, queue_pid])]

    supervisor_opts = [strategy: :one_for_one,
                       name: Honeydew.supervisor(queue, :worker_group)]

    Supervisor.start_link(children, supervisor_opts)
  end
end
