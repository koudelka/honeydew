defmodule Honeydew.WorkerGroupSupervisor do
  alias Honeydew.{WorkerSupervisor, NodeMonitorSupervisor}

  def start_link(queue, module, args, num_workers, init_retry_secs, shutdown, nodes) do
    import Supervisor.Spec

    children = [supervisor(WorkerSupervisor, [queue, module, args, num_workers, init_retry_secs, shutdown])]

    opts = [strategy: :one_for_one,
            name: Honeydew.supervisor(queue, :worker_group)]

    queue
    |> case do
         {:global, _} -> children ++ [supervisor(NodeMonitorSupervisor, [queue, nodes])]
         _ -> children
       end
    |> Supervisor.start_link(opts)
  end
end
